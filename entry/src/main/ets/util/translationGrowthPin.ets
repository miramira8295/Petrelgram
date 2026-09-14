import { bottomFollowShouldApply, bottomFollowShouldSchedule } from './bottomFollow';

// 译文 / 「翻译中」让气泡变高时，停在实时末尾就把底部钉住——气泡向上长。
//
// 【问题】可滚动的消息列表不开 stackFromEnd（见 util/stackFromEnd），行在视口里
// 变高推的是它**下面**的内容。停在最底下时，新长出来的那截直接落到输入栏后面，
// 得手滑才看得见（用户 2026-09-14：「消息已经在最底下的时候，翻译会把聊天内容
// 往下增长。在最底下的时候，气泡应该向上长」）。
//
// 【为什么现有的贴底跟随接不住】
//   · 译文落地：进 store 会发一份快照，页面 applyInitialOrFollowLanding 确实排了
//     scheduleBottomAfterLayout（+32ms）。可行外壳要先淡出 110ms 才换内容、再用
//     260ms 补间把高度长出来（ReusableMessageBubble.applyPresentation）——跟随
//     点火时内容还没换，什么都没贴上；真正变高的那 260ms 没人跟。
//   · 「翻译中 / 翻译失败」：走 translationChannel 旁路直达气泡，连快照都不发。
//
// 【做法】在变高发生的**那一次刷新**里 scrollEdge(Bottom)：
//   · 译文落地：在外壳淡入的 animateTo 闭包里、换内容之后调。行高补间和列表
//     跳到末尾在同一次布局里算出、按同一条曲线插值——每一帧行往上移多少、就
//     长高多少，底边一直钉着，看起来就是向上长。
//   · 瞬时态出现/消失：订阅回调里赋值之后调。同一帧布局，无动画。
// 钉不钉由页面判（translationGrowthPinWanted），这里只做分发。
//
// 一键回退：TRANSLATION_GROWTH_PIN_ENABLED 改 false，行为回到修之前。
export const TRANSLATION_GROWTH_PIN_ENABLED: boolean = true;

export type TranslationGrowthPin = (chatId: number) => void;

// 同一时刻可能挂着不止一个会话页（会话页 + 它的评论页），页面也可能换过会话，
// 所以不按会话建表：每页收到后自己比 chatId、自己判可见。
let pins: TranslationGrowthPin[] = [];

export function registerTranslationGrowthPin(pin: TranslationGrowthPin): () => void {
  pins = pins.concat([pin]);
  return (): void => {
    pins = pins.filter((p: TranslationGrowthPin): boolean => p !== pin);
  };
}

// 行在「因翻译变高」的那一次刷新里调。
export function pinForTranslationGrowth(chatId: number): void {
  if (!TRANSLATION_GROWTH_PIN_ENABLED) {
    return;
  }
  const current: TranslationGrowthPin[] = pins;
  for (let i = 0; i < current.length; i++) {
    current[i](chatId);
  }
}

export interface TranslationGrowthPinInput {
  pageVisible: boolean;
  didInitialScroll: boolean; // 首屏落点还没定：那时归落点逻辑管
  atBottom: boolean;
  followPending: boolean;    // 贴底跟随在途：视为仍在底（util/bottomFollow 规则 2）
  stayAtUnread: boolean;     // 落在未读、被锁住不贴底
  touchActive: boolean;
  scrollActive: boolean;
  viewerOpen: boolean;
  hasMoreNewer: boolean;     // 窗口没到实时尾部：那是已加载窗口的底，不是真尾部
}

// 与页面「原地变高时贴住底」（applyInitialOrFollowLanding 的 L1252 分支）同一组
// 条件，外加：页面不可见不钉；手指按着 / 列表在滚不钉（用户已经接管）。
export function translationGrowthPinWanted(input: TranslationGrowthPinInput): boolean {
  if (!input.pageVisible || !input.didInitialScroll || input.stayAtUnread) {
    return false;
  }
  if (!bottomFollowShouldSchedule(input.atBottom, input.followPending, input.viewerOpen)) {
    return false;
  }
  return bottomFollowShouldApply({
    superseded: false,
    touchActive: input.touchActive,
    scrollActive: input.scrollActive,
    viewerOpen: input.viewerOpen,
    hasMoreNewer: input.hasMoreNewer
  });
}
