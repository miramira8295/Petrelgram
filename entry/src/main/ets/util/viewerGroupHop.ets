// 查看器翻到本组头/尾之后，再用力拉一下切到上一组/下一组媒体。
//
// 这不是"整个会话连成一条随便翻"（那一版试过，撤了）。区别在于**要越界再拉
// 一次**：拉的过程中弹出气泡告诉你下一组是什么，拉够了松手才切，拉回去就什么
// 都不发生。翻页和切组因此是两个动作，不会手一滑就跑到别的相册里去。
//
// 抽成纯函数是因为这里全是符号和边界：越界方向的正负、进度的夹取、往前/往后
// 找下一组媒体时跳过非媒体行、以及"没有下一组"。这些混在手势回调里最难看清。

// 越界的方向。0 = 没有越界（正常翻页中，或者拖的方向指向组内的另一页）。
// +1 = 想去下一组（更新），-1 = 想去上一组（更旧）。
//
// 符号约定跟 Swiper 的 currentOffset 走：内容往左拖（露出下一页）是负数。
// 所以"停在最后一页还继续往左拖"= pageIdx 到顶 且 offset < 0。
//
// 只有一页时两个条件都可能成立，这是**故意**的：单图消息本来就没有组内翻页，
// 左拉去下一组、右拉去上一组，正是它该有的行为。
export function hopDirection(
  pageIdx: number, pageCount: number, currentOffset: number
): number {
  if (pageCount <= 0) {
    return 0;
  }
  if (pageIdx >= pageCount - 1 && currentOffset < 0) {
    return 1;
  }
  if (pageIdx <= 0 && currentOffset > 0) {
    return -1;
  }
  return 0;
}

// 拉了多少，0..1。到 1 就是"松手即切"。
// threshold <= 0 视为无效，直接给 0，免得除出 Infinity 让气泡瞬间满格。
export function hopProgress(currentOffset: number, threshold: number): number {
  if (threshold <= 0) {
    return 0;
  }
  return Math.min(1, Math.abs(currentOffset) / threshold);
}

// 从 from 出发往 dir 方向找下一组媒体行，返回下标；找不到返回 -1。
//
// 要跳过非媒体行（文字、系统消息、贴纸……）：用户拉的是"下一组媒体"，中间隔着
// 几十条聊天记录不该让这个动作失效。
export function nextMediaGroupIndex(
  count: number, from: number, dir: number, isMedia: (index: number) => boolean
): number {
  if (dir === 0 || from < 0 || from >= count) {
    return -1;
  }
  for (let i = from + dir; i >= 0 && i < count; i += dir) {
    if (isMedia(i)) {
      return i;
    }
  }
  return -1;
}
