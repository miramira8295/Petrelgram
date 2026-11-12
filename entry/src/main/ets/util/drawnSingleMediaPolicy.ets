// Screen readers deliberately retain native semantics (actions, selection, replies and media).
// Remove that fallback only after equivalent virtual accessibility nodes are verified.
import { AlbumGroup } from './collapseAlbums';

// Photo/video/GIF share geometry. Their native playback islands retain the
// original controls; failed thumbnails keep their local retry UI.
export function drawnSingleMediaEligible(group: AlbumGroup, material: boolean, accessibility: boolean): boolean {
  const m = group.head;
  return !material && !accessibility && group.memberIds.length === 1 &&
    (m.contentType === 'photo' || m.contentType === 'video') &&
    m.translatedText === '' && m.linkUrl === '' &&
    m.linkTitle === '' && m.linkSiteName === '' && m.linkDescription === '' && m.linkPhotoFileId === 0;
}
