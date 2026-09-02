// 相册格子在 ForEach 里的键。
//
// 【为什么不能用纯位置】原来这两个键是 `row_${rowIdx}` / `cell_${cell.idx}`——
// 只有位置，不带任何身份。ForEach 的契约是「键值不变就复用已有组件、**不重新
// 执行子构建函数**」，而 AlbumCell 只有 {idx, width, height} 三个几何字段，
// 真正在变的 fileId / memberId 是在构建函数里从 `this.` 读的。
//
// 于是：一个已经画过相册 A 的行被复用去画相册 B 时，只要**两条消息的图片张数
// 相同**，两层键就完全一样，ForEach 判定"没变化"，格子里的 LiveThumbImage 还
// 挂在 A 的 fileId 上；而正文、时间、表态都在 ForEach 之外，照常更新成 B 的。
// 用户看到的就是「配图配错了文」，并且**只在格式一致的频道上出现**——那种频道
// 里相邻两条的图片张数总是相同的。真机实报正是这个形状。
//
// 【为什么这些字段必须留在内层 key】整行 Repeat key 只表示稳定的相册身份，
// 历史分页补进成员时不会再换。AlbumGroup 对象变化会刷新气泡，而这两层
// ForEach 必须继续按 memberId + fileId 配对，才能让新增/替换的媒体格拿到正确
// 图片，不重新出现“图是这一条、文字是上一条”的错配。
//
// 【路径为什么不进 key】缩略图路径走旁路通道（见 mediaThumbChannel /
// LiveThumbImage），图落地时**不该**重建这一行——那正是旁路通道存在的理由。
// 进 key 的三样都不随下载进度变化。

// 一格的身份：属于哪条消息、缩略图是哪个文件、是视频还是图片。
// 视频与图片在 albumGrid 里走的是两棵完全不同的子树，所以它也是身份的一部分。
export function albumCellKey(
  index: number, memberId: number, fileId: number, isVideo: boolean
): string {
  return `cell_${index}_${memberId}_${fileId}_${isVideo ? 'v' : 'p'}`;
}

// 一行的身份 = 位置 + 这一行所有格子的身份。
//
// **外层也必须带身份**：外层键不变时 ForEach 连行的构建函数都不会重跑，内层
// 那个 ForEach 根本没有机会被重新求值——只修内层是修不动的。
export function albumRowKey(rowIndex: number, cellKeys: string[]): string {
  return `row_${rowIndex}_${cellKeys.join('|')}`;
}
