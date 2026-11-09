import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE } from './log';

// 窗口亮度：全屏播放器左半屏竖拖调的就是它。
//
// 【为什么是窗口亮度而不是系统亮度】改系统亮度要 ohos.permission.MANAGE_AUDIO_CONFIG
// 那一类系统级权限，普通应用拿不到。setWindowBrightness 只作用于本应用窗口，
// 不需要任何权限，观感上和"调屏幕亮度"一致——这也是系统播放器的做法。
//
// 【-1 是"跟随系统"】**退出播放器必须还原**，否则整个应用会一直被压在用户
// 划到的那个亮度上，连回到会话列表都是暗的。调用方在 aboutToDisappear 里调
// restoreWindowBrightness()。
export const BRIGHTNESS_FOLLOW_SYSTEM: number = -1;

// 上一次真正下发的值。窗口 API 是异步的，而竖拖每帧都会算出一个新档位——
// 不去重的话一次滑动就是几十次跨进程调用。
let lastApplied: number = BRIGHTNESS_FOLLOW_SYSTEM;

function applyTo(ctx: common.UIAbilityContext, value: number): void {
  window.getLastWindow(ctx).then((win: window.Window): void => {
    win.setWindowBrightness(value).catch((e: BusinessError): void => {
      logE(`screenBrightness.setWindowBrightness(${value}) failed: ${e.message}`);
    });
  }).catch((e: BusinessError): void => {
    logE(`screenBrightness.getLastWindow failed: ${e.message}`);
  });
}

// level 取 0..1。变化小于 1/255 的不下发（那已经低于屏幕能分辨的档）。
export function applyWindowBrightness(ctx: common.UIAbilityContext, level: number): void {
  const next: number = Math.max(0, Math.min(1, level));
  if (lastApplied >= 0 && Math.abs(next - lastApplied) < 1 / 255) {
    return;
  }
  lastApplied = next;
  applyTo(ctx, next);
}

export function restoreWindowBrightness(ctx: common.UIAbilityContext): void {
  if (lastApplied === BRIGHTNESS_FOLLOW_SYSTEM) {
    return;
  }
  lastApplied = BRIGHTNESS_FOLLOW_SYSTEM;
  applyTo(ctx, BRIGHTNESS_FOLLOW_SYSTEM);
}

// 进播放器时的起手值。系统没给"当前窗口亮度"的读接口，而 -1（跟随系统）不是
// 一个能拿来做加减的数——所以第一次竖拖从中点起步，之后才用上一次的值。
// 这是有意的取舍：读不到就别装作读到了。
export const BRIGHTNESS_START_DEFAULT: number = 0.5;

export function currentBrightnessLevel(): number {
  return lastApplied >= 0 ? lastApplied : BRIGHTNESS_START_DEFAULT;
}
