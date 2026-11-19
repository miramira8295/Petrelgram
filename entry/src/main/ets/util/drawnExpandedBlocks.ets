// Expansion snapshots are immutable @Local ReadonlyArray values. A deep
// document may contain many cached subtree engines; do not rebuild the entire
// expansion Set in every subtree. Weak ownership follows the source snapshot.
const emptyExpandedBlocks: ReadonlySet<number> = new Set<number>();
const expandedBlockSets: WeakMap<ReadonlyArray<number>, ReadonlySet<number>> = new WeakMap<ReadonlyArray<number>, ReadonlySet<number>>();
export function drawnExpandedBlockSet(blocks: ReadonlyArray<number> | undefined): ReadonlySet<number> {
  if (blocks === undefined || blocks.length === 0) { return emptyExpandedBlocks; }
  let result = expandedBlockSets.get(blocks);
  if (result === undefined) { result = new Set<number>(blocks); expandedBlockSets.set(blocks, result); }
  return result;
}
