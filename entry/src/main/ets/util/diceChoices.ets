// 从 ChatPage.ets 搬来（DiceChoice / DICE_CHOICES 原样）。diceSheet @Builder 仍留在页面里。

export interface DiceChoice {
  emoji: string;
  label: ResourceStr;
}

// 六个骰子表情。原先是 showActionMenu 的按钮上限刚好装得下，现在是 3×2 的格子。
export const DICE_CHOICES: DiceChoice[] = [
  { emoji: '🎲', label: $r('app.string.cp_dice_die') },
  { emoji: '🎯', label: $r('app.string.cp_dice_darts') },
  { emoji: '🏀', label: $r('app.string.cp_dice_basketball') },
  { emoji: '⚽', label: $r('app.string.cp_dice_football') },
  { emoji: '🎳', label: $r('app.string.cp_dice_bowling') },
  { emoji: '🎰', label: $r('app.string.cp_dice_slots') }
];
