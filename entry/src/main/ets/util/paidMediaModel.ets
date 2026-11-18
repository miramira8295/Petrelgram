import { TdObject } from '../tdkit/TdTypes';
import { DrawnDocumentMedia, drawnDocumentMedia, documentFileId, documentFilePath } from './drawnDocumentMedia';

export interface PaidMediaItem {
  index: number;
  kind: string;
  width: number;
  height: number;
  duration: number;
  mini: string;
  media: DrawnDocumentMedia | null;
}
export interface PaidMediaSet {
  items: PaidMediaItem[];
  media: DrawnDocumentMedia[];
  viewerIndices: number[];
  locked: boolean;
  complete: boolean;
  signature: string;
}
export interface PaidMediaViewerTarget { media: DrawnDocumentMedia[]; index: number; }

function paidMini(holder: TdObject | undefined): string {
  const mini = holder?.['minithumbnail'] as TdObject | undefined;
  const data = (mini?.['data'] as string | undefined) ?? '';
  return data !== '' ? `data:image/jpeg;base64,${data}` : '';
}

// One media pass plus each photo's size variants and fingerprint text:
// O(N + S + L) time, O(N + L) retained metadata. Build the viewer/index map here, never on
// progress updates or taps. Unknown entries retain their original positions.
export function parsePaidMediaSet(raw: TdObject[]): PaidMediaSet {
  const items: PaidMediaItem[] = [], media: DrawnDocumentMedia[] = [], viewerIndices: number[] = [];
  const fingerprints: Object[] = [];
  let locked = raw.length === 0;
  for (let index = 0; index < raw.length; index++) {
    const node = raw[index], type = (node['@type'] as string | undefined) ?? '';
    let parsed: DrawnDocumentMedia | null = null, holder: TdObject | undefined;
    let kind = 'unknown';
    if (type === 'paidMediaPhoto') {
      kind = 'photo'; holder = node['photo'] as TdObject | undefined;
      if (holder !== undefined) {
        const block: TdObject = {};
        block['@type'] = 'pageBlockPhoto'; block['photo'] = holder;
        parsed = drawnDocumentMedia(block, `paid:${index}`, index);
      }
    } else if (type === 'paidMediaVideo') {
      kind = 'video'; holder = node['video'] as TdObject | undefined;
      if (holder !== undefined) {
        const block: TdObject = {};
        block['@type'] = 'pageBlockVideo'; block['video'] = holder;
        parsed = drawnDocumentMedia(block, `paid:${index}`, index);
      }
    } else if (type === 'paidMediaPreview') {
      kind = 'preview'; holder = node; locked = true;
    }
    const width = parsed?.width ?? Math.max(0, (holder?.['width'] as number | undefined) ?? 0);
    const height = parsed?.height ?? Math.max(0, (holder?.['height'] as number | undefined) ?? 0);
    const duration = Math.max(0, (holder?.['duration'] as number | undefined) ?? 0);
    const viewerIndex = parsed !== null ? media.length : -1;
    if (parsed !== null) { media.push(parsed); }
    viewerIndices.push(viewerIndex);
    const mini = paidMini(holder);
    items.push({ index, kind, width, height, duration, mini, media: parsed });
    const fingerprint: Object[] = [kind, width, height, duration, mini, documentFileId(parsed?.file),
      documentFileId(parsed?.thumbnail), documentFilePath(parsed?.file), documentFilePath(parsed?.thumbnail),
      parsed?.size ?? 0, parsed?.mimeType ?? '', parsed?.name ?? ''];
    fingerprints.push(fingerprint);
  }
  return { items, media, viewerIndices, locked, complete: !locked && media.length === items.length,
    signature: JSON.stringify(fingerprints) };
}

export function paidMediaViewerTarget(set: PaidMediaSet, index: number): PaidMediaViewerTarget | null {
  if (set.locked || !Number.isInteger(index) || index < 0 || index >= set.items.length) { return null; }
  const mapped = set.viewerIndices[index];
  if (mapped === undefined || mapped < 0 || set.items[index].media !== set.media[mapped]) { return null; }
  return { media: set.media, index: mapped };
}
