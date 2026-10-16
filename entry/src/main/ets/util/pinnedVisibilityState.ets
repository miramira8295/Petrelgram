export interface PinnedVisibilityStorage {
  read: (key: string) => boolean;
  write: (key: string, hidden: boolean) => void;
}

export function pinnedVisibilityKey(account: string, chatId: number): string {
  return account !== '' && chatId !== 0 ? `${account}:${chatId}` : '';
}

@ObservedV2
export class PinnedVisibility {
  @Trace hidden: boolean = false;
  private key: string;
  private storage: PinnedVisibilityStorage | null;

  constructor(key: string = '', storage: PinnedVisibilityStorage | null = null) {
    this.key = key;
    this.storage = storage;
    if (key !== '' && storage !== null) { this.hidden = storage.read(key); }
  }

  toggle(): void {
    if (this.storage === null || this.key === '') { return; }
    const next = !this.hidden;
    this.storage.write(this.key, next);
    this.hidden = next;
  }
}
