// 译文到货时怎么保住阅读位置。判据在这里，位移计算复用 util/anchorRestore。
//
// 【问题】译文让气泡变高。列表的锚定方式由 util/stackFromEnd 决定：
//
//   · 已到实时尾部（底部锚定）→ 行变高时上方内容自然上移、**底部钉住**，
//     正是想要的；
//   · 停在未读/上次阅读位置（顶部锚定，hasMoreNewer=true）→ 行变高是把**它
//     下面的**内容往下推。视口上方那些行一变高，用户正在看的那条就往下漂。
//
// `maintainVisibleContentPosition` 救不了：SDK 原文说的是"数据**插入或删除**时
// 可见内容位置不变"，**行在视口内变高不在它的语义里**（用户 2026-09-09 实测：
// 「底部好像没问题，但是顶部确实定不住」）。
//
// 【为什么顶部锚定时不做动画】补偿要等布局落定才量得到位移。如果译文是用
// 220ms 的 animateTo 长出来的，那 220ms 里内容一直在往下漂，补偿只能在结束时
// 才把它拽回来——先漂后弹，比原来的硬切更难看。所以两种情形各用各的办法：
//
//   底部锚定 → 动画（本来就没有锚点问题，补间纯赚）
//   顶部锚定 → 即时应用 + 下一帧抵消（位移在同一帧被吃掉，看不见）

// 哪些消息这一次要「不做动画、直接落」。
//
// 【为什么判据不能是 atBottom】第一版按"贴不贴底"决定动不动画：贴底才动。
// 结果就是**只有第一屏有淡入淡出，往上翻过之后全没了**（用户 2026-09-09 实测）
// ——往上翻就不贴底了，我把动画整个关掉了。判据太粗。
//
// 真正会把阅读位置顶下去的**只有视口上方的行**（顶部锚定下，行变高推的是它
// 下面的内容）。而那些行本来就看不见，动画对它们毫无意义。视口内和视口下方
// 的行怎么动都不会移动首个可见行，可以放心动画。
//
// 所以改成按行点名：页面/驱动那边知道行号和可见区间，落地之前把"在视口上方"
// 的那几条点出来，行外壳照着办。没被点名的一律动画。
const instantIds: Set<number> = new Set<number>();

export function markTranslationInstant(messageId: number): void {
  instantIds.add(messageId);
}

// 查一次就清掉：这个标记只对**这一次**落地有效，留着会让同一条消息下次
// 换语言时也不动画。
export function takeTranslationInstant(messageId: number): boolean {
  if (!instantIds.has(messageId)) {
    return false;
  }
  instantIds.delete(messageId);
  return true;
}

export function clearTranslationInstant(): void {
  instantIds.clear();
}

// 该不该为这次译文到货保锚点。
// 底部锚定不需要（列表自己就是对的）；行号不新鲜时不做（拿旧行号去量会量错行，
// 与 anchorIndexFresh 的既有守卫同一理由）。
export function shouldHoldTranslationAnchor(atBottom: boolean, indexFresh: boolean): boolean {
  return !atBottom && indexFresh;
}

// 从「译文到货」到「量位置补偿」之间等多久。
//
// 要等布局把新高度排完，又不能久到用户已经看见位移。一次可见范围里常常连着
// 落好几条译文，这段等待同时起合并的作用：每来一条就把它往后推一次，最后统一
// 补一次，而不是每条都补。
export const TRANSLATION_ANCHOR_SETTLE_MS: number = 48;
