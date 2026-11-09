// 把一维列表按每行 perRow 个切成行（最后一行可以不满）。
//
// 共享媒体网格原来是 Flex 折行 + ForEach：每一格都是提前建好的节点，翻了很多页的
// 群里就是几百上千格一起活着。要走 LazyForEach 就得把「格」换成「行」——List 的一项
// 是一行三格，滚动时按行建、按行复用（ProfileMediaRow）。
export function chunkRows<T>(items: T[], perRow: number): T[][] {
  const size: number = perRow >= 1 ? Math.floor(perRow) : 1;
  const rows: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    rows.push(items.slice(i, i + size));
  }
  return rows;
}
