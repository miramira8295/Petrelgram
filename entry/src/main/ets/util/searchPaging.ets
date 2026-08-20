// 聊天内搜索的翻页决策。
//
// 结果按"新 → 旧"排列，∧ 往更旧走（下标 +1），∨ 往更新走（下标 -1）。窗口
// 一次取 50 条，翻到尽头时要不要再取一页，取决于已加载数和服务端给的总数。
//
// 抽成纯函数是因为这几个边界最容易错：下标越界、总数为 0、已加载等于总数、
// 空结果集。它们在页面里是三个 if 混在异步回调之间，单独测才看得清。

export const SEARCH_STAY: string = 'stay';       // 什么都不做
export const SEARCH_JUMP: string = 'jump';       // 跳到已加载的某一条
export const SEARCH_FETCH: string = 'fetch';     // 先取下一页，到货后跳

export interface SearchStep {
  action: string;
  // SEARCH_JUMP 时是目标下标；SEARCH_FETCH 时是到货后要跳的下标。
  index: number;
  // SEARCH_FETCH 时是"从这条消息往更旧翻"的锚点，其余为 0。
  fromMessageId: number;
}

function stay(): SearchStep {
  return { action: SEARCH_STAY, index: 0, fromMessageId: 0 };
}

// ∧：更旧的那一条。
export function stepOlder(
  loaded: number[], currentIndex: number, total: number
): SearchStep {
  const next: number = currentIndex + 1;
  if (next < loaded.length) {
    return { action: SEARCH_JUMP, index: next, fromMessageId: 0 };
  }
  // 已加载的到头了：还有没取回来的才继续翻页。loaded 为空时无锚点可用。
  if (loaded.length > 0 && loaded.length < total) {
    return { action: SEARCH_FETCH, index: next, fromMessageId: loaded[loaded.length - 1] };
  }
  return stay();
}

// ∨：更新的那一条。永远不需要翻页——更新的结果都在已加载窗口里。
export function stepNewer(currentIndex: number): SearchStep {
  return currentIndex > 0
    ? { action: SEARCH_JUMP, index: currentIndex - 1, fromMessageId: 0 }
    : stay();
}

// 计数显示："第几条 / 共几条"。结果按新→旧排，所以下标 0 是最新的那条，
// 显示成第 total 条。
export function searchCounterText(currentIndex: number, total: number): string {
  if (total <= 0) {
    return '';
  }
  return `${total - currentIndex} / ${total}`;
}

// 底部那一条左边显示什么。三种情形，返回"哪一类"而不是文案本身——文案里有
// Resource，把它留在组件侧，这里只做判断，才测得动。
export const SEARCH_LABEL_COUNTER: string = 'counter';   // 第几条 / 共几条
export const SEARCH_LABEL_NONE: string = 'none';         // 查过了，没有结果
export const SEARCH_LABEL_HINT: string = 'hint';         // 还没查，显示提示语

// 注意"查过了没结果"和"还没开始查"要分开：前者显示空白（提示语再挂着会像
// 没反应过），后者才显示提示语。判据是"用户敲进了非空关键词而总数为 0"。
export function searchLabelKind(
  loadedCount: number, total: number, query: string
): string {
  if (loadedCount > 0) {
    return SEARCH_LABEL_COUNTER;
  }
  return (total === 0 && query.trim() !== '') ? SEARCH_LABEL_NONE : SEARCH_LABEL_HINT;
}

// ∧ / ∨ 两个箭头亮不亮。必须和 stepOlder / stepNewer 的判断一致——按钮看着
// 能点、点下去没反应是最难查的那类 bug，所以单测里用穷举把两者钉在一起。
//
// 页面里原来写的是 `searchIdx + 1 < searchTotal`，少了"已加载数为 0 就没有
// 翻页锚点"这一支：total 大于 0 而一条都还没到货时，那个式子说亮，stepOlder
// 却只会返回 STAY。眼下不出问题只是因为箭头整体挂在 `results.length > 0` 里、
// 那种状态下根本没渲染——换句话说，正确性寄存在调用方的一个 if 上。
// 这里按 stepOlder 的真实条件写全，就不必再依赖那个 if。
export function canStepOlder(
  loadedCount: number, currentIndex: number, total: number
): boolean {
  return currentIndex + 1 < loadedCount || (loadedCount > 0 && loadedCount < total);
}

export function canStepNewer(currentIndex: number): boolean {
  return currentIndex > 0;
}

// 从全局搜索点某条消息进来时，那一条就是"锚点"：用户已经指明了要看哪一条。
//
// 进来之后还会用同一串关键词跑一次会话内搜索（searchChatMessages），目的只是
// 把 ∧/∨ 的结果列表填上。但两边的匹配口径并不一致：issue #80 里，全局搜索命中
// 的是「opengram，还有最近那个」，会话内搜索用同一串词只回了另一条同样含
// "opengram"、"还有" 的消息。原来的写法是 indexOf 找不到锚点就跳到 results[0]，
// 于是刚落对的位置被甩开，用户眼睁睁看着页面自己滑到别处。
//
// 锚点是用户的选择，不能被这次搜索推翻。结果按 id 降序（新→旧）排，把锚点按
// 序插进去即可：∧/∨ 相对它仍然是"更旧/更新"，翻页锚点也仍然是最后一条。
export interface AnchorMerge {
  results: number[];
  // 锚点在 results 里的下标；没有锚点时为 -1。
  index: number;
  // 是否是这次插进去的（调用方据此决定要不要把总数 +1）。
  inserted: boolean;
}

export function mergeAnchorHit(ids: number[], anchorId: number): AnchorMerge {
  if (anchorId <= 0) {
    return { results: ids, index: -1, inserted: false };
  }
  const at: number = ids.indexOf(anchorId);
  if (at >= 0) {
    return { results: ids, index: at, inserted: false };
  }
  let pos: number = ids.length;
  for (let i = 0; i < ids.length; i++) {
    if (ids[i] < anchorId) {
      pos = i;
      break;
    }
  }
  return {
    results: [...ids.slice(0, pos), anchorId, ...ids.slice(pos)],
    index: pos,
    inserted: true
  };
}
