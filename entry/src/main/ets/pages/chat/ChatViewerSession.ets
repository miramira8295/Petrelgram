import { MessageEntry } from '../../store/MessageEntry';
import { AlbumGroup, albumIndexOfMember, albumSiblingIds } from '../../util/collapseAlbums';
import { mediaEntryIsPhoto, mediaEntryIsVideo } from '../../util/mediaEntryKind';
import { MEDIA_VIEWING_PRIORITY } from '../../util/downloadPriority';
import { KEY_POWER_SMOOTH_TRANSITIONS } from '../../store/AppSettings';
import { promptAction } from '@kit.ArkUI';
import { ViewerUnderlay } from '../../util/viewerUnderlay';
import { logI } from '../../util/log';
import { MessageStore } from '../../store/MessageStore';
import { VIEWER_CHROME_ON_OPEN } from './MediaViewerOverlay';

export interface ChatViewerSessionHost {
  onTargetChanged: () => void;
  store: () => MessageStore | null;
  entryById: (messageId: number) => MessageEntry | null;
  messages: () => MessageEntry[];
  groups: () => AlbumGroup[];
  effectDuration: (key: string, duration: number) => number;
  logOpen: () => void;
  unlockPaidMedia: (messageId: number) => void;
  handoffToViewer: (messageId: number) => number;
  handoffFromViewer: (messageId: number, albumIndex: number, positionMs: number) => void;
  resumePrefetch: () => void;
  armPlaySlotSettle: () => void;
  exitLandscape: () => void;

}

/**
 * State owned by one ChatPage's media viewer lifetime.
 *
 * MediaViewerOverlay remains the visual/gesture owner. This object owns the
 * page-side handoff state so opening, swiping and closing cannot leave a
 * playback request or animation decision in a separate page field.
 */
@ObservedV2
export class ChatViewerSession {
  @Trace viewerMsgId: number = 0;
  @Trace chromeVisible: boolean = VIEWER_CHROME_ON_OPEN;
  @Trace viewerVideoLandscape: boolean = false;
  @Trace viewerClosing: boolean = false;
  @Trace pausedAnimationIds: number[] = [];
  @Trace forcedAnimationIds: number[] = [];
  @Trace failedAnimationIds: number[] = [];

  viewerInitIdx: number = 0;
  viewerPositionMs: number = 0;
  viewerStartPositionMs: number = 0;

  @Trace underlayHidden: boolean = false;
  readonly underlay: ViewerUnderlay = new ViewerUnderlay((hidden: boolean): void => {
    this.underlayHidden = hidden;
    logI(`[ViewerUnderlay] hidden=${hidden}`);
  });

  private playbackRequestedIds: number[] = [];
  private host: ChatViewerSessionHost = {
    store: (): MessageStore | null => null,
    entryById: (_id: number): MessageEntry | null => null,
    messages: (): MessageEntry[] => [],
    groups: (): AlbumGroup[] => [],
    effectDuration: (_key: string, duration: number): number => duration,
    logOpen: (): void => {},
    unlockPaidMedia: (_id: number): void => {},
    handoffToViewer: (_id: number): number => 0,
    handoffFromViewer: (_id: number, _index: number, _position: number): void => {},
    resumePrefetch: (): void => {},
    armPlaySlotSettle: (): void => {},
    exitLandscape: (): void => {},
    onTargetChanged: (): void => {}
  };

  bind(host: ChatViewerSessionHost): void {
    this.host = host;
  }

  setTarget(messageId: number): void {
    if (this.viewerMsgId === messageId) { return; }
    this.viewerMsgId = messageId;
    this.viewerPositionMs = 0;
    this.host.onTargetChanged();
  }

  setChromeVisible(visible: boolean): void {
    this.chromeVisible = visible;
  }

  setVideoLandscape(landscape: boolean): void {
    this.viewerVideoLandscape = landscape;
  }

  viewerOpen(): boolean {
    return this.viewerMsgId !== 0;
  }

  open(messageId: number): void {
    if (this.viewerClosing) {
      return;
    }
    // 平板黑屏 / 顶栏横幅（#201）：查看器现在单栏、分栏都在页面内；分栏时另外收左栏和
    // 侧边页签盖满窗口（见 util/viewerWindowCover）。打点保留，对照下一份平板日志用。
    this.host.logOpen();
    const entry = this.host.entryById(messageId);
    if (entry === null) {
      return;
    }
    if (entry.contentType === 'paidMedia' && entry.paidMediaLocked) {
      this.host.unlockPaidMedia(messageId);
      return;
    }
    if (!mediaEntryIsPhoto(entry) && !mediaEntryIsVideo(entry)) {
      return;
    }
    if (mediaEntryIsPhoto(entry) && entry.photoPath === '' && entry.photoFailed) {
      this.host.store()?.retryPhoto(messageId);
      promptAction.showToast({ message: $r('app.string.cp_reloading_thumb'), duration: 1200 });
      return;
    }
    if (mediaEntryIsPhoto(entry) && entry.photoPath === '' &&
      entry.photoFullPath === '' && entry.photoFileId === 0 && entry.photoFullFileId === 0) {
      promptAction.showToast({ message: $r('app.string.cp_photo_unavailable'), duration: 1500 });
      return;
    }
    if (mediaEntryIsVideo(entry)) {
      if (entry.videoFileId === 0 && entry.videoPath === '') {
        promptAction.showToast({ message: $r('app.string.cp_video_unavailable'), duration: 1500 });
        return;
      }
      // A cover failure must not block a playable video. Retry it quietly so
      // the viewer can gain a poster while the stream starts.
      if (entry.photoPath === '' && entry.photoFailed) {
        this.host.store()?.retryPhoto(messageId);
      }
      // Streaming needs a total size for byte ranges. If TDLib hasn't supplied
      // one yet, finish a normal download first instead of opening a viewer
      // that can only report "无法获取视频大小".
      if (entry.videoPath === '' && entry.videoFileSize <= 0) {
        // 为看而下，不是为留而下：走 requestVideoForPlayback，关掉播放器时
        // releaseVideoPlayback 才能真的把它停下来。
        this.host.store()?.requestVideoForPlayback(messageId, entry.videoFailed);
        this.notePlaybackRequest(messageId);
        promptAction.showToast({ message: $r('app.string.cp_fetching_video'), duration: 1800 });
        return;
      }
      if (entry.videoFailed) {
        // A failed autoplay/save download is recoverable and doesn't prevent
        // the independent streaming player from opening immediately.
        this.host.store()?.requestVideoDownload(messageId, false, true);
      }
    }
    // 【为什么是 SMOOTH_TRANSITIONS 而不是 EFFECT_BLUR】
    // 气泡↔全屏的一镜到底（geometryTransition）时长原本挂在
    // KEY_POWER_EFFECT_BLUR 上，而那个键在 AppSettings 的
    // POWER_BOOLEAN_FALSE_DEFAULTS 里——**出厂默认就是关的**，于是 duration 恒为 0，
    // 几何过渡没有时间可跑，表现是硬切。这套动画自 a118a87(2026-08-18) 落地起，
    // 在默认设置下**从来没生效过**，用户报的"没有定点放大缩小动画"就是这个。
    //
    // 换到 KEY_POWER_SMOOTH_TRANSITIONS（默认 true）也更符合文案：设置里那一项
    // 叫「模糊与缩放效果」，指的是毛玻璃那一档；用户为省电关掉模糊，不该静默
    // 失去一镜到底且毫无提示。省电模式激活时仍然归零（powerFeatureEnabled 里
    // 的 && !powerSavingActive()），这条没变。
    //
    // 查看器**内部**那 9 处动画（chrome 淡入、缩放复位等）仍留在 EFFECT_BLUR 下
    // ——它们确实属于"模糊与缩放效果"。
    animateTo({ duration: this.host.effectDuration(KEY_POWER_SMOOTH_TRANSITIONS, 300), curve: Curve.Friction }, () => {
      this.onMediaTap(messageId);
    });
  }

  close(): void {
    if (!this.viewerOpen() || this.viewerClosing) {
      return;
    }
    this.underlay.prepareClose();
    // ⚠️ [Viewer] 探针（S4）：查看器这一簇此前在 hilog 黄金样本里一个标签都没有，
    // S5/S6 改的是生命周期与挂载方式，本地单测证不了——这三条打点是那两批唯一的
    // 验收证据。删除条件：S6 落地并通过黄金样本 diff 之后，随第二轮 §8 的探针
    // 收尾批一起清。
    this.releasePlaybackRequests(this.host.store());
    this.exitLandscape();
    // 交接:把查看器最终播放到的位置写回气泡进度表，并把这条 pin 成播放位——
    // 用户刚看完的这条回到列表后应当继续播。取值/计算都要在 viewerMsgId 被
    // animateTo 里的回调清零之前完成。
    const viewerMessageId = this.viewerMsgId;
    // 交接必须留在 animateTo 之前：setTarget() 会在
    // viewerMsgId 归零那一刻同步把 viewerPositionMs 清成 0，挪到后面就永远记 0。
    const handoffAlbumIdx: number = albumIndexOfMember(this.host.groups(), viewerMessageId);
    this.host.handoffFromViewer(viewerMessageId, handoffAlbumIdx, this.viewerPositionMs);
    this.host.resumePrefetch();
    // 与打开同一把闸，理由见 openViewer 里那段说明。
    const duration: number = this.host.effectDuration(KEY_POWER_SMOOTH_TRANSITIONS, 260);
    this.viewerClosing = true;
    animateTo({ duration, curve: Curve.Friction }, () => {
      this.setTarget(0);
      this.viewerInitIdx = 0;
      // 复位到下一次打开的初值。openViewer 里也会写一次，这里写同一个常量只是
      // 不留下"关闭后是 true、打开时又变 false"的中间态。
      this.chromeVisible = VIEWER_CHROME_ON_OPEN;
    });
    // 查看器关掉了，重新喂一次"已停止"把播放位判定跑起来。候选表这一刻
    // 可能还是空的（open 时 reset() 清空过，且几何没变不会自然重新上报），
    // 那就先选不出来——下一次真正的滚动/新消息到达会用同一个幂等方法再补
    // 一次，不会永久卡住。pin() 记的目标在候选表补上之前一样选不出来，
    // 是同一个幂等收敛，不需要额外处理。
    this.host.armPlaySlotSettle();
    setTimeout((): void => { this.viewerClosing = false; }, Math.max(80, duration));
  }

  exitLandscape(): void {
    if (!this.viewerVideoLandscape) {
      return;
    }
    this.viewerVideoLandscape = false;
    this.host.exitLandscape();
  }

  private onMediaTap(messageId: number): void {
    const store = this.host.store();
    if (store === null) { return; }
    const idx = this.host.messages().findIndex((m: MessageEntry) => m.id === messageId);
    if (idx < 0) {
      return;
    }
    const m = this.host.messages()[idx];
    if (!mediaEntryIsPhoto(m) && !mediaEntryIsVideo(m)) {
      return;
    }
    if (mediaEntryIsPhoto(m)) {
      // 用户刚点开这张图，它就是"现在就要看到"的那一个——最高档。
      store.requestFullPhoto(messageId, false, MEDIA_VIEWING_PRIORITY);
    }
    // 交接:取气泡播放位记录的进度，必须在 playSlots.suspend() 让气泡播放器
    // 卸载之前完成——bubblePositionMs 本身不受 suspend() 影响，但卸载之后
    // 气泡播放器不会再有新的 onPositionChanged，读早读晚不影响这一次的值；
    // 保险起见仍然按“先取、后卸载”的顺序写。
    this.viewerStartPositionMs = this.host.handoffToViewer(messageId);
    // ⚠️ [Viewer] 探针（S4）。删除条件见 closeViewer 里那条。
    // Position the viewer Swiper on the tapped album member.
    const sib = albumSiblingIds(this.host.groups(), messageId);
    this.viewerInitIdx = Math.max(0, sib.indexOf(messageId));
    // 挂载查看器必须在 animateTo 闭包里：geometryTransition 只在动画闭包中
    // 改变绑定节点的存在性时才会做几何过渡，直接赋值就是瞬间出现（关闭那侧
    // 早就这么写了，见 closeViewer）。
    animateTo({
      duration: this.host.effectDuration(KEY_POWER_SMOOTH_TRANSITIONS, 300),
      curve: Curve.Friction
    }, (): void => {
      this.setTarget(messageId);
    });
    this.chromeVisible = VIEWER_CHROME_ON_OPEN;
    this.viewerVideoLandscape = false;
    this.viewerClosing = false;
  }

  notePlaybackRequest(messageId: number): void {
    if (this.playbackRequestedIds.indexOf(messageId) < 0) {
      this.playbackRequestedIds = [...this.playbackRequestedIds, messageId];
    }
  }

  releasePlaybackRequests(store: MessageStore | null): void {
    const ids: number[] = this.playbackRequestedIds;
    this.playbackRequestedIds = [];
    if (store === null) {
      return;
    }
    for (const id of ids) {
      store.releaseVideoPlayback(id);
    }
  }

  resetAnimationState(): void {
    this.pausedAnimationIds = [];
    this.forcedAnimationIds = [];
    this.failedAnimationIds = [];
  }

  animationPaused(messageId: number): boolean {
    return this.pausedAnimationIds.indexOf(messageId) >= 0;
  }

  animationForcePlay(messageId: number): boolean {
    return this.forcedAnimationIds.indexOf(messageId) >= 0;
  }

  animationPlaybackFailed(messageId: number): boolean {
    return this.failedAnimationIds.indexOf(messageId) >= 0;
  }

  requestAnimationPlayback(messageId: number): void {
    this.pausedAnimationIds = this.withoutId(this.pausedAnimationIds, messageId);
    this.failedAnimationIds = this.withoutId(this.failedAnimationIds, messageId);
    if (!this.animationForcePlay(messageId)) {
      this.forcedAnimationIds = [...this.forcedAnimationIds, messageId];
    }
  }

  markAnimationPlaybackFailed(messageId: number): void {
    if (!this.animationPlaybackFailed(messageId)) {
      this.failedAnimationIds = [...this.failedAnimationIds, messageId];
    }
    this.forcedAnimationIds = this.withoutId(this.forcedAnimationIds, messageId);
    if (!this.animationPaused(messageId)) {
      this.pausedAnimationIds = [...this.pausedAnimationIds, messageId];
    }
  }

  private withoutId(ids: number[], messageId: number): number[] {
    return ids.filter((id: number): boolean => id !== messageId);
  }
}
