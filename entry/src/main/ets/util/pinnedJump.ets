// 点置顶条：这一下该做什么。
//
// 置顶条是个循环器——反复点会在多条置顶之间轮转，转到最后一条再点就回到
// 「当前」（最新消息）。这条循环规则不直观，而且它的判据里混着视口位置，
// 很容易在改动中被抹掉，所以单独拿出来钉住。

import { pinnedShownIndex } from './pinnedSegments';

export const PINNED_IGNORE: string = 'ignore';   // 跳转守卫里，什么都不做
export const PINNED_RETRY: string = 'retry';     // 置顶列表没取到，重取
export const PINNED_EMPTY: string = 'empty';     // 一条置顶都没有，把条清掉
export const PINNED_LATEST: string = 'latest';   // 循环回到最新消息
export const PINNED_JUMP: string = 'jump';       // 目标已在列表里，直接滚过去
export const PINNED_LOAD: string = 'load';       // 目标不在窗口内，先去取

export interface PinnedTapInput {
  // 上一次跳转的守卫还没过期。
  busy: boolean;
  // 'loading' | 'ready' | 'error'
  loadState: string;
  // 会话的置顶消息 id，新 → 旧。
  pinnedIds: number[];
  // 当前轮转到第几条。
  cycle: number;
  // 视口最上面那条消息的 id；取不到时为 0。
  topVisibleId: number;
}

export interface PinnedTap {
  kind: string;
  // PINNED_JUMP / PINNED_LOAD 的目标消息。
  targetId: number;
  // PINNED_JUMP 时目标在当前列表里的行号。
  index: number;
}

function tap(kind: string, targetId: number, index: number): PinnedTap {
  return { kind: kind, targetId: targetId, index: index };
}

// loadedIndexOf：目标消息在当前已加载列表里的行号，不在则返回负数。
export function pinnedTapAction(
  input: PinnedTapInput, loadedIndexOf: (messageId: number) => number
): PinnedTap {
  if (input.busy) {
    return tap(PINNED_IGNORE, 0, -1);
  }
  if (input.loadState === 'error') {
    return tap(PINNED_RETRY, 0, -1);
  }
  const ids: number[] = input.pinnedIds;
  if (ids.length === 0) {
    return tap(PINNED_EMPTY, 0, -1);
  }
  // 用 ids.length 而不是外部维护的计数来夹：两者由不同的订阅更新，中间有窗口
  // 期可能不一致，拿大的那个去索引会取到 undefined。
  const idx: number = pinnedShownIndex(input.cycle, ids.length);
  const targetId: number = ids[idx];
  // 最后一条（最旧的那条）再点一次 → 循环回到最新。
  //
  // 判据要顺着"聊天列表越靠上越旧"来读：topVisibleId 是视口最上面那条的 id，
  // topVisibleId <= targetId 意思是"最上面那条比目标还旧（或就是它）"，
  // 也就是**目标位于视口顶部之下**——用户已经滚到它这里或更靠下的位置，
  // 这条置顶算过眼了，再点就该回到当前。
  //
  // 反之（最上面那条比目标新）说明目标还在视口上方、没看到过，照常跳过去。
  if (idx === ids.length - 1 && input.topVisibleId !== 0 &&
    input.topVisibleId <= targetId) {
    return tap(PINNED_LATEST, targetId, -1);
  }
  const loaded: number = loadedIndexOf(targetId);
  return loaded >= 0
    ? tap(PINNED_JUMP, targetId, loaded) : tap(PINNED_LOAD, targetId, -1);
}
