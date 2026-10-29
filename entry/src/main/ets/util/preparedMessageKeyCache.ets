// Cache only the preparation key, never the row's reuseId or prepared result.
// The owner still performs the normal bounded Map lookup/eviction every time.
interface PreparedKeyEntry {
  rowKey: string;
  chatId: number;
  flags: number;
  slot: string;
  slotStart: number;
  messageRevision: number;
  backgroundRevision: number;
  width: number;
  selected: number[];
  pageKey: string;
  key: string;
}

function sameSelected(a: number[], b: number[]): boolean {
  if (a.length !== b.length) { return false; }
  for (let i: number = 0; i < a.length; i++) {
    if (a[i] !== b[i]) { return false; }
  }
  return true;
}

function keyBit(flags: number, index: number): number {
  return (flags >>> index) & 1;
}

export class PreparedMessageKeyCache {
  private entries: WeakMap<Object, PreparedKeyEntry> = new WeakMap<Object, PreparedKeyEntry>();

  clear(): void { this.entries = new WeakMap<Object, PreparedKeyEntry>(); }

  prepare(row: Object, rowKey: string, chatId: number, flags: number,
    slot: string, slotStart: number, messageRevision: number, backgroundRevision: number,
    width: number, selected: number[], pageKey: string): string {
    const previous: PreparedKeyEntry | undefined = this.entries.get(row);
    if (previous !== undefined && previous.rowKey === rowKey && previous.chatId === chatId &&
      previous.flags === flags && previous.slot === slot && previous.slotStart === slotStart &&
      previous.messageRevision === messageRevision && previous.backgroundRevision === backgroundRevision &&
      previous.width === width && previous.pageKey === pageKey && sameSelected(previous.selected, selected)) {
      return previous.key;
    }
    const key: string = `${rowKey}|c${chatId}|lw${keyBit(flags, 0)}` +
      `|u${keyBit(flags, 1)}|r${keyBit(flags, 2)}` +
      `|editable${keyBit(flags, 3)}|poll${keyBit(flags, 4)}` +
      `|pin${keyBit(flags, 5)}|paid${keyBit(flags, 6)}` +
      `|anim${keyBit(flags, 7)}${keyBit(flags, 8)}${keyBit(flags, 9)}` +
      `|fresh${keyBit(flags, 10)}|slot${slot}|slotms${slotStart}` +
      `|msg${messageRevision}|bg${backgroundRevision}|width${width}|selm${selected.join(',')}` + pageKey;
    this.entries.set(row, { rowKey: rowKey, chatId: chatId, flags: flags, slot: slot,
      slotStart: slotStart, messageRevision: messageRevision, backgroundRevision: backgroundRevision,
      width: width, selected: selected.slice(), pageKey: pageKey, key: key });
    return key;
  }
}
