import { SharedItem, SharedPayload } from './sharedContent';
import { isAnimationPath } from './mediaPick';

export interface DirectShareStep {
  kind: string;
  items: SharedItem[];
  caption: string;
}

export function directShareSteps(payload: SharedPayload): DirectShareStep[] {
  const result: DirectShareStep[] = [];
  let batch: SharedItem[] = [];
  const flush = (): void => {
    if (batch.length === 0) { return; }
    result.push({ kind: 'media', items: batch, caption: result.length === 0 ? payload.caption : '' });
    batch = [];
  };
  for (const item of payload.media) {
    const media: boolean = item.kind === 'image' || item.kind === 'video';
    const animation: boolean = item.kind === 'image' && isAnimationPath(item.uri);
    if (media && !animation) {
      batch.push(item);
      if (batch.length === 9) { flush(); }
    } else {
      flush();
      result.push({ kind: media ? 'media' : item.kind, items: [item],
        caption: result.length === 0 ? payload.caption : '' });
    }
  }
  flush();
  if (result.length === 0 && payload.caption !== '') {
    result.push({ kind: 'text', items: [], caption: payload.caption });
  }
  return result;
}
