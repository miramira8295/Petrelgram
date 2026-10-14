// 覆盖范围是当前聊天列，而不是整个窗口：分栏里其他仍可见的区域不受影响。
export function chatMotionAllowed(pageVisible: boolean, foreground: boolean, chatCovered: boolean): boolean {
  return pageVisible && foreground && !chatCovered;
}

export function chatTimelineSuspended(allowed: boolean, initialStage: boolean,
  scrolling: boolean, settling: boolean): boolean {
  return !allowed || initialStage || scrolling || settling;
}
