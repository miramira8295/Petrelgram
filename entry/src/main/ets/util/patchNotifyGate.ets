// 「这次 patch 值得发一次快照吗」的判据。
//
// **背景（有真机数据）。** ChatPage 每收到一次 store 的 notify 就把**整个已加载
// 窗口**重新 collapseAlbums 一遍。util/mediaProgressChannel 文件头记着当时的实测：
//
//   真机实测（列表 421 条时）：每次 store notify 要 8–20ms 主线程 JS，其中
//   publish 段 6–15ms……滑动时进度每秒变 13 次，notify 每秒 10 次。
//
// 而 messages 数组只增不减，所以这条开销随停留时长线性增长——「在同一个群里读久
// 了就发烫、退出重进就好些」正是这个形状。
//
// **问题在哪。** MessageStore 的 patchStickerEntries / patchVideoEntries /
// patchLinkPreviewEntries 三支都是无条件 `changed = true` 后 notifySoon()：
// 进度从 40 跳到 41 也发一次。而**进度根本不在行 key 里**——它走
// mediaProgressChannel 旁路直达 LiveProgressRing——所以这些发布产生的可见变化
// 恰好是零。同一个文件里行内缩略图那一支早就用 inlineThumbEntryChanged 守着，
// 并注明「这一支因此一律不再发 notifySoon()」；这三支是同一件事漏掉的三个地方。
//
// **判据为什么保守。** 只在「差别仅仅是进度数字」时跳过。路径落地、失败标志、
// 下载活跃态一律照发：
//   · 路径是行 key 的输入，跳过会让贴纸/视频永远不显示——这是本次改动最大的
//     风险点，宁可多发几次也不能漏；
//   · 活跃态一次下载只翻两次（开始/结束），省它没有意义。
// 进度是唯一的高频项（每秒十几次），也是唯一确定不影响渲染的。

// 一次 patch 前后的「非进度」字段快照。三支各自的 fn 只碰这四类字段。
export interface PatchSignature {
  path: string;
  failed: boolean;
  active: boolean;
}

// 值得发快照吗：非进度字段有任何变化就发。
//
// 注意**不比较进度**——那正是要跳过的东西。调用方仍然要把进度写进 entry
// （状态得是最新的），只是不因它触发一次全窗重建。
export function patchNeedsNotify(before: PatchSignature, after: PatchSignature): boolean {
  return before.path !== after.path
    || before.failed !== after.failed
    || before.active !== after.active;
}
