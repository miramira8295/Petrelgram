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
  accept(list: ChatEntry[], renderActive: boolean = true,
    forceInitialContent: boolean = false): ChatEntry[] | null {
    // A neighbouring tab can be created while the finger-down gate is still
    // closed. Its first non-empty snapshot must paint once; otherwise the tab
    // enters the viewport as an empty list and only fills after swipe settle.
    // Callers only set this for an empty view receiving non-empty content, so
    // established lists still freeze every structural/content update.
    if (!forceInitialContent && (!renderActive || AppStorage.get<boolean>(CHAT_MENU_OPEN) === true
      || AppStorage.get<boolean>(CHAT_LIST_TOUCH_HOLD) === true)) {
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

// 两份快照的**身份顺序**是不是一样。一样 ⇒ 这次只是内容变了（未读数、最后
// 一条消息的文字、草稿……），发布出去不会重排，也就不需要那 180ms 动画。
//
// **为什么要提成公共函数**：这个判断有四个调用点——ChatListView 与
// MainTabBody 各自的 applyChats（决定要不要动画）和 onFlushRequested
// （决定转场里能不能放行）。四份手写的 length + 逐项 id 比较，改动画阈值时
// 漏掉一处的后果是静默的：某个列表在转场里放行了重排，或者反过来卡着不放。
export function chatOrderUnchanged(current: ChatEntry[], next: ChatEntry[]): boolean {
  if (current.length !== next.length) {
    return false;
  }
  for (let i: number = 0; i < current.length; i++) {
    if (current[i].id !== next[i].id) {
      return false;
    }
  }
  return true;
}

// 把新快照的**内容**贴到当前顺序上，返回可以立刻发布的那一份；没有内容变化
// 时返回 null。
//
// 【为什么需要它】用户报「有的时候聊天数字消失得快，有的时候又要等一会」。
// 返回转场里的旁路原来是"整份快照要么发、要么不发"：顺序变了就整份扣住等闸开。
// 可角标是**内容**，重排是**顺序**，它们只是碰巧坐在同一份快照里——你在 A 群
// 读完消息退出来，只要这期间任何一个别的会话来了条新消息，列表顺序就变了，
// 于是 A 群那个已经清零的角标也跟着一起等 640ms。快慢的分岔就在这里。
//
// 拆开之后：内容立刻发（角标马上消失），重排仍旧等闸开（那才是会掉帧的部分）。
//
// 【按 revision 判断有没有变】它是行 key 的组成部分（见 ChatListView.rowKey），
// cloneEntry 每次改动都会把它加一。用它而不是逐字段比：判据和"列表会不会重画
// 这一行"天然一致，不会出现"我认为没变、LazyForEach 却重画了"的偏差。
//
// 【不在 next 里的会话原样留着】离开的会话、翻页掉出去的会话，在这一小段里
// 仍然显示旧行——闸一开就会被真快照纠正。宁可留一行旧的，也不要为了它把
// 角标再扣住半秒。
export function contentOnlyUpdate(current: ChatEntry[], next: ChatEntry[]): ChatEntry[] | null {
  if (current.length === 0 || next.length === 0) {
    return null;
  }
  const byId: Map<number, ChatEntry> = new Map<number, ChatEntry>();
  for (let i = 0; i < next.length; i++) {
    byId.set(next[i].id, next[i]);
  }
  const out: ChatEntry[] = [];
  let changed: boolean = false;
  for (let i = 0; i < current.length; i++) {
    const cur: ChatEntry = current[i];
    const fresh: ChatEntry | undefined = byId.get(cur.id);
    if (fresh !== undefined && fresh.revision !== cur.revision) {
      changed = true;
      out.push(fresh);
    } else {
      out.push(cur);
    }
  }
  return changed ? out : null;
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
