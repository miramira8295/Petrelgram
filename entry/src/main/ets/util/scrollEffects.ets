// 滑动态：滑动期间把列表行上的隐式动画时长压成 0。
//
// 真机 trace（2026-08-26，PLA-AL10）：JSAnimation 在卡顿帧里占 17%，其中气泡上
// duration:90 那一支单独就有 390 次 / 207ms。滑动中这些动画既看不见也没意义。
//
// 动画门控**刻意不做成 @StorageProp**：这里只提供非订阅读取，滑动中新建的行
// 自然拿到 0，已经建好的行保持原值（它们本来就不在变）。玻璃材质不再读取这个
// 状态；滚动期间保持同一档位，避免开始/结束时批量卸载和恢复造成明暗闪变。

export const KEY_SCROLL_ACTIVE: string = 'chatScrollActive';

// Placeholder visibility follows the actual start/stop lifecycle, including
// inertia and page exit. The animation watchdog below is deliberately separate:
// a long drag must not bring album mini images/blur back after three seconds.
@ObservedV2
export class ScrollPlaceholderState {
  @Trace active: boolean = false;
}

export const scrollPlaceholderState: ScrollPlaceholderState = new ScrollPlaceholderState();

// 看门狗上限。onScrollStop 未必与 onScrollStart 配对（滑动中被程序化跳转打断），
// 标志卡在 true 的后果是此后所有气泡的隐式动画被永久压成 0。宁可提前过期——
// 提前过期只是把动画还原成改动前的样子，无害；卡住才是真故障。
// 同一个页面里 armFloatDateHide（ChatPage.ets:3555）用的是同一套办法。
const SCROLL_ACTIVE_MAX_MS: number = 3000;
let scrollWatchdog: number = -1;
let placeholderWatchdog: number = -1;
let placeholderLastMotionAt: number = 0;

function expireIdlePlaceholderScroll(): void {
  placeholderWatchdog = -1;
  const remaining = SCROLL_ACTIVE_MAX_MS - (Date.now() - placeholderLastMotionAt);
  if (remaining > 0) {
    placeholderWatchdog = setTimeout(expireIdlePlaceholderScroll, remaining);
  } else if (scrollPlaceholderState.active) {
    scrollPlaceholderState.active = false;
  }
}

// Called on actual movement only. Sustained movement only updates a timestamp;
// no per-frame observable writes/timers. Also handles movement resuming after
// an idle watchdog expiry without a second onScrollStart.
export function noteScrollPlaceholderMotion(): void {
  placeholderLastMotionAt = Date.now();
  if (!scrollPlaceholderState.active) {
    scrollPlaceholderState.active = true;
    placeholderWatchdog = setTimeout(expireIdlePlaceholderScroll, SCROLL_ACTIVE_MAX_MS);
  }
}

export function setScrollActive(active: boolean): void {
  if (scrollPlaceholderState.active !== active) {
    scrollPlaceholderState.active = active;
  }
  if (placeholderWatchdog !== -1) {
    clearTimeout(placeholderWatchdog);
    placeholderWatchdog = -1;
  }
  if (active) {
    noteScrollPlaceholderMotion();
    placeholderWatchdog = setTimeout(expireIdlePlaceholderScroll, SCROLL_ACTIVE_MAX_MS);
  }
  if (scrollWatchdog !== -1) {
    clearTimeout(scrollWatchdog);
    scrollWatchdog = -1;
  }
  AppStorage.setOrCreate(KEY_SCROLL_ACTIVE, active);
  if (active) {
    scrollWatchdog = setTimeout((): void => {
      scrollWatchdog = -1;
      AppStorage.setOrCreate(KEY_SCROLL_ACTIVE, false);
    }, SCROLL_ACTIVE_MAX_MS);
  }
}

export function scrollActiveNow(): boolean {
  return AppStorage.get<boolean>(KEY_SCROLL_ACTIVE) ?? false;
}

// 纯函数，便于单测：enabled 是各项设置与省电模式的合取结果。
export function animationDurationFor(enabled: boolean, scrolling: boolean, ms: number): number {
  return enabled && !scrolling ? ms : 0;
}

// 长期视觉效果（参数在 build 之后才被消费的动画，例如 iterations:-1 的循环
// 胶囊、行内链接药丸的按下过渡）的时长决策：不吃滑动门控——滑动中渲染的那一帧
// 会把时长固定成 0，而这类动画在那之后才播，门控它们只会让循环效果永久静止。
// 只受聊天特效开关、消息特效开关和省电模式约束。
//
// 注意：这个函数只决定「时长取多少」，不提供任何动画边界。节点上只要挂着常驻
// .animation()，普通数据更新照样会进入动画上下文并连带列表重测（2026-08-27 真机
// trace 已证实，属性链换位置也挡不住）。所以两支气泡的根节点现在完全不挂常驻
// 动画，不再调用本函数。
export function persistentAnimationDurationFor(
  chatEffectsEnabled: boolean, messageEffectsEnabled: boolean,
  powerSaving: boolean, ms: number): number {
  return chatEffectsEnabled && messageEffectsEnabled && !powerSaving ? ms : 0;
}
