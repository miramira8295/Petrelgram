// Screen readers deliberately retain native semantics (actions, selection, replies and media).
// Remove that fallback only after equivalent virtual accessibility nodes are verified.
import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';


// Gate unsupported behavior before allocating native drawing resources. The
// photo/video path includes captions, names and text-only reply quotes.
export function drawnAlbumEligible(group: AlbumGroup, data: MessageBubbleRenderData,
  material: boolean, accessibility: boolean): boolean {
  const msg = group.head;
  const count = group.memberIds.length;
  if (material || accessibility || count < 2 || count > 10 ||
    group.photoRatios.length !== count || msg.translatedText !== '' ||
    msg.linkUrl !== '' || msg.linkTitle !== '' || msg.linkSiteName !== '' ||
    msg.linkDescription !== '' || msg.linkPhotoFileId !== 0) { return false; }
  return true;
}

export interface DrawnAlbumRect { x: number; y: number; width: number; height: number; }
export function albumRectContains(rect: DrawnAlbumRect, x: number, y: number): boolean {
  return x >= rect.x && y >= rect.y && x < rect.x + rect.width && y < rect.y + rect.height;
}
