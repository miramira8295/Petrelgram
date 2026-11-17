import { DrawnAnchorBranch, DrawnRichSource } from './drawnRichTextPolicy';
interface DocumentAnchorFrame { anchorName?: string; source: DrawnRichSource; branch: DrawnAnchorBranch | null; }
// O(blocks + anchors) construction/storage. Persistent parent links avoid
// copying every ancestor path into every target. A click walks only its depth.
export function indexDocumentAnchors(source: DrawnRichSource): Map<string, DrawnAnchorBranch | null> {
  const result = new Map<string, DrawnAnchorBranch | null>();
  const pending: DocumentAnchorFrame[] = [{ source, branch: null }];
  while (pending.length > 0) {
    const frame = pending.pop()!;
    if (frame.anchorName !== undefined) { result.set(frame.anchorName, frame.branch); }
    for (const name of frame.source.anchorNames ?? []) { result.set(name, frame.branch); }
    if (frame.source.table !== undefined) {
      const rows = frame.source.table.rows;
      for (let row: number = rows.length - 1; row >= 0; row--) {
        for (let cell: number = rows[row].length - 1; cell >= 0; cell--) {
          pending.push({ source: rows[row][cell].source, branch: frame.branch });
        }
      }
    }
    const blocks = frame.source.blocks ?? [];
    for (let i: number = blocks.length - 1; i >= 0; i--) {
      const block = blocks[i];
      const branch: DrawnAnchorBranch | null = block.kind === 'details'
        ? { offset: block.offset, initiallyOpen: block.initiallyOpen === true, parent: frame.branch } : frame.branch;
      pending.push({ source: block.source, branch, anchorName: block.anchorName });
      if (block.title !== undefined) { pending.push({ source: block.title, branch: frame.branch }); }
      const buttons = block.buttons ?? [];
      for (let button: number = buttons.length - 1; button >= 0; button--) { pending.push({ source: buttons[button].source, branch: frame.branch }); }
    }
  }
  return result;
}
export function documentAnchorName(url: string): string | null {
  if (!url.startsWith('#')) { return null; }
  try { return decodeURIComponent(url.substring(1)).toLowerCase(); }
  catch (_) { return url.substring(1).toLowerCase(); }
}
export function expandDocumentAnchor(branch: DrawnAnchorBranch | null, current: ReadonlyArray<number>): number[] {
  const result = new Set<number>(current);
  for (let node = branch; node !== null; node = node.parent) {
    if (node.initiallyOpen) { result.delete(node.offset); } else { result.add(node.offset); }
  }
  return Array.from(result);
}
