import { TdObject } from '../tdkit/TdTypes';

export function customEmojiNeedsRepainting(sticker: TdObject): boolean {
  const fullType = sticker['full_type'] as TdObject | undefined;
  return fullType !== undefined && fullType['@type'] === 'stickerFullTypeCustomEmoji' &&
    fullType['needs_repainting'] === true;
}

export interface InlineEmojiUpdate {
  paths: string[];
  repaint: boolean[];
}

// One pass over this message's unique IDs; no scan of other messages or assets.
export function inlineEmojiUpdate(ids: string[], paths: string[], repaint: boolean[],
  pathById: Map<string, string>, repaintIds: Set<string>): InlineEmojiUpdate | null {
  if (ids.length === 0) { return null; }
  let next: InlineEmojiUpdate | null = paths.length !== ids.length || repaint.length !== ids.length
    ? { paths: [], repaint: [] } : null;
  for (let i: number = 0; i < ids.length; i++) {
    const path: string = pathById.get(ids[i]) ?? '';
    const tint: boolean = repaintIds.has(ids[i]);
    if (next === null) {
      if (paths[i] === path && repaint[i] === tint) { continue; }
      next = { paths: paths.slice(0, i), repaint: repaint.slice(0, i) };
    }
    next.paths.push(path); next.repaint.push(tint);
  }
  return next;
}

interface InlineEmojiAsset {
  source: string;
  repaint: boolean;
}

// Owned by one text component. O(E) only when its immutable arrays change,
// then O(1) for each run; retaining just the current message bounds memory.
export class InlineCustomEmojiPaint {
  private ids: string[] | null = null;
  private paths: string[] | null = null;
  private repaintFlags: boolean[] | null = null;
  private assets: Map<string, InlineEmojiAsset> = new Map<string, InlineEmojiAsset>();

  prepare(ids: string[], paths: string[], repaint: boolean[]): InlineCustomEmojiPaint {
    if (this.ids === ids && this.paths === paths && this.repaintFlags === repaint) { return this; }
    this.ids = ids; this.paths = paths; this.repaintFlags = repaint;
    this.assets.clear();
    for (let i: number = 0; i < ids.length; i++) {
      const path: string = paths[i] ?? '';
      if (path === '') { continue; }
      this.assets.set(ids[i], { source: path.startsWith('/') ? `file://${path}` : path,
        repaint: repaint[i] === true });
    }
    return this;
  }

  source(id: string): string { return this.assets.get(id)?.source ?? ''; }
  needsRepainting(id: string): boolean { return this.assets.get(id)?.repaint ?? false; }
}
