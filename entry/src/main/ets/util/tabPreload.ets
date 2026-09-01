// 文件夹页签的邻居预载：挑下一个值得 preloadItems 的页签。
//
// 背景（Frame 录制 20260901T184104）：页签内容是整页会话列表，首次滑进一个
// 页签要在手势首帧里同步构建+测量整屏 9 行 ChatRow，实测 74/81ms，120Hz 下
// 丢 8-9 拍。TabsController.preloadItems 能提前构建，但它是**调用即一次性
// 构建**——时机不对只是把卡顿搬家。所以这里只负责"挑谁"，并且一次只挑一个：
// 单个页签 ~60ms，左右一起预载就是单帧 120ms。
//
// 按 key 记账而不是下标：文件夹增删/重排时下标会漂移，而 ForEach 的子树
// 跟着 key 走，谁构建过只有 key 说得准。

// 右邻优先：从左往右逐个滑是最常见的浏览路径；往回滑时来路上的页签本来
// 就建过，左邻自然轮空，不需要方向信息。
export function nextTabPreloadIndex(keys: string[], current: number, built: Set<string>): number {
  if (current < 0 || current >= keys.length) {
    return -1;
  }
  const candidates: number[] = [current + 1, current - 1];
  for (const index of candidates) {
    const key = keys[index];
    if (key !== undefined && !built.has(key)) {
      return index;
    }
  }
  return -1;
}
