import { MessageTextPresentationCache } from '../../util/messageTextInput';
import { MessageEntry } from '../../store/MessageEntry';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleContext, MessageBubbleShell } from './MessageBubbleShell';
import { MessageBubbleText } from './MessageBubbleText';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { LiveThumbImage } from './LiveThumbImage';
import { LiveProgressRing } from './LiveProgressRing';
import { ThumbReadyGate } from './ThumbReadyGate';
import { EntryVideoFileRef, entryInlineFile } from '../../util/entryVideoVariant';
import { mediaBoxFor, MediaBox, BUBBLE_AVATAR_GUTTER_VP } from '../../util/mediaBox';
import { thumbBackdropColor } from '../../util/thumbBackdrop';
import { miniPlaceholderOf } from '../../util/miniThumbPlaceholder';
import { isLivePhotoVideo } from '../../util/livePhoto';
import { formatFileSize } from '../../util/formatFileSize';
import { formatMediaDuration } from '../../util/mediaDuration';
import { str } from '../../util/strings';

import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, slotKey } from './playSlot';

// 完整的单图片/视频/GIF 路径：公共壳 + 媒体 + 配文。
// 只订阅自身的缩略图/视频进度，播放可见性与候选生命周期也在此归属。
@ComponentV2
export struct SingleMediaBubble {
  private textInputCache: MessageTextPresentationCache = new MessageTextPresentationCache();
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private context: MessageBubbleContext = new MessageBubbleContext();
  private env: ChatEnvMirror = chatEnv;
  @Local private livePhotoProgress: number = 0;
  @Local private liveVideoProgress: number = 0;
  @Local private mediaVisible: boolean = true;
  private mediaCenterY: number = 0;
  private attachedRowId: number = 0;
  private attachedPhotoFileId: number = 0;
  private attachedVideoFileId: number = 0;
  private unsubPhotoProgress: (() => void) | null = null;
  private unsubVideoProgress: (() => void) | null = null;
  private competingMessageId: number = 0;

  private seedProgress(): void {
    this.livePhotoProgress = progressForOr(this.msg.photoFileId, this.msg.photoProgress);
    this.liveVideoProgress = progressForOr(this.msg.videoFileId, this.msg.videoProgress);
  }

  private attachProgress(): void {
    this.detachProgress();
    this.seedProgress();
    if (this.msg.photoFileId !== 0) {
      this.unsubPhotoProgress = subscribeProgress(this.msg.photoFileId,
        (percent: number): void => { this.livePhotoProgress = percent; });
    }
    if (this.msg.videoFileId !== 0) {
      this.unsubVideoProgress = subscribeProgress(this.msg.videoFileId,
        (percent: number): void => { this.liveVideoProgress = percent; });
    }
    this.attachedRowId = this.msg.rowId;
    this.attachedPhotoFileId = this.msg.photoFileId;
    this.attachedVideoFileId = this.msg.videoFileId;
  }

  private detachProgress(): void {
    if (this.unsubPhotoProgress !== null) {
      this.unsubPhotoProgress();
      this.unsubPhotoProgress = null;
    }
    if (this.unsubVideoProgress !== null) {
      this.unsubVideoProgress();
      this.unsubVideoProgress = null;
    }
    this.attachedRowId = 0;
  }

  private releaseCandidate(): void {
    const previousId: number = this.competingMessageId;
    this.competingMessageId = 0;
    if (previousId !== 0) { this.actions.onMediaGone(previousId, -1); }
  }

  private syncCandidate(): void {
    const nextId: number = this.msg.contentType === 'video' && !this.msg.isAnimation ? this.msg.id : 0;
    if (nextId !== this.competingMessageId) {
      this.releaseCandidate();
      this.competingMessageId = nextId;
    }
  }

  aboutToAppear(): void {
    this.attachProgress();
    this.syncCandidate();
    this.requestAutoplayDownload();
  }

  aboutToDisappear(): void {
    this.detachProgress();
    this.releaseCandidate();
  }

  aboutToRecycle(): void {
    this.detachProgress();
    this.releaseCandidate();
    this.mediaCenterY = 0;
  }

  aboutToReuse(): void {
    this.releaseCandidate();
    this.mediaCenterY = 0;
    this.attachProgress();
    this.syncCandidate();
    this.requestAutoplayDownload();
  }

  @Monitor('msg')
  onMessageChanged(): void {
    if (this.attachedRowId !== this.msg.rowId) {
      this.releaseCandidate();
      this.mediaCenterY = 0;
      if (!this.mediaVisible) { this.mediaVisible = true; }
    }
    if (this.attachedRowId !== this.msg.rowId || this.attachedPhotoFileId !== this.msg.photoFileId ||
      this.attachedVideoFileId !== this.msg.videoFileId) {
      this.attachProgress();
    } else {
      this.seedProgress();
    }
    // 包括临时 id → 真实 id，以及普通视频 → GIF 的原地替换。
    this.syncCandidate();
  }

  private isPlaySlot(): boolean {
    return this.data.playSlotKey !== '' && !this.msg.isAnimation &&
      this.data.playSlotKey === slotKey(this.msg.id, -1);
  }

  private autoplayInlineVideo(): boolean {
    if (this.msg.contentType !== 'video' || !this.msg.isAnimation || this.msg.videoPath === '' ||
      !this.mediaVisible || !this.env.appIsForeground || this.data.animationPlaybackFailed) {
      return false;
    }
    if (this.data.animationPaused) { return false; }
    return this.data.animationForcePlay || (!this.env.powerSaving && !this.env.reduceAnim && this.env.autoplayGif);
  }

  private requestAutoplayDownload(): void {
    if (this.msg.contentType !== 'video' || this.msg.videoFileId === 0 ||
      this.msg.videoPath !== '' || this.msg.videoFailed || !this.mediaVisible) {
      return;
    }
    // 普通视频保持播放位分片策略；只有 GIF 允许自动整文件下载。
    if (!this.msg.isAnimation) { return; }
    if ((this.env.autoplayGif && !this.env.powerSaving && !this.env.reduceAnim) || this.data.animationForcePlay) {
      this.actions.onAutoplayVideoNeedDownload(this.msg.id);
    }
  }

  @Monitor('env.reduceAnim', 'env.powerSaving', 'env.autoplayGif')
  onPlaybackPolicyChanged(): void {
    this.requestAutoplayDownload();
  }

  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }

  private formatDuration(totalSeconds: number): string {
    return formatMediaDuration(totalSeconds);
  }

  private videoFileUnavailable(): boolean {
    return this.msg.contentType === 'video' &&
      this.msg.videoFileId === 0 && this.msg.videoPath === '';
  }

  private videoDownloadActive(): boolean {
    return this.msg.videoPath === '' &&
      this.liveVideoProgress > 0 && this.liveVideoProgress < 100;
  }

  private videoMetaText(): string {
    if (this.msg.isAnimation) {
      return this.msg.videoDuration > 0
        ? `GIF · ${this.formatDuration(this.msg.videoDuration)}`
        : 'GIF';
    }
    // 时长和大小一起显示（issue #93）：只有时长时看不出这条视频要下多少。
    // 大小的位置再换成缓存状态（2026-09-15）：下完了写「已缓存」，正在下写百分比——后台缓存的进度
    // 也经 mediaProgressChannel 到这里（services/BackgroundCache）。
    const parts: string[] = [];
    if (this.msg.videoDuration > 0) {
      parts.push(this.formatDuration(this.msg.videoDuration));
    }
    if (this.msg.videoPath !== '') {
      parts.push(str('mb_video_cached'));
    } else if (this.videoDownloadActive()) {
      parts.push(`${this.liveVideoProgress}%`);
    } else if (this.msg.videoFileSize > 0) {
      parts.push(formatFileSize(this.msg.videoFileSize));
    }
    return parts.join(' · ');
  }

  private videoAccessibilityText(): string {
    if (this.msg.isAnimation) {
      if (this.videoFileUnavailable()) {
        return str('mb_gif_unavailable');
      }
      if (this.msg.videoFailed || this.data.animationPlaybackFailed) {
        return str('mb_gif_failed');
      }
      if (this.videoDownloadActive() || this.animationDownloadExpected()) {
        return this.liveVideoProgress > 0
          ? str('mb_gif_downloaded_pct', this.liveVideoProgress)
          : str('mb_gif_loading');
      }
      return this.autoplayInlineVideo() ? str('mb_gif_playing') : str('mb_gif_paused');
    }
    if (this.videoFileUnavailable()) {
      return str('mb_video_unavailable');
    }
    if (this.msg.videoFailed) {
      return str('mb_video_failed');
    }
    if (this.videoDownloadActive()) {
      return str('mb_video_downloaded_pct', this.liveVideoProgress);
    }
    if (this.msg.photoFailed) {
      return str('mb_video_cover_failed');
    }
    return this.msg.videoDuration > 0
      ? str('mb_video_duration', this.formatDuration(this.msg.videoDuration))
      : str('mb_tap_play_video');
  }

  private mediaBox(): MediaBox {
    return mediaBoxFor(this.data.contentWidth, this.msg.photoWidth, this.msg.photoHeight,
      this.msg.contentType === 'video', this.avatarReserve());
  }

  @Builder
  mediaLoadState(size: number, fileId: number, initialPercent: number, failed: boolean) {
    if (failed) {
      Column({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(Math.max(17, size * 0.5))
          .fontColor([Color.White]);
        Text($r('app.string.settings_retry')).fontSize(11).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor('#80000000').borderRadius(18);
    } else {
      // 进度不进 key，环自己订阅自己更新（见 LiveProgressRing / collapseAlbums）。
      LiveProgressRing({ fileId: fileId, initialPercent: initialPercent, ringSize: size });
    }
  }

  @Builder
  liveChip() {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.livephoto')).fontSize(12).fontColor([Color.White]);
      Text($r('app.string.cp_live_photo'))
        .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
    }
    .height(18)
    .padding({ left: 5, right: 6 })
    .backgroundColor('#66000000')
    .borderRadius(9)
    .position({ x: 6, y: 6 });
  }

  @Builder
  singleMediaPlaceholder(hasFile: boolean) {
    Stack() {
      Column().width(this.mediaBox().width).height(this.mediaBox().height).borderRadius(8)
        .backgroundColor(thumbBackdropColor(this.msg.contentType === 'video'));
      if (this.msg.contentType === 'video') {
        // Wait only when a real thumbnail file exists. Videos without a
        // cover remain playable and get the normal play control below.
        if (hasFile && !this.msg.photoFailed) {
          this.mediaLoadState(36, this.msg.photoFileId, this.livePhotoProgress, false);
        }
      } else {
        this.mediaLoadState(36, this.msg.photoFileId, this.livePhotoProgress,
          this.msg.photoFailed || !hasFile);
      }
    }.width(this.mediaBox().width).height(this.mediaBox().height);
  }

  private msgIsLivePhoto(): boolean {
    return this.msg.contentType === 'video' &&
      isLivePhotoVideo(this.msg.videoFileName, this.msg.videoDuration);
  }

  @Builder
  videoActionBadge(size: number) {
    Stack() {
      Circle({ width: size, height: size }).fill('#78000000')
        .stroke('#24FFFFFF').strokeWidth(1);
      if (this.videoDownloadActive()) {
        Progress({ value: this.liveVideoProgress, total: 100, type: ProgressType.Ring })
          .width(size).height(size).color(Color.White);
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(size * 0.34).fontColor([Color.White]).margin({ left: 2 });
      } else if (this.msg.isAnimation && this.animationDownloadExpected()) {
        LoadingProgress().width(size * 0.62).height(size * 0.62).color(Color.White);
      } else if (this.msg.videoFailed || this.data.animationPlaybackFailed) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(size * 0.4).fontColor([Color.White]);
      } else if (this.videoFileUnavailable()) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(size * 0.4).fontColor([Color.White]);
      } else {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(size * 0.42).fontColor([Color.White]).margin({ left: 2 });
      }
    }
    .width(size).height(size)
    .animation({ duration: this.effectDuration(160), curve: Curve.EaseOut });
  }

  private thumbnailRetryable(): boolean {
    return this.msg.photoPath === '' && this.msg.photoFailed && this.msg.photoFileId !== 0;
  }

  private inlineVideoFile(): EntryVideoFileRef {
    const f: EntryVideoFileRef | null = entryInlineFile(this.msg);
    return f !== null ? f : { fileId: this.msg.videoFileId, fileSize: this.msg.videoFileSize, local: false };
  }

  private animationDownloadExpected(): boolean {
    return this.msg.isAnimation && this.msg.videoFileId !== 0 &&
      this.msg.videoPath === '' && !this.msg.videoFailed &&
      (this.data.animationForcePlay || (!this.env.powerSaving && !this.env.reduceAnim && this.env.autoplayGif));
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  @Builder
  media() {
    Stack() {
      if (this.isPlaySlot() && this.msg.contentType === 'video' && this.msg.videoFileId !== 0) {
        // 播放位气泡：只有滚动停下、被选中的这一条才挂流式播放器。
        // 小窗播低清那一档（多清晰度，见 util/entryVideoVariant.entryInlineFile）。
        VideoBubbleSurface({
          fileId: this.inlineVideoFile().fileId,
          fileSize: this.inlineVideoFile().fileSize,
          mimeType: this.msg.videoMimeType,
          sourceWidth: this.msg.photoWidth,
          sourceHeight: this.msg.photoHeight,
          posterPath: this.msg.photoPath,
          muted: this.data.autoplayMuted,
          startPositionMs: this.data.playSlotStartMs,
          onPositionChanged: (positionMs: number): void => {
            this.actions.onPlaySlotPositionChanged(this.msg.id, -1, positionMs);
          },
          onEnded: (): void => {
            this.actions.onPlaySlotEnded(this.msg.id, -1);
          }
        })
          .width(this.mediaBox().width).height(this.mediaBox().height)
          // 渲染面在内嵌档是 Cover（填满并溢出，见 StreamingVideoPlayer
          // .surfaceFillsViewport），没有 clip 就会画到气泡外面去。
          // 相册格那处本来就有，这里是补的。
          .clip(true)
          // 播放位没有手势层，但底层 XComponent 会默认吃掉点击——和下面
          // SmartLoopVideo 同理，交给外层 Stack 的 onClick 打开全屏查看器。
          .hitTestBehavior(HitTestMode.None);
      } else if (this.autoplayInlineVideo()) {
        SmartLoopVideo({
          videoPath: this.msg.videoPath,
          thumbPath: this.msg.photoPath,
          boxWidth: this.mediaBox().width,
          boxHeight: this.mediaBox().height,
          powerCategory: 'gif',
          // 滑动时暂停而不是卸载（用户报"滑动时 GIF 闪一下"）。会话内的
          // GIF 跟贴纸走同一道闸，见 SmartLoopVideo.scrollGated。
          scrollGated: true,
          forcePlay: this.msg.isAnimation && this.data.animationForcePlay,
          onPlaybackFailed: (): void => {
            if (this.msg.isAnimation) {
              this.actions.onAnimationPlaybackFailed(this.msg.id);
            }
          }
        })
          // Native texture components can otherwise consume the tap before
          // the media wrapper gets a chance to toggle GIF pause/play.
          .hitTestBehavior(HitTestMode.None);
      } else if (this.msg.photoFileId !== 0 || this.msg.photoPath !== '') {
        // Keep the thumbnail mounted while fullscreen preview is open. ArkUI's
        // geometry transition can re-parent this Image node; with LazyForEach
        // recycling that occasionally restored only the placeholder/background
        // or an undecoded blank node after returning to the chat.
        // No appear transition here. A LazyForEach CHANGE rebuilds this
        // subtree, so the Image comes back as a new node and any appear
        // transition replays — during a download that fired at the updateFile
        // rate and read as the thumbnail flickering. The row key now buckets
        // progress (see collapseAlbums.progressBucket), but a rebuild is still
        // normal for every other field, and a thumbnail must not blink on one.
        // Decoded through the PixelMap cache: DMA memory so the first draw
        // costs no texture upload on the render thread, and desiredSize
        // downsamples during the decode rather than after it.
        // Self-subscribing: the row key no longer carries the path, so this
        // node must react to the thumbnail landing on its own.
        // The condition can't be fileId-only: MessageStore backfills
        // photoPath from the full-size download while photoFileId can still
        // be 0, and losing the path there would regress an already
        // downloaded photo to a dead "retry" tile.
        LiveThumbImage({
          spec: {
            syncDisplay: true,
            fileId: this.msg.photoFileId,
            initialPath: this.msg.photoPath,
            boxWidth: this.mediaBox().width,
            boxHeight: this.mediaBox().height,
            radius: 8,
            fit: this.msg.contentType === 'photo' ? ImageFit.Contain : ImageFit.Cover,
            // 单张大图不开 565：面积大、渐变明显。
            opaque: false,
            // 和 singleMediaPlaceholder 的底色同源（见 util/thumbBackdrop）。
            backdrop: thumbBackdropColor(this.msg.contentType === 'video'),
            mini: miniPlaceholderOf(this.msg.photoMini)
          },
          placeholder: (): void => {
            this.singleMediaPlaceholder(this.msg.photoFileId !== 0);
          }
        });
      } else {
        this.singleMediaPlaceholder(false);
      }
      // 出站发送中：图上叠一个上传环（LiveProgressRing 按 fileId 自己订阅通道，
      // 0% 时转圈）。照片上传的是照片文件本身，视频上传的是视频文件。
      if (this.context.liveSendState === 'sending') {
        LiveProgressRing({
          fileId: this.msg.contentType === 'video' ? this.msg.videoFileId : this.msg.photoFileId,
          initialPercent: 0,
          ringSize: Math.min(44, Math.min(this.mediaBox().width, this.mediaBox().height) * 0.3)
        });
      }
        // **实况不画播放钮。** 它已经有自己的「实况」角标（liveChip），
        // 交互也不是"点一下播放"而是长按即播（见 util/livePhoto 的协议约定），
        // 再摆一个播放三角是在说一件不成立的事。普通视频不受影响。
      if (this.msg.contentType === 'video' && !this.msgIsLivePhoto() &&
        this.context.liveSendState !== 'sending' &&
        !this.autoplayInlineVideo() &&
        !(this.isPlaySlot() && this.msg.videoFileId !== 0)) {
        // 不要和缩略图自己的加载圈叠成两个中心控件——所以要等缩略图到位。
        // 这个"到没到"必须问通道：路径旁路化之后 msg.photoPath 不再回填，
        // 直接读它会永远是空，播放钮就再也不出现（用户报的正是这个）。
        ThumbReadyGate({
          fileId: this.msg.photoFileId,
          initialPath: this.msg.photoPath,
          ready: this.msg.photoFileId === 0 || this.msg.photoFailed,
          content: (): void => {
            this.videoActionBadge(
              Math.min(56, Math.min(this.mediaBox().width, this.mediaBox().height) * 0.34));
          }
        })
      }
      if (this.msgIsLivePhoto()) {
        this.liveChip();
      }
      if (this.msg.contentType === 'video' && this.videoMetaText() !== '') {
        Text(this.videoMetaText())
          .fontSize(11).fontColor(Color.White).backgroundColor('#00000066')
          .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .position({ x: 8, y: Math.max(8, this.mediaBox().height - 25) });
      }
    }
    .width(this.mediaBox().width).height(this.mediaBox().height)
    // 一镜到底：和全屏查看器里同一条消息的图绑同一个 id，打开/关闭时由系统
    // 把两者的宽高与位置对齐过渡（见 MediaViewerOverlay）。气泡在查看器打开
    // 期间仍然挂在列表里，所以出场节点一直存在，动画不会半路断掉。
    //
    // 【id 必须带 chatId】TDLib 的 message id 是**会话内 id**，跨会话高度重合；
    // 而本仓明确允许多个 ChatPage 同时活在栈里（见 ChatPageEntry.ets 的说明）。
    // 只用 msg.id 的话，两个活着的会话页各带一个 media_1048576，已经踩在官方
    // 「同一个 id 只能有两个组件绑定」的红线上。今天靠"查看器只有一个、且和
    // 其中一个配上了"侥幸没出事。**编译器不校验三处 id 的配对**，所以改动时
    // 三处（本行、相册格那行、MediaViewerOverlay 那行）必须逐字一致。
    .geometryTransition(`media_${this.data.chatId}_${this.msg.id}`)
    .accessibilityText(this.msg.contentType === 'video'
      ? this.videoAccessibilityText()
      : (this.msg.photoFailed ? str('mb_photo_failed') : str('mb_open_photo')))
    // onVisibleAreaChange 每帧都要重新计算可见比例，聊天列表里挂几十个媒体节点会
    // 明显拖累功耗（HarmonyOS 文档已载明这点）；onVisibleAreaApproximateChange 按
    // expectedUpdateInterval 限频上报，正是为这种「列表里大量媒体节点」的场景加的。
    .onVisibleAreaApproximateChange(
      { ratios: [0.0, 0.08, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, 0.9],
        expectedUpdateInterval: 200 },
      (visible: boolean, ratio: number): void => {
        const nextVisible = visible && ratio > 0.02;
        if (this.mediaVisible !== nextVisible) {
          this.mediaVisible = nextVisible;
          if (nextVisible) { this.requestAutoplayDownload(); }
        }
        if (this.msg.contentType !== 'video' || this.msg.isAnimation) {
          return; // 只有普通视频参与播放位竞选：GIF/动图仍走整文件循环播放
        }
        if (ratio <= 0) {
          this.actions.onMediaGone(this.msg.id, -1);
        } else {
          this.actions.onMediaRatio(this.msg.id, -1, ratio, this.mediaCenterY);
        }
      })
    .onAreaChange((_old: Area, area: Area): void => {
      this.mediaCenterY = (area.globalPosition.y as number) + (area.height as number) / 2;
    })
    .onClick((e: ClickEvent) => {
      if (this.context.gestureClaimed) { return; }
      // A failed cover remains a thumbnail-only retry. A failed video does
      // not intercept the whole media surface: ChatPage.openViewer can open
      // the streaming viewer and independently restart the file download.
      if (this.thumbnailRetryable()) {
        this.actions.onSpecialPhotoRetry(this.msg.id);
        return;
      }
      if (this.msg.isAnimation) {
        // 正在播的 GIF 点一下**出气泡菜单**，不再开全屏播放器（用户 2026-09-07
        // 定的交互）。理由：GIF 在气泡里本来就在循环播放，"点开看大的"没什么
        // 可看；而它需要的动作（转发、保存、添加到 GIF）全在菜单里。全屏那条
        // 是修 #105 时定的——那次要解决的是「能动了但点不开」，菜单同样解决。
        //
        // 没在播的那条分支不动：点一下先起播（自动播放关着时这就是"点一下播"）。
        if (this.autoplayInlineVideo()) {
          this.context.recordMenuOffset(e.x, Number(e.target.area.width));
          this.context.msgContextMenuShown = true;
        } else {
          this.actions.onAnimationTap(this.msg.id, false);
        }
      } else {
        this.actions.onMediaTap(this.msg.id, e.windowX, e.windowY);
      }
    });
  }

  @Builder
  content() {
    this.media();
    if (this.msg.text !== '' || this.msg.translatedText !== '') {
      MessageBubbleText({ actions: this.actions,
        context: this.context, presentation: this.textInputCache.prepare(this.msg, this.group.showSenderName, this.data,
          this.msg.text, this.msg.textEntities, 0, 'caption') });
    }
  }

  build() {
    MessageBubbleShell({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
