import { AlbumGroup } from '../../util/collapseAlbums';
import { checkRenderedGroup } from '../../util/rowIdentityGuard';
import {
  messageRowPresentationFor, subscribeMessageRowPresentation
} from '../../util/messageRowPresentationChannel';
import { probeHit } from '../../util/panelProbe';
import { TranslationPresentation, translationLanded } from '../../util/translationLanding';
import { takeTranslationInstant } from '../../util/translationAnchor';
import {
  TRANSLATION_FADE_IN_MS, TRANSLATION_FADE_LOW, TRANSLATION_FADE_OUT_MS
} from '../../util/deferredTranslation';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { LightweightPlainTextBubble } from './LightweightPlainTextBubble';
import { MessageBubble } from './MessageBubble';

// One stable controller belongs to the ChatPage. The wrapper only forwards
// ids/current arrays, so no callback retains the AlbumGroup that created a row.
export interface MessageBubbleActions {
  onStopLiveLocation: () => void;
  onMediaTap: (messageId: number, x: number, y: number) => void;
  onLinkTap: (url: string) => void;
  onCommentTap: (messageId: number) => void;
  onBotCallback: (messageId: number, data: string) => void;
  onAvatarTap: (userId: number) => void;
  onAvatarLongPress: (userId: number, name: string) => void;
  onReplyTap: (messageId: number, fromId: number) => void;
  onFileTap: (messageId: number) => void;
  onFileSave: (messageId: number) => void;
  // 下载中点文件卡片 = 暂停（issue #93）。
  onFilePause: (messageId: number) => void;
  onStickerRetry: (messageId: number) => void;
  onLinkPreviewRetry: (messageId: number) => void;
  onContactOpen: (userId: number, phone: string, vcard: string) => void;
  onPhoneOpen: (phone: string) => void;
  onLocationOpen: (latitude: number, longitude: number, label: string, valid: boolean) => void;
  onPollVote: (messageId: number, optionIds: number[]) => void;
  onGameOpen: (messageId: number) => void;
  onGamePhotoRetry: (messageId: number) => void;
  onPaidMediaUnlock: (messageId: number) => void;
  onPaidMediaOpen: (messageId: number) => void;
  onSpecialPhotoRetry: (messageId: number) => void;
  onVideoRetry: (messageId: number) => void;
  onGiftCodeCopy: (code: string) => void;
  onGiveawayOpen: (chatId: number, messageId: number) => void;
  onVoiceTap: (messageId: number) => void;
  onVoicePlaybackStarted: (messageId: number) => void;
  onAudioTap: (messageId: number) => void;
  onAudioPrevious: (messageId: number) => void;
  onAudioNext: (messageId: number) => void;
  onAudioSeek: (messageId: number, fraction: number) => void;
  onAutoplayVideoNeedDownload: (messageId: number) => void;
  onMediaRatio: (messageId: number, albumIndex: number, ratio: number, centerY: number) => void;
  onMediaGone: (messageId: number, albumIndex: number) => void;
  onPlaySlotPositionChanged: (messageId: number, albumIndex: number, positionMs: number) => void;
  onPlaySlotEnded: (messageId: number, albumIndex: number) => void;
  onAnimationTap: (messageId: number, isPlaying: boolean) => void;
  onAnimationPlaybackFailed: (messageId: number) => void;
  onSetReaction: (messageId: number, emoji: string, chosen: boolean) => void;
  onReplyTo: (messageId: number) => void;
  onEditMsg: (messageId: number) => void;
  onShowReactors: (messageId: number, emoji: string) => void;
  onTranslateMsg: (messageId: number) => void;
  onPinMsg: (messageId: number, unpin: boolean) => void;
  onStopPoll: (messageId: number) => void;
  onReplaceMedia: (messageId: number) => void;
  onPollVoters: (messageId: number) => void;
  onSetDefaultReaction: (emoji: string) => void;
  onCopyText: (messageId: number) => void;
  onSelectText: (messageId: number) => void;
  onCopyCode: (text: string) => void;
  onCopyLink: (messageId: number) => void;
  onForwardMessages: (messageIds: number[]) => void;
  onSaveMessages: (messageIds: number[]) => void;
  onRepeatMessages: (messageIds: number[]) => void;
  onViewSenderHistory: (senderId: number) => void;
  onReportMsg: (messageId: number) => void;
  onSelectMessages: (messageIds: number[]) => void;
  onDeleteMsg: (messageId: number) => void;
  onForwardTap: (chatId: number, messageId: number, userId: number) => void;
  onOpenReactions: (messageId: number) => void;
  onRecognizeSpeech: (messageId: number) => void;
  onVideoNoteDownload: (messageId: number) => void;
  onToggleTranslation: (messageId: number, hidden: boolean) => void;
  onRetryTranslation: (messageId: number) => void;
  onLiveStreamTap: (groupCallId: number) => void;
  // 「添加到 GIF」：动图消息专有，把这条的动图文件存进账号的 saved animations。
  onAddToGifs: (messageId: number) => void;
}

export interface MessageBubbleRenderData {
  // 这个会话此刻能不能发言。只读频道、未加入、被封禁、机器人还没「开始」时
  // 输入框根本不在（membershipLosesComposer），此时左滑回复不该有反应
  // ——滑了也只是把一条回复挂到一个不存在的输入框上
  // （用户 2026-09-09：「这个频道应该没有回复消息的能力呀」）。
  canReply: boolean;
  chatId: number;
  // Actual row width after page-local chrome such as the multi-select gutter.
  // Media, albums and both bubble renderers derive every cap from this value.
  contentWidth: number;
  isGroup: boolean;
  isChannel: boolean;
  liveSharingId: number;
  themeBubbleOut: string;
  showUnreadDivider: boolean;
  // Same divider geometry, different label. Optional keeps older tests/callers
  // source-compatible; only restored-position rows set it.
  dividerIsResume?: boolean;
  paidMediaPending: boolean;
  audioQueuePosition: number;
  audioQueueLength: number;
  audioHasPrevious: boolean;
  audioHasNext: boolean;
  playSlotKey: string;
  autoplayMuted: boolean;
  playSlotStartMs: number;
  animationPaused: boolean;
  animationForcePlay: boolean;
  animationPlaybackFailed: boolean;
  editingActive: boolean;
  isPinnedMsg: boolean;
  liveGroupCallId: number;
  animateIn: boolean;
  lightweightPlainText: boolean;
}

const EMPTY_ACTIONS: MessageBubbleActions = {
  onStopLiveLocation: (): void => {},
  onMediaTap: (_id: number, _x: number, _y: number): void => {},
  onLinkTap: (_url: string): void => {}, onCommentTap: (_id: number): void => {},
  onBotCallback: (_id: number, _data: string): void => {},
  onAvatarTap: (_id: number): void => {},
  onAvatarLongPress: (_id: number, _name: string): void => {},
  onReplyTap: (_id: number, _fromId: number): void => {},
  onFileTap: (_id: number): void => {}, onFileSave: (_id: number): void => {},
  onFilePause: (_id: number): void => {},
  onStickerRetry: (_id: number): void => {}, onLinkPreviewRetry: (_id: number): void => {},
  onContactOpen: (_id: number, _phone: string, _vcard: string): void => {},
  onPhoneOpen: (_phone: string): void => {},
  onLocationOpen: (_lat: number, _lon: number, _label: string, _valid: boolean): void => {},
  onPollVote: (_id: number, _options: number[]): void => {},
  onGameOpen: (_id: number): void => {}, onGamePhotoRetry: (_id: number): void => {},
  onPaidMediaUnlock: (_id: number): void => {}, onPaidMediaOpen: (_id: number): void => {},
  onSpecialPhotoRetry: (_id: number): void => {}, onVideoRetry: (_id: number): void => {},
  onGiftCodeCopy: (_code: string): void => {},
  onGiveawayOpen: (_chatId: number, _id: number): void => {},
  onVoiceTap: (_id: number): void => {}, onVoicePlaybackStarted: (_id: number): void => {},
  onAudioTap: (_id: number): void => {}, onAudioPrevious: (_id: number): void => {},
  onAudioNext: (_id: number): void => {}, onAudioSeek: (_id: number, _fraction: number): void => {},
  onAutoplayVideoNeedDownload: (_id: number): void => {},
  onMediaRatio: (_id: number, _idx: number, _ratio: number, _y: number): void => {},
  onMediaGone: (_id: number, _idx: number): void => {},
  onPlaySlotPositionChanged: (_id: number, _idx: number, _ms: number): void => {},
  onPlaySlotEnded: (_id: number, _idx: number): void => {},
  onAnimationTap: (_id: number, _playing: boolean): void => {},
  onAnimationPlaybackFailed: (_id: number): void => {},
  onSetReaction: (_id: number, _emoji: string, _chosen: boolean): void => {},
  onReplyTo: (_id: number): void => {}, onEditMsg: (_id: number): void => {},
  onShowReactors: (_id: number, _emoji: string): void => {},
  onTranslateMsg: (_id: number): void => {},
  onPinMsg: (_id: number, _unpin: boolean): void => {},
  onStopPoll: (_id: number): void => {}, onReplaceMedia: (_id: number): void => {},
  onPollVoters: (_id: number): void => {}, onSetDefaultReaction: (_emoji: string): void => {},
  onCopyText: (_id: number): void => {}, onSelectText: (_id: number): void => {},
  onCopyCode: (_text: string): void => {},
  onCopyLink: (_id: number): void => {}, onForwardMessages: (_ids: number[]): void => {},
  onSaveMessages: (_ids: number[]): void => {}, onRepeatMessages: (_ids: number[]): void => {},
  onViewSenderHistory: (_id: number): void => {}, onReportMsg: (_id: number): void => {},
  onSelectMessages: (_ids: number[]): void => {}, onDeleteMsg: (_id: number): void => {},
  onForwardTap: (_chatId: number, _id: number, _userId: number): void => {},
  onOpenReactions: (_id: number): void => {}, onRecognizeSpeech: (_id: number): void => {},
  onVideoNoteDownload: (_id: number): void => {},
  onToggleTranslation: (_id: number, _hidden: boolean): void => {},
  onRetryTranslation: (_id: number): void => {}, onLiveStreamTap: (_id: number): void => {},
  onAddToGifs: (_id: number): void => {}
};

// The reuse pool this @ReusableV2 declares lives on the PARENT custom component
// (ChatPage, via the LazyForEach item builder) — a component that does not
// itself reuse does not keep its children's pools alive across recycles. This
// shell is the right place for the annotation precisely because ChatPage
// never gets destroyed while the list scrolls; MessageBubble/
// LightweightPlainTextBubble below must not carry @Reusable of their own.
//
// 必须和 ChatPage 同批迁 V2：官方混用表「V2 普通组件 -> V1 复用组件：不支持，
// 编译告警，实际使用子组件不创建」——ChatPage 变 V2 而这里还是 @Reusable
// @Component，整个消息列表运行时一行都不会创建（而且只是个告警，实测本仓
// 编译连告警都没报出来）。
//
// 子树保持 V1：混用表「V2 复用组件 -> V1 普通组件：支持」。MessageBubble /
// LightweightPlainTextBubble 里现有的 aboutToRecycle 手工清理**全部保留**——
// 官方只承诺「所有的 V2 自定义组件」会被自动重置，V1 子组件不在其中。
@ReusableV2
@ComponentV2
export struct ReusableMessageBubble {
  // @Param 而不是 V1 的 @Prop：官方迁移表「当输入参数为复杂类型时，@Prop 为
  // 深拷贝，@Param 为引用」。这三个入参每帧每行都要过一遍，深拷贝换成引用是
  // 这次迁移在滚动路径上唯一的直接收益。
  //
  // 不需要 UIUtils.enableV2Compatibility：AlbumGroup / MessageBubbleRenderData
  // 都是 interface（非 @Observed / @ObservedV2），且上游 collapseAlbums() 每次
  // 产出全新对象、ChatPage 侧只做整体替换（零原地修改，已逐个 grep 核过），
  // 所以不存在「同一个可变对象被两套体系各自代理」的双重代理场景，桥接是 no-op。
  @Require @Param group: AlbumGroup;
  @Param nowSec: number = 0;
  @Require @Param data: MessageBubbleRenderData;
  // **调研 §2.3 说这里「保持无装饰器」，那是错的，被编译器直接推翻**：
  //   ArkTS Compiler Error 10905324 — The 'regular' property 'actions' in the
  //   custom component 'ReusableMessageBubble' cannot be initialized here
  //   (forbidden to specify).
  // V1 允许父组件一次性初始化无装饰器成员，V2 不允许——无装饰器成员在
  // @ComponentV2 里是**纯本地常量**，外部构造传参是编译错误。所以必须加
  // @Param。
  // 代价可以忽略：messageActions() 惰性建一次、全生命周期同一个引用，
  // @Param 每帧只多一次 === 比较，比较结果恒为相等，不会触发任何刷新。
  @Param actions: MessageBubbleActions = EMPTY_ACTIONS;
  @Local private liveGroup: AlbumGroup | null = null;
  private unsubPresentation: (() => void) | null = null;

  private currentGroup(): AlbumGroup {
    if (this.liveGroup !== null && this.liveGroup.head.rowId === this.group.head.rowId) {
      // 常驻不变量：旁路快照压过 @Param 时，两者描述的必须是同一条消息。
      // rowId 相等只保证"同一行"，不保证"同一份内容版本"。见 util/rowIdentityGuard。
      checkRenderedGroup(this.group.head.id, this.liveGroup.head.id, this.group.head.rowId);
      return this.liveGroup;
    }
    return this.group;
  }

  // 订阅当前挂在哪条 (chatId, rowId) 上。同 key 短路（审计 P1-1 / 3.4）：复用
  // 一次会挂两遍——aboutToReuse 一次、@Param group 落地触发 @Monitor 再一次，每次
  // 都是一整轮「退订 + 读现值 + 重订阅」，是滚动时的每行常数开销。
  // 记下 key 同时也让「订阅挂在哪」成为可判定的事实，谁先到都不影响正确性。
  private attachedKey: string = '';

  private attachPresentation(group: AlbumGroup): void {
    const key: string = `${this.data.chatId}:${group.head.rowId}`;
    if (this.unsubPresentation !== null && this.attachedKey === key) {
      // 已挂在同一行上：订阅原样保留，只重新取一次现值（aboutToRecycle 会把
      // liveGroup 置 null，短路分支不补种会让这一帧退回 @Prop 的快照）。
      this.liveGroup = messageRowPresentationFor(this.data.chatId, group.head.rowId) ?? group;
      return;
    }
    this.detachPresentation();
    this.attachedKey = key;
    this.liveGroup = messageRowPresentationFor(this.data.chatId, group.head.rowId) ?? group;
    this.unsubPresentation = subscribeMessageRowPresentation(
      this.data.chatId,
      group.head.rowId,
      (next: AlbumGroup): void => { this.applyPresentation(next); }
    );
  }

  // 旁路更新落到界面上。
  //
  // 【为什么这里可以做动画，而气泡里不行】译文**不进行签名**（见
  // util/collapseAlbums 的头注释），是从这条通道直达的——这句赋值就在我们自己
  // 的闭包里，`animateTo` 包得住它引起的布局变化，气泡拉长因此能补间。
  // 而气泡内部拿到的已经是变完的值，那时再动画就晚了。
  //
  // 【为什么只给译文动画】这条通道是**所有**展示态更新的公共入口：下载完成、
  // 缩略图路径、发送态都走它。整条包进 animateTo 的话，一次下载进度跳动也会
  // 让气泡跟着动一下。判据在 util/translationLanding（纯函数、有单测）。
  //
  // 【为什么不是给气泡加 .animation()】常驻动画会建立动画上下文，把同一刷新
  // 周期里的列表脏节点一起拖进动画布局——2026-08-27 真机 trace 量过，最重的
  // 一帧从 210ms 涨到 463ms（见 MessageBubble 气泡根节点上那段长注释，那里
  // 点名了「翻译态」）。animateTo 是一次性的，不留上下文。
  private applyPresentation(next: AlbumGroup): void {
    const before: TranslationPresentation = this.translationOf(this.liveGroup);
    const after: TranslationPresentation = this.translationOf(next);
    if (!translationLanded(before, after)) {
      this.liveGroup = next;
      return;
    }
    // 被点名"直接落"的不做动画：那是视口**上方**的行，它变高会把用户正在看的
    // 内容往下推，页面要靠一次滚动补偿吃掉这个位移，而补偿只有布局落定才量得到
    // ——动画会让内容先漂再被拽回来，比硬切更难看。那些行本来也看不见。
    // 判据与点名见 util/translationAnchor。
    if (takeTranslationInstant(next.head.id)) {
      this.liveGroup = next;
      return;
    }
    // 先淡出、换内容、再淡入。
    //
    // 【为什么必须有这一层，光靠高度补间不够】**替换模式**（译文顶掉原文）下
    // 气泡高度往往几乎不变，只有字变了，用户看到的就还是硬切
    // （2026-09-09：「原文翻译替换好像看不太出来动画呢」）。而正文那一层的
    // ForEach 键里含内容指纹，节点确实是销毁重建的——但**不能在那里挂
    // transition**：行复用时键同样会变，那样每滚过一行都会淡入一次。
    // 所以淡入淡出放在行外壳上，只在译文落地这一刻发生。
    //
    // opacity 直接挂在子组件调用上，不额外包一层容器——每行多一个节点在这个
    // 列表上是要还的。
    this.getUIContext().animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, TRANSLATION_FADE_OUT_MS),
      curve: Curve.EaseOut,
      onFinish: (): void => {
        this.getUIContext().animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, TRANSLATION_FADE_IN_MS),
          curve: Curve.FastOutSlowIn
        }, (): void => {
          this.liveGroup = next;
          this.translationFade = 1;
        });
      }
    }, (): void => { this.translationFade = TRANSLATION_FADE_LOW; });
  }

  private translationOf(group: AlbumGroup | null): TranslationPresentation {
    if (group === null) {
      return { text: '', hidden: false };
    }
    return { text: group.head.translatedText, hidden: group.head.translationHidden };
  }

  // 译文换字时的淡入淡出。1 = 常态。
  @Local private translationFade: number = 1;

  private detachPresentation(): void {
    if (this.unsubPresentation !== null) {
      this.unsubPresentation();
      this.unsubPresentation = null;
    }
    this.attachedKey = '';
  }

  // @Monitor 而不是 V1 的 @Watch。注意它**在复用时不会触发**，见 aboutToReuse。
  // 非复用路径（同一个实例上 group 真的换了行）仍然走这里。
  @Monitor('group')
  private onGroupChanged(): void {
    this.attachPresentation(this.group);
  }

  aboutToAppear(): void {
    probeHit('message.mount');
    this.attachPresentation(this.group);
  }

  aboutToDisappear(): void {
    this.detachPresentation();
  }

  aboutToRecycle(): void {
    // detachPresentation() 不能因为「V2 会自动重置」而删掉：重置表最后一行
    // 「常量：包括 readonly 的常量，不重置」，而 attachedKey / unsubPresentation
    // 都是无装饰器成员，V2 视作常量——不退订就会漏订阅。
    // liveGroup 这一次赋值在 V2 下不会刷新 UI（回收期间组件被冻结），但赋值
    // 本身生效，且 @Local 复用时也会被自动重置回 null。语义等价，保留更安全。
    this.detachPresentation();
    this.liveGroup = null;
  }

  aboutToReuse(): void {
    // @ReusableV2 的 aboutToReuse 没有入参（官方《@ReusableV2装饰器》），而
    // @Monitor('group') 在复用重置期间静默——所以这里是复用路径上**唯一**的
    // 重挂订阅点，删掉它 = 复用出来的行永远停在 @Param 的静态快照上。
    // 同步调用的前提是「回调此刻 @Param group 已是新值」：外壳自己是
    // @ReusableV2 根，官方没写清时序，靠真机探针判定——shell.reuse.fresh
    // 连续满格、stale 恒零（09-02，数百样本），据此从延帧兜底改为同步，
    // nextFrameQueue 随最后一个用户退役。
    this.attachPresentation(this.group);
  }

  build() {
    if (this.data.lightweightPlainText && this.currentGroup().head.translatedText === '') {
      LightweightPlainTextBubble({
        msg: this.currentGroup().head,
        nowSec: this.nowSec,
        chatId: this.data.chatId,
        contentWidth: this.data.contentWidth,
        isGroup: this.data.isGroup,
        themeBubbleOut: this.data.themeBubbleOut,
        showUnreadDivider: this.data.showUnreadDivider,
        dividerIsResume: this.data.dividerIsResume === true,
        dateLabel: this.currentGroup().dateLabel,
        editingActive: this.data.editingActive,
        isPinnedMsg: this.data.isPinnedMsg,
        showAvatar: this.currentGroup().showAvatar,
        showSenderName: this.currentGroup().showSenderName,
        animateIn: this.data.animateIn,
        memberIds: this.currentGroup().memberIds,
        actions: this.actions
      })
        .opacity(this.translationFade);
    } else {
      MessageBubble({
      // 整行一个对象下发，不再拆成十七个 @Param（理由见 MessageBubble.group）。
      group: this.currentGroup(),
      msg: this.currentGroup().head, nowSec: this.nowSec,
      // 同理：整份渲染数据一个对象下发（见 MessageBubble.data）。
      data: this.data,
      // 回调表也整体下发（见 MessageBubble.actions）。
      actions: this.actions,
      // `actions` is page-owned and stable. Passing its functions through directly avoids
      // allocating a fresh forwarding closure for every callback of every visible row.
      })
        .opacity(this.translationFade);
    }
  }
}
