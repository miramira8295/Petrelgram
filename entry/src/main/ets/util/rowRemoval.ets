// 「这次发布是不是删了中间几行」——消息删除动画的判据（issue #149）。
//
// **为什么要挑得这么细。** 消息列表的发布路径（ChatPage.publishGroupsNow）是滚动
// 时的热路径，不能每次发布都套 animateTo：那等于给翻页、加载历史、缩略图落地
// 统统加上补间，而本项目的教训是动画会盖住真正的布局抖动。
//
// 只有一种发布该带动画：**行变少，且少掉的那几行前后都还有行留着**。
//   · 删消息 → 中间少掉一行，前后都有 ⇒ 动画（剩下的行平滑合拢）
//   · 往上翻页时丢掉窗口末尾的旧行 → 少掉的是**一头**的一段 ⇒ 不动画
//   · 行数不变或变多 ⇒ 不动画（连判据都不跑）
//
// 代价：删掉的正好是第一行或最后一行时不带动画。这是有意的保守——那两种
// 情况和窗口裁剪从 id 序列上看长得一模一样，分不开，宁可不动。

// prevIds / nextIds 是发布前后每一行的消息 id（行的身份）。
export function isInteriorRowRemoval(prevIds: number[], nextIds: number[]): boolean {
  if (nextIds.length >= prevIds.length || nextIds.length === 0) {
    return false;
  }
  const shorter: number = nextIds.length;
  let head: number = 0;
  while (head < shorter && prevIds[head] === nextIds[head]) {
    head++;
  }
  let tail: number = 0;
  while (tail < shorter - head &&
    prevIds[prevIds.length - 1 - tail] === nextIds[nextIds.length - 1 - tail]) {
    tail++;
  }
  // 前后都得有留下来的行，否则就是从一头砍掉一段（窗口裁剪）。
  if (head === 0 || tail === 0) {
    return false;
  }
  // 中间只减不增：新列表的中段必须是空的，否则是「换了一批」而不是「删掉」。
  return nextIds.length - head - tail === 0;
}
