// 「跳到某条消息」的旁路通道。
//
// **为什么需要它。** 所有会话入口都走 navigateToChat，而它的去重规则只问一句
// 「这个会话是不是已经开着」（splitRouting.decideChatPush）：
//
//   已在栈顶      → skip，什么都不做
//   压在上面几层  → popTo，出栈回到它
//
// 两条路都**只负责把那一页弄到眼前，不传参**——于是 params 里的 jumpTo 被整个
// 丢掉。表现就是：
//   - 从会话资料页点媒体/文件：回到聊天页，但停在原来的位置（issue #102 报的）；
//   - 搜索结果落在一个已经打开的会话里：落点不是那条消息（issue #80「定位不准」）。
// ChatPage 里的 [Jump80] 探针只在 push 那条路上打得出来，skip/popTo 根本走不到，
// 所以之前对着日志查不出所以然。
//
// **为什么是旁路而不是改路由。** 已经挂在树上的那个 ChatPage 不会因为 popTo
// 重新吃一遍 pathInfo（栈帧的参数没变），没有任何"重新传参"的口子。和
// translationChannel / mediaThumbChannel 同构：发布方不认识订阅方，键用 chatId。
//
// **不留待送队列**：skip/popTo 的前提就是那一页已经挂着、也已经订阅了，没有
// 竞态；而留一份"待送"反而会在下次打开同一个会话时冒出一次陈旧的跳转。
// push 那条路本来就把 jumpTo 放在参数里，不经过这里。

type JumpListener = (messageId: number) => void;

const subs: Map<number, Set<JumpListener>> = new Map();

// 返回退订函数，交给调用方的订阅登记册管理。
export function subscribeChatJump(chatId: number, listener: JumpListener): () => void {
  let listeners: Set<JumpListener> | undefined = subs.get(chatId);
  if (listeners === undefined) {
    listeners = new Set<JumpListener>();
    subs.set(chatId, listeners);
  }
  listeners.add(listener);
  return (): void => {
    const current: Set<JumpListener> | undefined = subs.get(chatId);
    if (current === undefined) {
      return;
    }
    current.delete(listener);
    if (current.size === 0) {
      subs.delete(chatId);
    }
  };
}

// 没有订阅者就是"这个会话现在没开着"——静默丢弃，不排队。
export function requestChatJump(chatId: number, messageId: number): void {
  if (chatId === 0 || messageId <= 0) {
    return;
  }
  const listeners: Set<JumpListener> | undefined = subs.get(chatId);
  if (listeners === undefined) {
    return;
  }
  listeners.forEach((cb: JumpListener): void => cb(messageId));
}

// 只给单测用：模块级 Map 在同一个进程里跨用例活着。
export function resetChatJumpChannel(): void {
  subs.clear();
}
