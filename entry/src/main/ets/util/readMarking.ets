// 已读推进的两个判定。
//
// TDLib 的已读状态是**高水位**：报上去一个 id，比它旧的全部算已读。所以只能
// 报"用户确实看到过的最大 id"——进会话不滚动，下面的就该保持未读。判错的方向
// 是单向的：报高了，没看的消息被吞掉，且再也回不来。

// 可见区末行往回找，第一条能代表"真实消息"的行，取其最大成员 id。
//
// 本地合成的服务行（例如自己那条"你加入了本群"提示）没有成员 id。它若正好
// 停在可见区末尾，直接取末行会得到 0，整个尾部就永远标不上已读——现象是角标
// 一直挂着。所以往回走，跳过这类行。
// 取访问器而不是整个二维数组：这个判定每次滚动都要跑一次，把上百行的
// memberIds 拷一遍是白花的开销。命中即停，通常只看末尾那一行。
export function newestVisibleMessageId(
  rowCount: number, memberIdsAt: (index: number) => number[], end: number
): number {
  if (end < 0 || end >= rowCount) {
    return 0;
  }
  for (let i = end; i >= 0; i--) {
    let best: number = 0;
    for (const id of memberIdsAt(i)) {
      if (id > best) {
        best = id;
      }
    }
    if (best > 0) {
      return best;
    }
  }
  return 0;
}

// 是不是真的站在实时尾部。
//
// 本地摘角标只在这个条件下做。只凭会话列表快照里的 lastMessageId 判断"读到
// 最新了"是不够的：那个值可能慢一拍，用户停在中段也可能满足，角标被提前摘掉
// 而下面还有新消息。权威在 MessageStore —— 没有更新的历史可拉，且最后一组
// 已经进入可见区。
//
// 这个错不会自愈：0 一旦写进会话列表缓存，若该会话此后没有任何更新，TDLib
// 不会再下发一次把它纠回来。
export function isAtLiveTail(end: number, rowCount: number, hasMoreNewer: boolean): boolean {
  return !hasMoreNewer && end >= rowCount - 1;
}
