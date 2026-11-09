import { ChatBackgroundState } from '../store/ChatBackgroundStore';

export interface WallpaperEditorSource {
  seedFromDefault: () => void;
  subscribe: (listener: (state: ChatBackgroundState) => void) => (() => void);
  open: (chatId: number) => void;
  close: () => void;
}

// The editor owns one resolver for one slot. Late callbacks cannot replace a newer selection.
export class WallpaperEditorSession {
  private source: WallpaperEditorSource | null = null;
  private unsubscribe: (() => void) | null = null;
  private revision: number = 0;

  open(source: WallpaperEditorSource, chatId: number,
    active: () => boolean, publish: (state: ChatBackgroundState) => void): void {
    this.close();
    const revision: number = this.revision;
    this.source = source;
    if (chatId === 0) { source.seedFromDefault(); }
    this.unsubscribe = source.subscribe((state: ChatBackgroundState): void => {
      if (revision === this.revision && active()) { publish(state); }
    });
    source.open(chatId);
  }

  close(): void {
    this.revision++;
    this.unsubscribe?.(); this.unsubscribe = null;
    this.source?.close(); this.source = null;
  }
}
