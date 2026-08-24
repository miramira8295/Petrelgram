import { AlbumGroup } from './collapseAlbums';

export const INITIAL_EAGER_MESSAGE_ROWS: number = 1;

// Admit exactly one real row per release. The 17:04 device trace showed that a
// pair containing a sticker can still take 26-28 ms, while a short initial page
// followed by its automatic backfill bypassed the old 1 -> 3 -> +2 policy and
// put six rows into one 65 ms layout. One-row growth gives every content shape
// the same hard per-VSync ceiling. Keeping the policy here makes it testable
// without ArkUI.
export function nextInitialMessageRevealCount(current: number, available: number): number {
  if (available <= 0 || current >= available) {
    return available;
  }
  return Math.min(current + 1, available);
}

function deferredCopy(group: AlbumGroup): AlbumGroup {
  return {
    key: `${group.key}|initial-deferred`,
    head: group.head,
    memberIds: group.memberIds,
    rowMemberIds: group.rowMemberIds,
    photoPaths: group.photoPaths,
    photoFileIds: group.photoFileIds,
    photoRatios: group.photoRatios,
    photoIsVideo: group.photoIsVideo,
    photoProgress: group.photoProgress,
    photoFailed: group.photoFailed,
    videoFileIds: group.videoFileIds,
    videoFileSizes: group.videoFileSizes,
    videoMimeTypes: group.videoMimeTypes,
    caption: group.caption,
    captionEntities: group.captionEntities,
    dateLabel: group.dateLabel,
    showAvatar: group.showAvatar,
    showSenderName: group.showSenderName,
    initialDeferred: true
  };
}

// Keep only the requested rows real and turn every other row into a cheap
// height placeholder. Bottom-anchored chats reveal backwards from the newest
// row; unread-anchored chats reveal forwards from the unread row because
// ScrollAlign.START makes that row the top of the viewport.
export function stageInitialMessageGroups(
  groups: AlbumGroup[],
  anchorIndex: number,
  alignFromStart: boolean,
  eagerCount: number = INITIAL_EAGER_MESSAGE_ROWS
): AlbumGroup[] {
  if (groups.length <= eagerCount || anchorIndex < 0 || anchorIndex >= groups.length) {
    return groups;
  }
  const eagerStart: number = alignFromStart
    ? anchorIndex : Math.max(0, anchorIndex - eagerCount + 1);
  const eagerEnd: number = alignFromStart
    ? Math.min(groups.length - 1, anchorIndex + eagerCount - 1) : anchorIndex;
  if (eagerStart === 0 && eagerEnd === groups.length - 1) {
    return groups;
  }
  const staged: AlbumGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    staged.push(i >= eagerStart && i <= eagerEnd ? groups[i] : deferredCopy(groups[i]));
  }
  return staged;
}

// Fixed-height placeholders are deliberately approximate. stackFromEnd or the
// unread START anchor keeps the meaningful edge stable when the real row is
// swapped in one frame later; the estimate only determines how many cheap rows
// List asks for during the first measure pass.
export function initialMessagePlaceholderHeight(
  group: AlbumGroup,
  screenWidth: number,
  showUnreadDivider: boolean
): number {
  const msg = group.head;
  let body: number = 52;
  if (msg.contentType === 'system') {
    body = 34;
  } else if (msg.contentType === 'sticker') {
    body = 172;
  } else if (msg.contentType === 'emoji' || msg.contentType === 'customEmoji') {
    body = 76;
  } else if (msg.contentType === 'photo' || msg.contentType === 'video' ||
    group.photoPaths.length > 1) {
    body = 210;
  } else if (msg.contentType === 'text') {
    const charsPerLine: number = Math.max(12, Math.floor(screenWidth * 0.62 / 9));
    const lines: number = Math.max(1, Math.min(8, Math.ceil(msg.text.length / charsPerLine)));
    body = Math.max(group.showAvatar ? 44 : 0, 22 + lines * 22);
    if (msg.replyToMessageId !== 0) { body += 40; }
    if (group.showSenderName && !msg.isOutgoing) { body += 20; }
  } else if (msg.contentType === 'voice' || msg.contentType === 'audio' ||
    msg.contentType === 'file' || msg.contentType === 'poll') {
    body = 104;
  }
  if (group.dateLabel !== '') { body += 30; }
  if (showUnreadDivider) { body += 26; }
  return body;
}
