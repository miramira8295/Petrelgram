// 输入框下面那块高度归谁：没人、附件抽屉、表情/贴纸抽屉、机器人回复键盘。
//
// 三者共用同一块位置，互斥此前是散在十几处的赋值维持的——开表情的地方写
// `replyKbCollapsed = true`，开附件的地方写 `setEmojiPanel(false)`，各写各的。
// 规则因此并不一致：**开表情会收起机器人键盘，开附件却不会**，于是附件抽屉
// 和机器人键盘可以同时展开，把 dock 撑成两层高。
//
// 做成"一块高度只有一个主人"之后，这类不一致没有存在的余地：任何一个打开，
// 另外两个自动让位。
//
// 只管"谁占着"，不管分帧挂载、键盘收起、动画时序——那些只有页面做得了。

export const SLOT_NONE: string = 'none';
export const SLOT_ATTACH: string = 'attach';
export const SLOT_EMOJI: string = 'emoji';
export const SLOT_REPLY_KB: string = 'replyKeyboard';

// 打开某个占位者。同一个再打开一次是空操作（不是关闭）——关闭要显式说。
export function openSlot(current: string, next: string): string {
  return next;
}

export function closeSlot(current: string, target: string): string {
  return current === target ? SLOT_NONE : current;
}

export function closeAllSlots(): string {
  return SLOT_NONE;
}

// 异步到达的东西只在无人占位时入座。机器人键盘是随消息来的，不该把用户
// 手动打开的抽屉顶掉——用户开抽屉时 composerFocused 已经是 false，只按
// "没在打字"判断会误伤。
export function claimIfFree(current: string, next: string): string {
  return current === SLOT_NONE ? next : current;
}

// 点同一个入口第二次是收起。附件按钮和机器人键盘按钮都是这个语义。
export function toggleSlot(current: string, target: string): string {
  return current === target ? SLOT_NONE : target;
}

// 这块高度现在有没有被占。机器人键盘算占——它和抽屉一样把 dock 撑高。
export function slotOccupied(current: string): boolean {
  return current !== SLOT_NONE;
}

// 抽屉（附件/表情）占位时才需要让出系统键盘的高度；机器人键盘是随消息来的
// 一排按钮，和系统键盘可以并存。
export function slotIsDrawer(current: string): boolean {
  return current === SLOT_ATTACH || current === SLOT_EMOJI;
}
