// Screen readers use DrawnRowAccessibility virtual targets alongside the same paint plan.
import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';


// Gate unsupported behavior before allocating native drawing resources. The
// photo/video path includes captions, names and text-only reply quotes.
export function drawnAlbumEligible(group: AlbumGroup, data: MessageBubbleRenderData,
  _material: boolean, _accessibility: boolean): boolean {
  const count = group.memberIds.length;
  if (count < 2 || count > 10 ||
    group.photoRatios.length !== count) { return false; }
  return true;
}

export interface DrawnAlbumRect { x: number; y: number; width: number; height: number; }
export function albumRectContains(rect: DrawnAlbumRect, x: number, y: number): boolean {
  return x >= rect.x && y >= rect.y && x < rect.x + rect.width && y < rect.y + rect.height;
}
