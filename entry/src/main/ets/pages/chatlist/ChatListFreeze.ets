import { ChatEntry } from '../../store/ChatEntry';

// AppStorage flag: true while a chat row's context menu is on screen.
//
// Chat list rows are keyed by a compact render revision because ForEach only
// re-renders a row when its key changes. That makes an incoming message
// re-create the affected row — and destroy the context menu bound to it.
// So while a menu is open the list holds its last rendering and buffers updates,
// applying the newest one as soon as the menu closes.
export const CHAT_MENU_OPEN: string = 'chatMenuOpen';
// Shared minute clock for every visible chat row. The parent page owns one
// timer instead of each folder list starting its own interval.
export const CHAT_LIST_NOW: string = 'chatListNowSec';

// Buffers chat-list updates for one list view. Not a store: purely a
// render-timing gate owned by the view.
export class ChatListFreeze {
  private pending: ChatEntry[] | null = null;

  // Returns the list to render now, or null to keep the current one. A covered
  // chat list uses the same newest-snapshot buffer as an open context menu:
  // subscriptions remain authoritative, but no @State/DataSource publication
  // reaches the hidden LazyForEach until the navigation transition has settled.
  accept(list: ChatEntry[], renderActive: boolean = true): ChatEntry[] | null {
    if (!renderActive || AppStorage.get<boolean>(CHAT_MENU_OPEN) === true) {
      this.pending = list;
      return null;
    }
    this.pending = null;
    return list;
  }

  // Called when the menu closes: the newest buffered list, if any arrived.
  flush(): ChatEntry[] | null {
    const p = this.pending;
    this.pending = null;
    return p;
  }
}
