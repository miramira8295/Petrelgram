import { TdObject } from '../tdkit/TdTypes';
// O(1) invalidation for immutable block snapshots. Never serialize a deep tree
// just to decide whether a list row must receive the new document.
const revisions: WeakMap<TdObject[], number> = new WeakMap();
let next: number = 0;
export function richBlockRevision(blocks: TdObject[] | undefined): number {
  if (blocks === undefined) { return 0; }
  let revision = revisions.get(blocks);
  if (revision === undefined) { revision = ++next; revisions.set(blocks, revision); }
  return revision;
}
