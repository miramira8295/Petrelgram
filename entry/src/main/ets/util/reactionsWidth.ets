// 反应条（气泡底下那排 👍 3 · ❤️ 1 的 chip）的宽度。
//
// **为什么要自己算。** chip 排在 Flex({ wrap }) 里，而 Flex 开了 wrap 就必须先
// 知道自己多宽才能决定在哪换行，于是它永远按父容器的最大宽度来测量——一个 👍
// 就能把一条"好的"的气泡顶到最大内容宽（issue #100）。上一版给它
// alignSelf(ItemAlign.Start)，那只管对齐不管测量，1.4.0 里用户报仍然如此。
// 给 Flex 一个明确宽度，wrap 才有意义：一行放不下时正好等于上限。
//
// 数字必须和 MessageBubble.reactionsRow 里 chip 的样式逐个对应，改一处要改两处：
//   padding({ left: 9, right: 9 })  →  CHIP_PAD_H
//   Row({ space: 4 })               →  CHIP_GAP
//   margin({ right: 4 })            →  CHIP_MARGIN_R
//   图标 15×15（自定义表情位图或占位）→ CHIP_ICON_VP；unicode 表情是 Text，要测
export const CHIP_PAD_H: number = 9;
export const CHIP_GAP: number = 4;
export const CHIP_MARGIN_R: number = 4;
export const CHIP_ICON_VP: number = 15;
// 测量与真实排版之间留一点余量：少算 1vp 最后一个 chip 就会掉到下一行，多算
// 1vp 只是气泡右边多一根头发丝。
const SLACK_VP: number = 2;

// 单个 chip 的宽度（vp）。iconVp 是图标/表情的宽，countVp 是计数文本的宽。
export function reactionChipWidth(iconVp: number, countVp: number): number {
  return CHIP_PAD_H + iconVp + CHIP_GAP + countVp + CHIP_PAD_H + CHIP_MARGIN_R;
}

// 整条反应条该给 Flex 的宽度：所有 chip 一行排开的自然宽，封顶 maxVp。
// 超过上限就交给 wrap 换行，那时上限正是它该有的宽。
export function reactionsRowWidth(chipWidthsVp: number[], maxVp: number): number {
  let total: number = 0;
  for (const w of chipWidthsVp) {
    total += w;
  }
  if (total <= 0) {
    return 0;
  }
  return Math.min(maxVp, Math.ceil(total) + SLACK_VP);
}
