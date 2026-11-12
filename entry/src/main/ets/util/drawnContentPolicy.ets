import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';
import { slotKey } from '../pages/chat/playSlot';

// Solid content rows share one drawn outline. Glass and bare/system messages
// retain their distinct rendering contracts, not a flattened approximation.
export function drawnContentEligible(type: string, material: boolean): boolean {
  return !material && type !== 'system' && type !== 'hidden' && type !== 'emoji' &&
    type !== 'sticker' && type !== 'customEmoji' && type !== 'videoNote' && type !== 'dice';
}

// The play slot encodes the album index. Validate that indexed member instead
// of scanning every member on each menu/snapshot/press binding.
export function drawnLiveSurface(group: AlbumGroup, data: MessageBubbleRenderData): boolean {
  const key = data.playSlotKey;
  // GIF playback owns a native surface too, even without a normal play slot.
  // Conservatively avoid snapshots while a downloaded GIF can be mounted.
  if (group.head.isAnimation) { return group.head.videoPath !== '' && !data.animationPlaybackFailed; }
  if (key === '') { return false; }
  if (key === slotKey(group.head.id, -1)) { return group.head.videoFileId !== 0; }
  const separator = key.lastIndexOf(':');
  if (separator <= 0) { return false; }
  const index = Number(key.substring(separator + 1));
  return Number.isInteger(index) && index >= 0 && index < group.memberIds.length &&
    key === slotKey(group.memberIds[index], index) && (group.videoFileIds[index] ?? 0) !== 0;
}
