// Presentation history only: never deletes a conversation or its messages.
export interface RecentChatHistoryState {
  cleared: boolean;
  hidden: number[];
  reopened: number[];
}

export interface RecentChatHistoryStorage {
  read(): RecentChatHistoryState;
  write(state: RecentChatHistoryState): void;
}

export function emptyRecentChatHistory(): RecentChatHistoryState {
  return { cleared: false, hidden: [], reopened: [] };
}

function validIds(ids: number[]): boolean {
  return Array.isArray(ids) && ids.every((id: number): boolean => Number.isSafeInteger(id) && id !== 0);
}

export class RecentChatHistory {
  private storage: RecentChatHistoryStorage;
  private state: RecentChatHistoryState | undefined = undefined;
  private listeners: Array<() => void> = [];
  constructor(storage: RecentChatHistoryStorage) { this.storage = storage; }

  private current(): RecentChatHistoryState {
    if (this.state === undefined) {
      const state = this.storage.read();
      if (typeof state.cleared !== 'boolean' || !validIds(state.hidden) || !validIds(state.reopened)) {
        throw new Error('invalid recent chat history');
      }
      this.state = state;
    }
    return this.state;
  }

  filter(ids: number[]): number[] {
    const state = this.current();
    return ids.filter((id: number): boolean => state.hidden.indexOf(id) < 0 &&
      (!state.cleared || state.reopened.indexOf(id) >= 0));
  }

  private save(state: RecentChatHistoryState): void {
    // Publish only after durable storage succeeds, so failed deletion leaves the UI intact.
    this.storage.write(state);
    this.state = state;
    this.listeners.slice().forEach((listener: () => void): void => listener());
  }

  clear(): void { this.save({ cleared: true, hidden: [], reopened: [] }); }

  remove(chatId: number): void {
    if (!Number.isSafeInteger(chatId) || chatId === 0) { return; }
    const state = this.current();
    if (state.cleared) {
      this.save({ cleared: true, hidden: [], reopened: state.reopened.filter((id: number): boolean => id !== chatId) });
    } else if (state.hidden.indexOf(chatId) < 0) {
      this.save({ cleared: false, hidden: [...state.hidden, chatId], reopened: [] });
    }
  }

  opened(chatId: number): void {
    if (!Number.isSafeInteger(chatId) || chatId === 0) { return; }
    const state = this.current();
    if (state.cleared) {
      // TDLib's landing list is limited to 30. Keep the same bounded reopen window.
      this.save({ cleared: true, hidden: [], reopened: [chatId,
        ...state.reopened.filter((id: number): boolean => id !== chatId)].slice(0, 30) });
    } else if (state.hidden.indexOf(chatId) >= 0) {
      this.save({ cleared: false, hidden: state.hidden.filter((id: number): boolean => id !== chatId), reopened: [] });
    }
  }

  subscribe(listener: () => void): () => void {
    this.listeners.push(listener);
    return (): void => { this.listeners = this.listeners.filter((item: () => void): boolean => item !== listener); };
  }
}
