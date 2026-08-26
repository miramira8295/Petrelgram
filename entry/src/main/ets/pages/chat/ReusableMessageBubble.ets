import { AlbumGroup } from '../../util/collapseAlbums';
import {
  messageRowPresentationFor, subscribeMessageRowPresentation
} from '../../util/messageRowPresentationChannel';
import { probeHit, reuseProbe } from '../../util/panelProbe';
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

// The reuse pool this @Reusable declares lives on the PARENT custom component
// (ChatPage, via the LazyForEach item builder) — a component that does not
// itself reuse does not keep its children's pools alive across recycles. This
// shell is the right place for the annotation precisely because ChatPage
// never gets destroyed while the list scrolls; MessageBubble/
// LightweightPlainTextBubble below must not carry @Reusable of their own.
// aboutToReuse/aboutToRecycle state-reset work is out of scope here (next
// task); only the annotation and the reuseId wiring belong to this step.
@Reusable
@Component
export struct ReusableMessageBubble {
  @Prop @Watch('onGroupChanged') group: AlbumGroup;
  @Prop nowSec: number = 0;
  @Prop data: MessageBubbleRenderData;
  actions: MessageBubbleActions = EMPTY_ACTIONS;
  @State private liveGroup: AlbumGroup | null = null;
  private unsubPresentation: (() => void) | null = null;

  private currentGroup(): AlbumGroup {
    if (this.liveGroup !== null && this.liveGroup.head.rowId === this.group.head.rowId) {
      return this.liveGroup;
    }
    return this.group;
  }

  // 订阅当前挂在哪条 (chatId, rowId) 上。同 key 短路（审计 P1-1 / 3.4）：复用
  // 一次会挂两遍——aboutToReuse 一次、@Prop group 落地触发 @Watch 再一次，每次
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
    this.detachPresentation();
    this.liveGroup = null;
  }

  aboutToReuse(params: Record<string, Object>): void {
    const next: AlbumGroup | undefined = params['group'] as AlbumGroup | undefined;
    // P2-1 探针（审计第 4 节 ①-1）：这一层是 LazyForEach 直接建的顶层复用
    // 组件，params 理应恒有 group；打出来是为了拿到「顶层」的对照组，好判断
    // 递归到子组件时 params 变空/变旧到底发生在哪一层。
    reuseProbe('ReusableMessageBubble', 'group', next !== undefined,
      `row=${next?.head.rowId ?? -1},msg=${next?.head.id ?? -1}`,
      `row=${this.group.head.rowId},msg=${this.group.head.id}`);
    if (next !== undefined) {
      this.attachPresentation(next);
    } else {
      setTimeout((): void => { this.attachPresentation(this.group); }, 0);
    }
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
      showUnreadDivider: this.data.showUnreadDivider, dateLabel: this.currentGroup().dateLabel,
      albumPaths: this.currentGroup().photoPaths, albumFileIds: this.currentGroup().photoFileIds,
      albumRatios: this.currentGroup().photoRatios,
      albumMemberIds: this.currentGroup().memberIds,
      albumIsVideo: this.currentGroup().photoIsVideo,
      albumProgress: this.currentGroup().photoProgress,
      albumFailed: this.currentGroup().photoFailed,
      albumVideoFileIds: this.currentGroup().videoFileIds,
      albumVideoFileSizes: this.currentGroup().videoFileSizes,
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
