export const KEY_HIDE_PINNED_DEFAULT: string = 'hidePinnedByDefault';

export interface PinnedVisibilityStorage {
  read: (key: string) => boolean | undefined;
  write: (key: string, hidden: boolean) => void;
}

export function pinnedVisibilityKey(account: string, chatId: number): string {
  return account !== '' && chatId !== 0 ? `${account}:${chatId}` : '';
}

@ObservedV2
export class PinnedVisibilityDefaults {
  @Trace hidden: boolean = false;
}

export const pinnedVisibilityDefaults: PinnedVisibilityDefaults = new PinnedVisibilityDefaults();

@ObservedV2
export class PinnedVisibility {
  @Trace private overrideHidden: boolean | undefined = undefined;
  private key: string;
  private storage: PinnedVisibilityStorage | null;
  private defaults: PinnedVisibilityDefaults;

  constructor(key: string = '', storage: PinnedVisibilityStorage | null = null,
    defaults: PinnedVisibilityDefaults = pinnedVisibilityDefaults) {
    this.key = key;
    this.storage = storage;
    this.defaults = defaults;
    if (key !== '' && storage !== null) { this.overrideHidden = storage.read(key); }
  }

  get hidden(): boolean {
    return this.overrideHidden ?? this.defaults.hidden;
  }

  toggle(): void {
    if (this.storage === null || this.key === '') { return; }
    const next = !this.hidden;
    this.storage.write(this.key, next);
    this.overrideHidden = next;
  }
}
