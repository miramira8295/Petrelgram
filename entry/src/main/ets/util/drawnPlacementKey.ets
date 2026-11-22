// ForEach retains the original item and its event closures while a key matches.
// Prepared placements are immutable and stay shared across progress updates.
const placementKeys: WeakMap<Object, string> = new WeakMap<Object, string>();
let nextPlacementKey: number = 0;

export function drawnPlacementKey(placement: Object): string {
  const existing = placementKeys.get(placement);
  if (existing !== undefined) { return existing; }
  const key = String(++nextPlacementKey);
  placementKeys.set(placement, key);
  return key;
}
