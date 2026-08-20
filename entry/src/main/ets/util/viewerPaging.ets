// 全屏查看器能左右翻到哪些媒体。
//
// 原来只在相册内部翻：单图消息的 Swiper 里只有一页，双击放大、拖动、拖到边缘
// 翻页这几条代码早就有，只是没有下一页可去（issue #49）。改成翻遍**整个已加载
// 会话**的图片和视频，相册的情形被自然包含——album 成员在消息列表里本来就是
// 相邻的独立条目。
//
// 两件事必须同时成立，缺一个都会出问题：
//
//   开窗——Swiper 用的是 ForEach，所有页都会被建出来。一个翻了很久的会话里
//   媒体能有好几百条，不封顶就是几百个 Stack + Image。
//
//   冻结——列表在查看器打开的那一刻算一次就不再变。消息列表会随着滚动加载
//   历史而增长，中途改变列表长度会让 Swiper 的下标错位，画面直接跳到别处。
//   冻结的语义也更自然：查看器是盖在一份快照上的模态层。
//
// 抽成纯函数是因为这里全是下标边界：目标在列表头/尾、目标不在列表里、
// 列表比窗口短。这些混在组件的生命周期里最难看清，也最容易改错。

export interface MediaPageWindow {
  ids: number[];
  // currentId 在 ids 里的下标；ids 为空时是 -1。
  index: number;
}

// ids：按时间升序排好的全部媒体 id。half：当前这张前后各取多少张。
export function mediaPageWindow(
  ids: number[], currentId: number, half: number
): MediaPageWindow {
  const at: number = ids.indexOf(currentId);
  if (at < 0) {
    // 目标不在列表里（消息刚被撤回、或者根本不是媒体）。退化成只有它自己，
    // 查看器仍然能正常显示，只是翻不动——总好过空列表。
    return currentId !== 0
      ? { ids: [currentId], index: 0 }
      : { ids: [], index: -1 };
  }
  const from: number = Math.max(0, at - half);
  const to: number = Math.min(ids.length, at + half + 1);
  return { ids: ids.slice(from, to), index: at - from };
}
