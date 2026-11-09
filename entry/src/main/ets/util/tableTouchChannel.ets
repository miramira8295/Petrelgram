// 「手指正压在一张可横滑的表格上」的旁路标记。
//
// 【为什么需要它】消息行整行挂着 parallelGesture 的横向 PanGesture（左滑回复 /
// 右滑多选，distance 8）。parallelGesture 的语义就是**和子孙手势并行跑**——
// 所以横滑气泡里的表格时，表格在滚、整行也跟着滑出去（用户 2026-09-22 实报）。
// 子节点这边没有任何属性能让父节点那条并行手势让路。
//
// 于是反过来：表格在按下时把这个标记打开，消息行的滑动回调看到它就不起手。
// 触摸事件是**冒泡**的，子节点的 onTouch 先于父节点触发（MessageBubble 那边
// 「onTouch 落在任何子元素上都会走到这里，所以一定发生在子元素判定之前」说的
// 就是这个顺序），所以父节点读到的一定是本次按下写的值。
//
// 【为什么还要一个时间戳兜底】万一某次抬手/取消事件没送到（手势被系统接管、
// 组件在拖动中途被复用掉），标记就会一直挂着，之后所有消息都滑不动回复了。
// 超过这个时长一律当作过期——一次拖动不可能持续这么久还没有任何抬手事件。
const STALE_MS: number = 4000;

let touching: boolean = false;
let touchedAt: number = 0;

export function setTableScrollTouch(on: boolean): void {
  touching = on;
  touchedAt = on ? Date.now() : 0;
}

export function tableScrollTouched(): boolean {
  if (!touching) {
    return false;
  }
  if (Date.now() - touchedAt > STALE_MS) {
    touching = false;
    return false;
  }
  return true;
}

export function resetTableScrollTouchForTest(): void {
  touching = false;
  touchedAt = 0;
}
