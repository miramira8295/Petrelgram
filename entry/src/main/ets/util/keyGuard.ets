import { logE } from './log';
// Diagnostic for LazyForEach duplicate keys.
//
// ArkUI logs "Use repeat key for index: N" but names neither the key nor the
// list, and this app has three LazyForEach instances.
//
// The first version of this reset its table on every dataset update, which made
// it blind: rows are built lazily during scroll, and between two builds the data
// source can call update() a dozen times. A collision whose two halves straddle
// a reset was never seen. It reported nothing while ArkUI reported 44 repeats.
//
// This version mirrors what the framework actually keeps: one key table per
// list, invalidated only by RELOAD, with indexes shifted by ADD and DELETE
// exactly as the framework shifts them. A report from it means two live rows
// really do claim one key.
//
// Temporary. Remove once the remaining duplicates are accounted for.

class KeyTable {
  byIndex: Map<number, string> = new Map();
  byKey: Map<string, number> = new Map();
}

const tables: Map<string, KeyTable> = new Map();

// Each LazyForEach has its own key table, and so must each list identity here.
// Sharing one table named 'messages' across chat pages made every fresh page's
// rows collide with the previous page's leftovers — 11 reports whose index gap
// was exactly the old page's row count, all of them this diagnostic's own doing.
let nextTableId: number = 0;

export function newKeyTableId(prefix: string): string {
  nextTableId++;
  return `${prefix}#${nextTableId}`;
}

function tableFor(list: string): KeyTable {
  let t = tables.get(list);
  if (t === undefined) {
    t = new KeyTable();
    tables.set(list, t);
  }
  return t;
}

// Returns the key unchanged so it can wrap a key expression in place.
export function guardKey(list: string, index: number, key: string): string {
  const t = tableFor(list);
  const at = t.byKey.get(key);
  if (at !== undefined && at !== index) {
    logE(`[KeyGuard] ${list}: key claimed by index ${index} and ${at} -> ${key}`);
  }
  // Whatever this index held before is gone; drop its reverse entry so a stale
  // key cannot outlive the row that produced it.
  const previous = t.byIndex.get(index);
  if (previous !== undefined && previous !== key && t.byKey.get(previous) === index) {
    t.byKey.delete(previous);
  }
  t.byIndex.set(index, key);
  t.byKey.set(key, index);
  return key;
}

// RELOAD invalidates every key the framework holds.
export function keyTableReload(list: string): void {
  tables.set(list, new KeyTable());
}

// ADD at `index` shifts every row at or after it up by `count`.
export function keyTableAdd(list: string, index: number, count: number): void {
  shift(list, index, count);
}

// DELETE drops the removed rows and shifts the rest down.
export function keyTableDelete(list: string, index: number, count: number): void {
  const t = tableFor(list);
  for (let i = index; i < index + count; i++) {
    const key = t.byIndex.get(i);
    if (key !== undefined && t.byKey.get(key) === i) {
      t.byKey.delete(key);
    }
    t.byIndex.delete(i);
  }
  shift(list, index + count, -count);
}

function shift(list: string, from: number, by: number): void {
  const t = tableFor(list);
  const moved: KeyTable = new KeyTable();
  t.byIndex.forEach((key: string, idx: number): void => {
    const target = idx >= from ? idx + by : idx;
    moved.byIndex.set(target, key);
    moved.byKey.set(key, target);
  });
  tables.set(list, moved);
}
