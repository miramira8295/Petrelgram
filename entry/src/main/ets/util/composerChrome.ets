// 输入区的几个小判断：占位文字、机器人键盘可见性、底部留白。
//
// 都很短，但每一条都有过实测教训，写在各自的注释里。抽出来是为了让那些教训
// 有测试守着，而不是只活在注释里——注释拦不住下一次"顺手简化"。

import { str } from './strings';

// 输入区底部让出多少高度。
//
// 抽屉打开等同于键盘起来：底部安全区已经被抽屉占住了，输入框再留一条就会
// 浮得离抽屉老远。
//
// 不能只看键盘高度——自定义键盘（抽屉）的高度系统**不算作键盘高度**，诊断
// 日志里 keyboardH 全程为 0，只判断它的话抽屉打开时会走到 else 分支。
export const COMPOSER_GAP_TIGHT: number = 6;
export const COMPOSER_GAP_MIN: number = 8;

// 悬浮导航栏（MainScreen 的 HdsTabsFloatingModifier）贴底的距离：
// max(DOCK_GAP=6, round(bottomSafe * 0.85))。输入栏要和它落在同一条基线上，
// 否则收起底栏时输入栏会比导航栏高出一截。
//
// 0.7 → 0.85 → 0.95（2026-11-18）：用户对照畅连，觉得输入栏和悬浮导航栏都还偏低。
// 0.7 是当年「半个 bottomSafe 太低、整条 bottomSafe 又太远」之间的折中。0.85 之后
// 用 dumpLayout 量过真机（1320×2848，bottomSafe=32vp）：畅连聊天页输入胶囊下沿
// y=2754，我们输入胶囊下沿 y=2764，还低 10px(≈3.3vp)；0.95 → gap 30vp=90px，输入
// 胶囊下沿落到 y≈2755，与畅连基本重合。**两处必须同步改**：MainScreen 里四处
// Math.max(DOCK_GAP, Math.round(this.bottomSafe * 0.95)) 是同一个数的另一份写法。
export const COMPOSER_DOCK_GAP_RATIO: number = 0.95;

export function composerDockBottomGap(bottomSafe: number): number {
  return Math.max(COMPOSER_GAP_MIN, Math.round(bottomSafe * COMPOSER_DOCK_GAP_RATIO));
}

export function composerBottomGap(
  keyboardHeight: number, bottomPanelOpen: boolean, bottomSafe: number
): number {
  if (keyboardHeight > 0 || bottomPanelOpen) {
    return COMPOSER_GAP_TIGHT;
  }
  return Math.max(COMPOSER_GAP_MIN, bottomSafe);
}

// 机器人键盘这会儿露不露脸。三个条件缺一不可：有发言权、确实收到了键盘、
// 用户没把它收起来。
export function replyKeyboardVisible(
  membershipState: string, hasReplyKeyboard: boolean, collapsed: boolean
): boolean {
  return membershipState === 'writable' && hasReplyKeyboard && !collapsed;
}

// 输入框里的灰字。优先级从高到低：
//   1. 对方正在输入——借用占位文字来显示，不额外占地方，也永远盖不住消息；
//   2. 机器人键盘自带的提示语（有些机器人靠它说明该填什么）；
//   3. 默认的"消息"。
// 第 2 档要求键盘此刻确实可见：收起状态下还显示它的提示语会让人以为键盘还在。
export function composerPlaceholder(
  typingLabel: string, replyKeyboardVisibleNow: boolean, replyKeyboardPlaceholder: string
): string {
  if (typingLabel !== '') {
    return typingLabel;
  }
  if (replyKeyboardVisibleNow && replyKeyboardPlaceholder.trim() !== '') {
    return replyKeyboardPlaceholder;
  }
  return str('cp_message_placeholder');
}
