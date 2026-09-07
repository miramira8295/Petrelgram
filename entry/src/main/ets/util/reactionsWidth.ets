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

// ── 反应条与时间戳同处一行 ────────────────────────────────────────────────
//
// 有反应时时间戳跟在反应条末尾（MessageBubble 里那个 Row({ space: 6 })）。
// 反应条自己是**定宽**的，Row 的 maxWidth 压不动它，于是反应条一旦顶到
// inlineMaxW，时间戳就被挤出气泡右边缘画到壁纸上——真机 2026-09-04：一条五个
// chip 的频道消息，「下午07:57」后两个字符跑到气泡外面去了。
//
// 修法是给反应条的上限**先扣掉时间戳要占的位**。扣完之后自然宽仍放得下就一切
// 照旧（绝大多数消息只有一两个 chip）；放不下就早一个 chip 换行，时间戳落在
// 最后一行右边，正好是官方的样子。

// timeOverlay 内部 Row({ space: 4 }) 的间距。
const TIME_INNER_GAP: number = 4;
// statusIcon 的 SymbolGlyph 是 12fp；已读那一枚叠在上面（margin-left -8），
// 不额外占位。
const TIME_STATUS_ICON_VP: number = 12;
// 反应条与时间戳之间那 6（Row({ space: 6 })）。
export const REACTIONS_TIME_GAP: number = 6;
// 扣到最后也要给反应条留下的宽度。低于这个数每个 chip 都会单独占一行，那比
// 时间戳溢出更难看。取一个 chip 的典型宽度（图标 15 + 两侧 padding + 计数）。
const REACTIONS_MIN_VP: number = 52;

// 时间戳挂件的宽度（vp）。三部分与 MessageBubble.timeOverlay 逐项对应：
// 「已编辑」标签（可选）、时刻文本、发送状态图标（仅自己发的）。
export function timeOverlayWidth(
  timeTextVp: number, editedTextVp: number, edited: boolean, outgoing: boolean
): number {
  let total: number = Math.max(0, timeTextVp);
  if (edited) {
    total += Math.max(0, editedTextVp) + TIME_INNER_GAP;
  }
  if (outgoing) {
    total += TIME_STATUS_ICON_VP + TIME_INNER_GAP;
  }
  return Math.ceil(total);
}

// 反应条在「和时间戳同行」时的宽度上限。
export function reactionsRowMaxWidth(inlineMaxVp: number, timeVp: number): number {
  const left: number = inlineMaxVp - timeVp - REACTIONS_TIME_GAP;
  // 气泡本来就比一个 chip 还窄时不再往下扣：那种宽度下换不换行都一样难看，
  // 而扣成负数会让 Flex 拿到一个非法宽度。
  return Math.max(Math.min(inlineMaxVp, REACTIONS_MIN_VP), left);
}
