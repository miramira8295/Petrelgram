import { display, window } from '@kit.ArkUI';
import { allowsRotationForDisplay } from './layoutBreakpoint';
import { logE } from './log';

// 应用的默认旋转策略（2026-09-27 用户定：手机锁竖屏，平板 / 折叠屏展开态可转）。
//
// 判据在 layoutBreakpoint.allowsRotationForDisplay（物理屏短边 ≥ 600vp），这里只负责
// 把结论推给主窗口，并把「默认该是什么」记下来：查看器 / 直播全屏退出时要回到的是
// 这个默认值，不能写死 PORTRAIT——那样平板看完一个视频整个应用就被锁成竖屏。
//
// 大屏用 AUTO_ROTATION_UNSPECIFIED：跟随传感器，受控制中心旋转锁定开关约束，可转
// 方向由系统按设备形态判定（官方《窗口旋转》推荐的单一策略）。
// 折叠屏开合会换屏幕，EntryAbility 监听 foldDisplayModeChange 再调一次 apply。

let defaultOrientation: window.Orientation = window.Orientation.PORTRAIT;
// 查看器 / 直播全屏临时接管方向期间，开合屏不去抢它；退出时它会回到默认值。
let overrideActive: boolean = false;

function computeDefault(): window.Orientation {
  try {
    const disp: display.Display = display.getDefaultDisplaySync();
    return allowsRotationForDisplay(disp.width, disp.height, disp.densityPixels)
      ? window.Orientation.AUTO_ROTATION_UNSPECIFIED
      : window.Orientation.PORTRAIT;
  } catch (e) {
    logE(`appOrientation: getDefaultDisplaySync failed: ${(e as Error).message}`);
    return window.Orientation.PORTRAIT;
  }
}

export function defaultAppOrientation(): window.Orientation {
  return defaultOrientation;
}

// 临时接管方向的一方（查看器横屏、直播全屏）进出时调，true = 接管中。
export function setOrientationOverride(active: boolean): void {
  overrideActive = active;
}

// 重新按当前屏幕算默认值，并在没人接管时推给窗口。
export function applyDefaultOrientation(win: window.Window): void {
  defaultOrientation = computeDefault();
  if (overrideActive) {
    return;
  }
  win.setPreferredOrientation(defaultOrientation).catch((e: Error): void => {
    logE(`appOrientation: setPreferredOrientation failed: ${e.message}`);
  });
}
