import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';
import { slotKey } from '../pages/chat/playSlot';

// Solid content rows share one drawn outline. Glass and bare/system messages
// retain their distinct rendering contracts, not a flattened approximation.
export function drawnContentEligible(type: string, material: boolean): boolean {
  return !material && type !== 'system' && type !== 'hidden' && type !== 'emoji' &&
    type !== 'sticker' && type !== 'customEmoji' && type !== 'videoNote' && type !== 'dice';
}

// Native surfaces are switched inside media children. Parent snapshot bindings
// must stay safe without subscribing to playback. Cache potential surface
// presence once per immutable group (O(N) on a new group, O(1) thereafter).
const potentialVideoSurface: WeakMap<AlbumGroup, boolean> = new WeakMap();
function headHasVideoSurface(group: AlbumGroup): boolean {
  const m = group.head;
  // Documents, audio and voice also store their file in videoFileId. A file
  // identifier alone does not imply that the bubble mounts a video surface.
  return (m.contentType === 'video' || m.contentType === 'videoNote' || m.isAnimation ||
    (m.contentType === 'paidMedia' && m.paidMediaKind === 'video')) && (m.videoFileId !== 0 || m.videoPath !== '');
}
function canHostVideoSurface(group: AlbumGroup): boolean {
  const known = potentialVideoSurface.get(group);
  if (known !== undefined) { return known; }
  const result = headHasVideoSurface(group) || group.photoIsVideo.some((value: boolean): boolean => value);
  potentialVideoSurface.set(group, result);
  return result;
}

// The play slot encodes the album index. Validate that indexed member instead
// of scanning every member on each menu/snapshot/press binding.
export function drawnLiveSurface(group: AlbumGroup, data: MessageBubbleRenderData, localPlayback: boolean = false): boolean {
  if (localPlayback && canHostVideoSurface(group)) { return true; }
  const key = data.playSlotKey;
  // GIF playback owns a native surface too, even without a normal play slot.
  // Conservatively avoid snapshots while a downloaded GIF can be mounted.
  if (group.head.isAnimation) { return group.head.videoPath !== '' && !data.animationPlaybackFailed; }
  if (key === '') { return false; }
  if (key === slotKey(group.head.id, -1)) { return headHasVideoSurface(group); }
  const separator = key.lastIndexOf(':');
  if (separator <= 0) { return false; }
  const index = Number(key.substring(separator + 1));
  return Number.isInteger(index) && index >= 0 && index < group.memberIds.length &&
    key === slotKey(group.memberIds[index], index) && (group.videoFileIds[index] ?? 0) !== 0;
}
