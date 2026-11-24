import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';

// Immutable row snapshots: compare fixed fields/references, never scan history,
// entities or media arrays. Conservative on replaced arrays, including selection.
// Host tests audit these fields against the interfaces when they grow.
export function sameDrawnRowData(a: MessageBubbleRenderData, b: MessageBubbleRenderData): boolean {
  return a === b || (a.contentWidth === b.contentWidth && a.splitLayout === b.splitLayout && a.isGroup === b.isGroup && a.isChannel === b.isChannel &&
    a.canReply === b.canReply && a.canReport === b.canReport && a.selectionActive === b.selectionActive &&
    a.selectedMemberIds === b.selectedMemberIds && a.chatId === b.chatId && a.liveSharingId === b.liveSharingId &&
    a.themeBubbleOut === b.themeBubbleOut && a.showUnreadDivider === b.showUnreadDivider && a.dividerIsResume === b.dividerIsResume &&
    a.paidMediaPending === b.paidMediaPending && a.audioQueuePosition === b.audioQueuePosition && a.audioQueueLength === b.audioQueueLength &&
    a.audioHasPrevious === b.audioHasPrevious && a.audioHasNext === b.audioHasNext && a.playSlotKey === b.playSlotKey &&
    a.autoplayMuted === b.autoplayMuted && a.playSlotStartMs === b.playSlotStartMs && a.animationPaused === b.animationPaused &&
    a.animationForcePlay === b.animationForcePlay && a.animationPlaybackFailed === b.animationPlaybackFailed && a.editingActive === b.editingActive &&
    a.isPinnedMsg === b.isPinnedMsg && a.liveGroupCallId === b.liveGroupCallId && a.animateIn === b.animateIn &&
    a.lightweightPlainText === b.lightweightPlainText);
}

export function sameDrawnAlbumInput(a: AlbumGroup, b: AlbumGroup): boolean {
  return a === b || (a.key === b.key && a.head === b.head && a.memberIds === b.memberIds &&
    a.rowMemberIds === b.rowMemberIds && a.photoPaths === b.photoPaths && a.photoMinis === b.photoMinis &&
    a.photoFileIds === b.photoFileIds && a.photoRatios === b.photoRatios && a.photoIsVideo === b.photoIsVideo &&
    a.photoIsLive === b.photoIsLive && a.photoProgress === b.photoProgress && a.photoFailed === b.photoFailed &&
    a.videoFileIds === b.videoFileIds && a.videoFileSizes === b.videoFileSizes && a.videoDurations === b.videoDurations &&
    a.videoMimeTypes === b.videoMimeTypes && a.inlineFileIds === b.inlineFileIds && a.inlineFileSizes === b.inlineFileSizes &&
    a.captionMessage === b.captionMessage && a.caption === b.caption && a.captionEntities === b.captionEntities &&
    a.dateLabel === b.dateLabel && a.showAvatar === b.showAvatar && a.showSenderName === b.showSenderName &&
    a.initialDeferred === b.initialDeferred);
}

// Interaction/other-media flags still reach the child, but cannot reshape an
// album. Include every data input read by media/grid/content layout policies.
export function sameDrawnAlbumGeometryData(a: MessageBubbleRenderData, b: MessageBubbleRenderData): boolean {
  return a === b || (a.contentWidth === b.contentWidth && a.splitLayout === b.splitLayout && a.isGroup === b.isGroup && a.isChannel === b.isChannel &&
    a.chatId === b.chatId && a.themeBubbleOut === b.themeBubbleOut && a.selectionActive === b.selectionActive &&
    a.selectedMemberIds === b.selectedMemberIds && a.playSlotKey === b.playSlotKey && a.autoplayMuted === b.autoplayMuted &&
    a.playSlotStartMs === b.playSlotStartMs && a.animationPlaybackFailed === b.animationPlaybackFailed);
}
