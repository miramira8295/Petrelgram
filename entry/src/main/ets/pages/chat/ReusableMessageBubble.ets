import { AlbumGroup } from '../../util/collapseAlbums';
import {
  messageRowPresentationFor, subscribeMessageRowPresentation
} from '../../util/messageRowPresentationChannel';
import { probeHit } from '../../util/panelProbe';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId
} from '../../util/nextFrameQueue';
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
}

export interface MessageBubbleRenderData {
  chatId: number;
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
  onCopyText: (_id: number): void => {}, onCopyCode: (_text: string): void => {},
  onCopyLink: (_id: number): void => {}, onForwardMessages: (_ids: number[]): void => {},
  onSaveMessages: (_ids: number[]): void => {}, onRepeatMessages: (_ids: number[]): void => {},
  onViewSenderHistory: (_id: number): void => {}, onReportMsg: (_id: number): void => {},
  onSelectMessages: (_ids: number[]): void => {}, onDeleteMsg: (_id: number): void => {},
  onForwardTap: (_chatId: number, _id: number, _userId: number): void => {},
  onOpenReactions: (_id: number): void => {}, onRecognizeSpeech: (_id: number): void => {},
  onVideoNoteDownload: (_id: number): void => {},
  onToggleTranslation: (_id: number, _hidden: boolean): void => {},
  onRetryTranslation: (_id: number): void => {}, onLiveStreamTap: (_id: number): void => {}
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
  // 见 util/nextFrameQueue：复用路径上的 setTimeout(0) 合并成一帧一个，这是本
  // 实例在那个队列里的序号。无装饰器成员在复用时不重置，序号因此在整个实例生命
  // 周期里稳定——后一次复用排的回调才盖得掉前一次的。
  private frameOwnerId: number = nextFrameOwnerId();

  private currentGroup(): AlbumGroup {
    if (this.liveGroup !== null && this.liveGroup.head.rowId === this.group.head.rowId) {
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
      (next: AlbumGroup): void => { this.liveGroup = next; }
    );
  }

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
    // 组件要销毁了，上一次复用排的那条回调不能再跑：attachPresentation 会重新
    // 订阅，而这一层再也没有 detach 会被调用——订阅会一直持有这个实例。
    cancelNextFrame(this.frameOwnerId);
  }

  aboutToRecycle(): void {
    // detachPresentation() 不能因为「V2 会自动重置」而删掉：重置表最后一行
    // 「常量：包括 readonly 的常量，不重置」，而 attachedKey / unsubPresentation
    // 都是无装饰器成员，V2 视作常量——不退订就会漏订阅。
    // liveGroup 这一次赋值在 V2 下不会刷新 UI（回收期间组件被冻结），但赋值
    // 本身生效，且 @Local 复用时也会被自动重置回 null。语义等价，保留更安全。
    this.detachPresentation();
    this.liveGroup = null;
    // 躺进复用池期间别让上一次复用排的回调再把订阅挂回来——那时已经退订，
    // 没人会再去退它。下一次 aboutToReuse 会重新排队，所以没有丢失。
    cancelNextFrame(this.frameOwnerId);
  }

  aboutToReuse(): void {
    // 迁 @ReusableV2 之后，原来那条读 params['group'] 的快路径**不存在了**：
    // 官方《@ReusableV2装饰器：V2组件复用》——「与@Reusable不同的是，
    // aboutToReuse 没有入参」。
    //
    // 而 @Monitor('group') 在复用时也**不跑**：同一篇「复用前的组件内状态变量
    // 重置」表写明「@Monitor：在上述所有变量重置完成之后触发。**重置过程中产生
    // 的变量变化不会触发 @Monitor 回调**，仅更新 IMonitorValue 中的 before 值」。
    // aboutToRecycle 已经退订、把 liveGroup 置 null、attachedKey 归零，所以复用
    // 回来时没有别的路会重挂订阅。
    //
    // → 这条 setTimeout 兜底**已经是唯一的重挂路径**（P2 时它还只是「迁 V2 后
    //   会变成唯一分支」的预判；现在是事实）。删掉它 = 复用出来的行永远停在
    //   @Param 的静态快照上，下载进度/编辑/表态都不再跟。
    //
    // 为什么仍然推迟一帧而不是同步调用：官方没有写清「状态变量重置」与
    // 「aboutToReuse 回调」的精确先后（冻结那一节说冻结「持续到 aboutToReuse
    // 前」，重置那一节只说「复用前」），**无法确定**此刻 this.group 已经是新值
    // 还是仍是旧值。推迟一帧读到的必然是新值。上机探针确认之后（P3 批 2 第一
    // 项）再决定能不能改成同步、省这一帧。
    // 合并进共享队列，语义不变（见 util/nextFrameQueue）。
    enqueueNextFrame(this.frameOwnerId,
      (): void => { this.attachPresentation(this.group); });
  }

  build() {
    if (this.data.lightweightPlainText && this.currentGroup().head.translatedText === '') {
      LightweightPlainTextBubble({
        msg: this.currentGroup().head,
        nowSec: this.nowSec,
        chatId: this.data.chatId,
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
      });
    } else {
      MessageBubble({
      msg: this.currentGroup().head, nowSec: this.nowSec, chatId: this.data.chatId,
      isGroup: this.data.isGroup, isChannel: this.data.isChannel,
      liveSharingId: this.data.liveSharingId,
      onStopLiveLocation: this.actions.onStopLiveLocation,
      themeBubbleOut: this.data.themeBubbleOut,
      showUnreadDivider: this.data.showUnreadDivider,
      dividerIsResume: this.data.dividerIsResume === true,
      dateLabel: this.currentGroup().dateLabel,
      albumPaths: this.currentGroup().photoPaths, albumFileIds: this.currentGroup().photoFileIds,
      albumRatios: this.currentGroup().photoRatios,
      albumMemberIds: this.currentGroup().memberIds,
      albumIsVideo: this.currentGroup().photoIsVideo,
      albumIsLive: this.currentGroup().photoIsLive,
      albumProgress: this.currentGroup().photoProgress,
      albumFailed: this.currentGroup().photoFailed,
      albumVideoFileIds: this.currentGroup().videoFileIds,
      albumVideoFileSizes: this.currentGroup().videoFileSizes,
      albumVideoDurations: this.currentGroup().videoDurations,
      albumVideoMimeTypes: this.currentGroup().videoMimeTypes,
      albumCaption: this.currentGroup().caption,
      albumCaptionEntities: this.currentGroup().captionEntities,
      paidMediaPending: this.data.paidMediaPending,
      audioQueuePosition: this.data.audioQueuePosition,
      audioQueueLength: this.data.audioQueueLength,
      audioHasPrevious: this.data.audioHasPrevious, audioHasNext: this.data.audioHasNext,
      playSlotKey: this.data.playSlotKey, autoplayMuted: this.data.autoplayMuted,
      playSlotStartMs: this.data.playSlotStartMs,
      animationPaused: this.data.animationPaused,
      animationForcePlay: this.data.animationForcePlay,
      animationPlaybackFailed: this.data.animationPlaybackFailed,
      editingActive: this.data.editingActive, isPinnedMsg: this.data.isPinnedMsg,
      liveGroupCallId: this.data.liveGroupCallId,
      showAvatar: this.currentGroup().showAvatar,
      showSenderName: this.currentGroup().showSenderName,
      animateIn: this.data.animateIn,
      // `actions` is page-owned and stable. Passing its functions through directly avoids
      // allocating a fresh forwarding closure for every callback of every visible row.
      onMediaTap: this.actions.onMediaTap,
      onLinkTap: this.actions.onLinkTap,
      onCommentTap: this.actions.onCommentTap,
      onBotCallback: this.actions.onBotCallback,
      onAvatarTap: this.actions.onAvatarTap,
      onAvatarLongPress: this.actions.onAvatarLongPress,
      onReplyTap: this.actions.onReplyTap,
      onFileTap: this.actions.onFileTap,
      onFileSave: this.actions.onFileSave,
      onFilePause: this.actions.onFilePause,
      onStickerRetry: this.actions.onStickerRetry,
      onLinkPreviewRetry: this.actions.onLinkPreviewRetry,
      onContactOpen: this.actions.onContactOpen,
      onPhoneOpen: this.actions.onPhoneOpen,
      onLocationOpen: this.actions.onLocationOpen,
      onPollVote: this.actions.onPollVote,
      onGameOpen: this.actions.onGameOpen,
      onGamePhotoRetry: this.actions.onGamePhotoRetry,
      onPaidMediaUnlock: this.actions.onPaidMediaUnlock,
      onPaidMediaOpen: this.actions.onPaidMediaOpen,
      onSpecialPhotoRetry: this.actions.onSpecialPhotoRetry,
      onVideoRetry: this.actions.onVideoRetry,
      onGiftCodeCopy: this.actions.onGiftCodeCopy,
      onGiveawayOpen: this.actions.onGiveawayOpen,
      onVoiceTap: this.actions.onVoiceTap,
      onVoicePlaybackStarted: this.actions.onVoicePlaybackStarted,
      onAudioTap: this.actions.onAudioTap,
      onAudioPrevious: this.actions.onAudioPrevious,
      onAudioNext: this.actions.onAudioNext,
      onAudioSeek: this.actions.onAudioSeek,
      onAutoplayVideoNeedDownload: this.actions.onAutoplayVideoNeedDownload,
      onMediaRatio: this.actions.onMediaRatio,
      onMediaGone: this.actions.onMediaGone,
      onPlaySlotPositionChanged: this.actions.onPlaySlotPositionChanged,
      onPlaySlotEnded: this.actions.onPlaySlotEnded,
      onAnimationTap: this.actions.onAnimationTap,
      onAnimationPlaybackFailed: this.actions.onAnimationPlaybackFailed,
      onSetReaction: this.actions.onSetReaction,
      onReplyTo: this.actions.onReplyTo,
      onEditMsg: this.actions.onEditMsg,
      onShowReactors: this.actions.onShowReactors,
      onTranslateMsg: this.actions.onTranslateMsg,
      onPinMsg: this.actions.onPinMsg,
      onStopPoll: this.actions.onStopPoll,
      onReplaceMedia: this.actions.onReplaceMedia,
      onPollVoters: this.actions.onPollVoters,
      onSetDefaultReaction: this.actions.onSetDefaultReaction,
      onCopyText: this.actions.onCopyText,
      onCopyCode: this.actions.onCopyCode,
      onCopyLink: this.actions.onCopyLink,
      onForwardMsg: this.actions.onForwardMessages,
      onSaveToSaved: this.actions.onSaveMessages,
      onRepeatMsg: this.actions.onRepeatMessages,
      onViewSenderHistory: this.actions.onViewSenderHistory,
      onReportMsg: this.actions.onReportMsg,
      onSelectMsg: this.actions.onSelectMessages,
      onDeleteMsg: this.actions.onDeleteMsg,
      onForwardTap: this.actions.onForwardTap,
      onOpenReactions: this.actions.onOpenReactions,
      onRecognizeSpeech: this.actions.onRecognizeSpeech,
      onVideoNoteDownload: this.actions.onVideoNoteDownload,
      onToggleTranslation: this.actions.onToggleTranslation,
      onRetryTranslation: this.actions.onRetryTranslation,
      onLiveStreamTap: this.actions.onLiveStreamTap
      });
    }
  }
}
