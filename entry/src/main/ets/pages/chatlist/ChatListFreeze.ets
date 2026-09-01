import { ChatEntry } from '../../store/ChatEntry';

// AppStorage flag: true while a chat row's context menu is on screen.
//
// Chat list rows are keyed by a compact render revision because ForEach only
// re-renders a row when its key changes. That makes an incoming message
// re-create the affected row — and destroy the context menu bound to it.
// So while a menu is open the list holds its last rendering and buffers updates,
// applying the newest one as soon as the menu closes.
export const CHAT_MENU_OPEN: string = 'chatMenuOpen';
// AppStorage flag: true while a finger is down on a chat list. Long-pressing a
// row used to let an incoming update reorder the list mid-press (the pressed
// row slid away under the finger — the menu gate only closes once the menu is
// already on screen). Data keeps flowing; only publications wait for lift-off,
// which also defers the 180ms reorder animation to after the gesture.
export const CHAT_LIST_TOUCH_HOLD: string = 'chatListTouchHold';
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
    if (!renderActive || AppStorage.get<boolean>(CHAT_MENU_OPEN) === true
      || AppStorage.get<boolean>(CHAT_LIST_TOUCH_HOLD) === true) {
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

// List.onTouch 用：Down 关闸，Up/**Cancel 都**开闸——横滑被 Swiper 抢走手势
// 时列表收到的是 Cancel，漏了它闸就永远卡死。双指场景一指抬起会提前开闸，
// 列表上双指按住是极冷门场景，不为它数指头。
export function updateTouchHold(type: TouchType): void {
  if (type === TouchType.Down) {
    setTouchHold(true);
  } else if (type === TouchType.Up || type === TouchType.Cancel) {
    setTouchHold(false);
  }
}

function setTouchHold(value: boolean): void {
  if ((AppStorage.get<boolean>(CHAT_LIST_TOUCH_HOLD) ?? false) !== value) {
    AppStorage.setOrCreate(CHAT_LIST_TOUCH_HOLD, value);
  }
}
