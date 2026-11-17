// Screen readers use DrawnRowAccessibility virtual targets alongside the same paint plan.
import { AlbumGroup } from './collapseAlbums';

// Photo/video/GIF share geometry. Their native playback islands retain the
// original controls; failed thumbnails keep their local retry UI.
export function drawnSingleMediaEligible(group: AlbumGroup, _material: boolean, _accessibility: boolean): boolean {
  const m = group.head;
  return group.memberIds.length === 1 &&
    (m.contentType === 'photo' || m.contentType === 'video');
}
