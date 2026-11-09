// 文件夹页签列表的滚动位置记忆。
//
// Tabs.cachedMaxCount 会释放 当前±范围 之外的页签子树；在此之前所有建过的
// 页签永久保活，位置天然保留。释放再重建的 List 会回到顶部——这里按 listKey
// 记住首个可见行下标，重建时经 List 的 initialIndex 恢复，抵消这条行为回退。
//
// 只在进程内存活：跨启动时数据本身都是新拉的，位置没有意义。归档页不参与
// （它是每次进入重建的 NavDestination，历来从顶部开始，不改这个预期）。

const positions: Map<string, number> = new Map<string, number>();

export function rememberListPosition(listKey: string, firstVisibleIndex: number): void {
  positions.set(listKey, firstVisibleIndex);
}

export function recallListPosition(listKey: string): number {
  return positions.get(listKey) ?? 0;
}
