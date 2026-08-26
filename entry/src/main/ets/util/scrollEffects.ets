// 滑动态：滑动期间把列表行上的隐式动画时长压成 0。
//
// 真机 trace（2026-08-26，PLA-AL10）：JSAnimation 在卡顿帧里占 17%，其中气泡上
// duration:90 那一支单独就有 390 次 / 207ms。滑动中这些动画既看不见也没意义。
//
// **刻意不做成 @StorageProp**：订阅会让 onScrollStart 那一刻所有可见气泡失效重建，
// 为了省动画反而制造一次全树重建。这里只提供非订阅的读取，在 build 期间取值——
// 滑动中新建的行自然拿到 0，已经建好的行保持原值（它们本来就不在变）。
// 同一套办法见 util/overlayMaterial.ets 读厚度/光感档位。

export const KEY_SCROLL_ACTIVE: string = 'chatScrollActive';

// 看门狗上限。onScrollStop 未必与 onScrollStart 配对（滑动中被程序化跳转打断），
// 标志卡在 true 的后果是此后所有气泡的隐式动画被永久压成 0。宁可提前过期——
// 提前过期只是把动画还原成改动前的样子，无害；卡住才是真故障。
// 同一个页面里 armFloatDateHide（ChatPage.ets:3555）用的是同一套办法。
const SCROLL_ACTIVE_MAX_MS: number = 3000;
let scrollWatchdog: number = -1;

export function setScrollActive(active: boolean): void {
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
