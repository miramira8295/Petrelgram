import { TdObject } from '../tdkit/TdTypes';

export interface DrawnDocumentMedia {
  key: string;
  index: number;
  kind: string;
  file: TdObject;
  thumbnail: TdObject | undefined;
  width: number;
  height: number;
  size: number;
  mimeType: string;
  name: string;
  autoplay: boolean;
  duration?: number;
}
export function documentFileId(file: TdObject | undefined): number { return (file?.['id'] as number | undefined) ?? 0; }
export function documentFilePath(file: TdObject | undefined): string {
  const local = file?.['local'] as TdObject | undefined;
  return local?.['is_downloading_completed'] === true ? (local['path'] as string | undefined) ?? '' : '';
}

// Read standard TDLib media objects once, never serialize or re-walk sizes in
// build/paint. Inline layout chooses a small image; the viewer requests full.
export function drawnDocumentMedia(node: TdObject, key: string, index: number): DrawnDocumentMedia | null {
  const type = (node['@type'] as string | undefined) ?? '';
  const kind = type === 'pageBlockPhoto' ? 'photo' : type === 'pageBlockVideo' ? 'video'
    : type === 'pageBlockAnimation' ? 'animation' : '';
  if (kind === '') { return null; }
  const media = node[kind] as TdObject | undefined;
  if (media === undefined) { return null; }
  let file: TdObject | undefined, thumbnail: TdObject | undefined;
  let width = (media['width'] as number | undefined) ?? 0;
  let height = (media['height'] as number | undefined) ?? 0;
  if (kind === 'photo') {
    const sizes = (media['sizes'] as TdObject[] | undefined) ?? [];
    let largest: number = -1, thumbDistance: number = Number.POSITIVE_INFINITY;
    for (const size of sizes) {
      const w = (size['width'] as number | undefined) ?? 0, h = (size['height'] as number | undefined) ?? 0;
      const image = size['photo'] as TdObject | undefined;
      if (documentFileId(image) <= 0 || !(w > 0 && h > 0)) { continue; }
      if (w * h > largest) { largest = w * h; file = image; width = w; height = h; }
      const distance = Math.abs(Math.max(w, h) - 480);
      if (distance < thumbDistance) { thumbDistance = distance; thumbnail = image; }
    }
  } else {
    file = media[kind] as TdObject | undefined;
    const thumb = media['thumbnail'] as TdObject | undefined;
    thumbnail = thumb?.['file'] as TdObject | undefined;
  }
  if (file === undefined || documentFileId(file) <= 0) { return null; }
  return { key, index, kind, file, thumbnail, width: width > 0 ? width : 320, height: height > 0 ? height : 180,
    size: ((file['size'] ?? file['expected_size']) as number | undefined) ?? 0,
    mimeType: (media['mime_type'] as string | undefined) ?? '', name: (media['file_name'] as string | undefined) ?? '',
    autoplay: node['need_autoplay'] === true || kind === 'animation',
    duration: Math.max(0, (media['duration'] as number | undefined) ?? 0) };
}
