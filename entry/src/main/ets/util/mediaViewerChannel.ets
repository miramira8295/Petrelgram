// 全屏媒体查看器的跨页旁路通道（MediaViewer 独立页面化，S4 批）。
//
// **为什么需要它。** 查看器要成为独立的 NavDestination（见
// docs/media-viewer-page-plan.md），而它和 ChatPage 之间有四条数据要来回走，
// 全部无法经 pathInfo.param 传：param 只在 push 那一刻求值一次，而这四条都是
// **持续的**或**反向的**。
//
// 形状与 chatJumpChannel / translationChannel / mediaThumbChannel 同构：
// 发布方不认识订阅方，键用 chatId，同步多播，不留待送队列。
//
// **四条通道各自为什么存在：**
//
// 1. data（ChatPage → 查看器）：查看器要跟着历史加载增长的 messages/groups 翻相册。
//    **发布的是 ChatPage 已经 commit 的那一份，不是 store 的原始快照。**
//    查看器**绝不能**自己 store.subscribe——onMessagesSnapshot 有两条早退
//    （historyState === 'loading'、resume fragment 守卫），那些被页面刻意扣住的
//    部分快照会让查看器的"当前消息不在列表里就自关"逻辑当着用户面把查看器关掉，
//    且不报错。另外 timelineSnapshot.groups 与现算的 collapseAlbums(list) 有一条
//    永久性差异（photoPaths 因 reuseUnchangedRows 而停在 ''），而查看器是全仓
//    唯一直接读行对象的地方——两份数据必须是同一份。
//
// 2. result（查看器 → ChatPage）：关闭时把播放进度与相册下标交回，
//    由 ChatPage 调 playSlot.handoffFromViewer()。
//    **必须同步发布，且必须早于 ChatPage 的 onShown**：coordinateChatPageShown
//    第 6 步就是 armPlaySlotSettle()，pin 若还没落下，它会选出一个错的播放位。
//    发布点在查看器出栈之前，天然满足。
//
// 3. save（查看器 → ChatPage）：媒体保存**整簇留在 ChatPage**，不跟着查看器走。
//    理由是 MessageStore.consumeLiveIncomingMediaIds() 是排干式读取，两份
//    onSnapshot 会互偷 id，自动保存到相册随机丢件且无任何报错（S2 已把这条
//    跨域读拆干净，这里只是把"请求"递回去）。
//
// 4. history（查看器 → ChatPage）：查看器翻到相册边缘要拉更多消息。
//    **由 ChatPage 代为发起，而不是查看器直接调 store.loadOlder()**，
//    这样加载不会被记成"页面隐藏期间的外部变更"（hiddenListDirty）——
//    否则返回时 resyncListAfterHidden 会命中"整表重建但不复位、不 glue"那一支，
//    列表停在任意位置且 atBottom 仍为 true。详见方案 §5.1。
//
// **不留待送队列**：四条的前提都是两端同时挂着（查看器在栈顶、ChatPage 在它下面
// 且没被销毁）。留"待送"反而会在下次打开时冒出一次陈旧的回传。

import { AlbumGroup } from './collapseAlbums';
import { MessageEntry } from '../store/MessageEntry';
import { MessageStore } from '../store/MessageStore';

// 查看器关闭时交回的东西。albumIndex 用 playSlot 的语义：整条消息 -1，
// 相册成员是该格在 memberIds 里的下标。
export interface MediaViewerResult {
  messageId: number;
  albumIndex: number;
  positionMs: number;
}

// 打开查看器页时一次性递过去的东西。
//
// **为什么不走 pathInfo.param**：store 是活对象（MessageStore 实例），而 nav 的
// param 是 Record<string, Object>，官方对它是否会被序列化/在状态恢复时重建没有
// 承诺。这里用一个模块级单槽手递手：push 之前 put，页面 aboutToAppear 里 take
// （取走即清）。栈顶同时只可能有一个查看器页，所以单槽够用。
//
// store 之所以能安全跨页递：它在一次会话里**身份从不改变**
// （ChatPage 的字段初始化只 new 一次），所以接收方不需要任何观测能力。
// 而 messages/groups 不能这样递——上游是整表换引用，递过去的会是一份冻结的旧
// 引用，必须走 data 通道持续多播。
export interface MediaViewerSession {
  chatId: number;
  messageId: number;
  initIdx: number;
  startPositionMs: number;
  chatTitle: string;
  store: MessageStore;
}

let pending: MediaViewerSession | null = null;

export function putViewerSession(session: MediaViewerSession): void {
  pending = session;
}

// 取走即清。取不到返回 null——页面遇到这种情况应当立刻退栈（不该发生，
// 但比拿一份陈旧的 session 渲染要好）。
export function takeViewerSession(): MediaViewerSession | null {
  const s: MediaViewerSession | null = pending;
  pending = null;
  return s;
}

type DataListener = (messages: MessageEntry[], groups: AlbumGroup[]) => void;
type ResultListener = (result: MediaViewerResult) => void;
type SaveListener = (messageId: number, toFiles: boolean) => void;
type HistoryListener = (dir: number) => void;

const dataSubs: Map<number, Set<DataListener>> = new Map();
const resultSubs: Map<number, Set<ResultListener>> = new Map();
const saveSubs: Map<number, Set<SaveListener>> = new Map();
const historySubs: Map<number, Set<HistoryListener>> = new Map();

// 四条通道的订阅/退订形状完全一样，但 ArkTS 没有好用的泛型闭包写法，
// 逐条展开——重复四遍好过一个看不懂的抽象。

function unsubscribe<T>(subs: Map<number, Set<T>>, chatId: number, listener: T): void {
  const current: Set<T> | undefined = subs.get(chatId);
  if (current === undefined) {
    return;
  }
  current.delete(listener);
  if (current.size === 0) {
    subs.delete(chatId);
  }
}

function subscribe<T>(subs: Map<number, Set<T>>, chatId: number, listener: T): () => void {
  let listeners: Set<T> | undefined = subs.get(chatId);
  if (listeners === undefined) {
    listeners = new Set<T>();
    subs.set(chatId, listeners);
  }
  listeners.add(listener);
  return (): void => { unsubscribe(subs, chatId, listener); };
}

// ——— 1. data：ChatPage 已发布的快照 → 查看器 ———

export function subscribeViewerData(chatId: number, listener: DataListener): () => void {
  return subscribe(dataSubs, chatId, listener);
}

// 调用点：ChatPage.publishSnapshotAndChrome 的末尾。没有订阅者（查看器没开）
// 就是空操作，不排队。
export function publishViewerData(
  chatId: number, messages: MessageEntry[], groups: AlbumGroup[]
): void {
  if (chatId === 0) {
    return;
  }
  const listeners: Set<DataListener> | undefined = dataSubs.get(chatId);
  if (listeners === undefined) {
    return;
  }
  listeners.forEach((cb: DataListener): void => cb(messages, groups));
}

// ——— 2. result：查看器关闭 → ChatPage 的播放位交接 ———

export function subscribeViewerResult(chatId: number, listener: ResultListener): () => void {
  return subscribe(resultSubs, chatId, listener);
}

// **同步多播。** 调用点必须在查看器出栈之前，见文件头第 2 条。
export function publishViewerResult(chatId: number, result: MediaViewerResult): void {
  if (chatId === 0) {
    return;
  }
  const listeners: Set<ResultListener> | undefined = resultSubs.get(chatId);
  if (listeners === undefined) {
    return;
  }
  listeners.forEach((cb: ResultListener): void => cb(result));
}

// ——— 3. save：查看器点保存 → ChatPage 的 MediaSaveState ———

export function subscribeMediaSave(chatId: number, listener: SaveListener): () => void {
  return subscribe(saveSubs, chatId, listener);
}

export function requestMediaSave(chatId: number, messageId: number, toFiles: boolean): void {
  if (chatId === 0 || messageId <= 0) {
    return;
  }
  const listeners: Set<SaveListener> | undefined = saveSubs.get(chatId);
  if (listeners === undefined) {
    return;
  }
  listeners.forEach((cb: SaveListener): void => cb(messageId, toFiles));
}

// ——— 4. history：查看器翻到边缘 → ChatPage 代为拉历史 ———

export function subscribeViewerHistory(chatId: number, listener: HistoryListener): () => void {
  return subscribe(historySubs, chatId, listener);
}

// dir < 0 拉更早，dir > 0 拉更新。语义与今天 MediaViewerOverlay 的
// onNeedHistory(dir) 逐字相同。
export function requestViewerHistory(chatId: number, dir: number): void {
  if (chatId === 0 || dir === 0) {
    return;
  }
  const listeners: Set<HistoryListener> | undefined = historySubs.get(chatId);
  if (listeners === undefined) {
    return;
  }
  listeners.forEach((cb: HistoryListener): void => cb(dir));
}

// 只给单测用：模块级 Map 在同一个进程里跨用例活着（照 chatJumpChannel）。
export function resetMediaViewerChannel(): void {
  pending = null;
  dataSubs.clear();
  resultSubs.clear();
  saveSubs.clear();
  historySubs.clear();
}
