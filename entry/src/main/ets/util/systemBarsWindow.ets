// 把 util/systemBarsHidden 的仲裁结果推给窗口。记账在那边（纯函数、有单测），
// 这里只负责取窗口、排队、调 setWindowSystemBarEnable。
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  isSystemBarsHiddenApplied, releaseAllViewerSystemBars, requestSystemBarsHidden,
  systemBarsApplyFailed
} from './systemBarsHidden';
import { logE } from './log';

// 窗口操作串行排队；序号保证只有最新的决定落地。
let applyTask: Promise<void> = Promise.resolve();
let applySeq: number = 0;
let mainWinRef: window.Window | null = null;
let systemTopAvoidVp: number = 0;
let expectedTopSafeVp: number = 0;
let topAvoidWaiters: Array<() => void> = [];

const TOP_AVOID_RESTORE_TIMEOUT_MS: number = 90;

function barsFor(hidden: boolean): Array<'status' | 'navigation'> {
  return hidden ? [] : ['status', 'navigation'];
}

export function setSystemBarsMainWindow(win: window.Window | null): void {
  mainWinRef = win;
}

export function noteSystemTopAvoidHeight(topVp: number, seededSafeTopVp?: number): void {
  systemTopAvoidVp = topVp;
  if (seededSafeTopVp !== undefined && seededSafeTopVp > 0) {
    expectedTopSafeVp = seededSafeTopVp;
  } else if (topVp > 0) {
    expectedTopSafeVp = topVp;
  }
  if (topVp > 0 && topAvoidWaiters.length > 0) {
    const waiters: Array<() => void> = topAvoidWaiters;
    topAvoidWaiters = [];
    for (const resolve of waiters) {
      resolve();
    }
  }
}

export function isSystemTopBarReady(): boolean {
  return !isSystemBarsHiddenApplied() && (expectedTopSafeVp <= 0 || systemTopAvoidVp > 0);
}

function waitForSystemTopAvoidReady(): Promise<void> {
  if (expectedTopSafeVp <= 0 || systemTopAvoidVp > 0) {
    return Promise.resolve();
  }
  return new Promise<void>((resolve: () => void): void => {
    let settled: boolean = false;
    const finish = (): void => {
      if (settled) {
        return;
      }
      settled = true;
      // 让同一轮 avoidAreaChange 先在 ArkUI SafeAreaManager 落定，再放开标题栏显隐。
      setTimeout((): void => { resolve(); }, 0);
    };
    const timer: number = setTimeout((): void => {
      finish();
    }, TOP_AVOID_RESTORE_TIMEOUT_MS);
    topAvoidWaiters.push((): void => {
      clearTimeout(timer);
      finish();
    });
  });
}

function enqueueWindowSystemBars(context: common.UIAbilityContext | null, next: boolean): Promise<void> {
  const seq: number = ++applySeq;
  const cachedWin: window.Window | null = mainWinRef;
  if (cachedWin !== null) {
    applyTask = applyTask.then((): Promise<void> => {
      if (seq !== applySeq) {
        return Promise.resolve();
      }
      return cachedWin.setWindowSystemBarEnable(barsFor(next));
    }).catch((caught: Error): void => {
      if (seq === applySeq) {
        systemBarsApplyFailed(next);
      }
      logE(`systemBarsWindow set failed: ${caught.message}`);
    });
    return applyTask;
  }
  if (context === null) {
    return Promise.resolve();
  }
  applyTask = applyTask.then((): Promise<void> => {
    if (seq !== applySeq) {
      return Promise.resolve();
    }
    return window.getLastWindow(context).then((win: window.Window): Promise<void> =>
      win.setWindowSystemBarEnable(barsFor(next)));
  }).catch((caught: Error): void => {
    if (seq === applySeq) {
      systemBarsApplyFailed(next);
    }
    logE(`systemBarsWindow set failed: ${caught.message}`);
  });
  return applyTask;
}

// 已经拿到窗口的调用方（直播全屏在同一串窗口操作里还要转屏）用这个。
export function applySystemBarsHiddenOn(win: window.Window, owner: string,
  hidden: boolean): Promise<void> {
  const next: boolean | null = requestSystemBarsHidden(owner, hidden);
  if (next === null) {
    return Promise.resolve();
  }
  return win.setWindowSystemBarEnable(barsFor(next)).catch((caught: Error): void => {
    systemBarsApplyFailed(next);
    logE(`systemBarsWindow apply failed: ${caught.message}`);
  });
}

// 手上只有 context 的调用方（媒体查看器）用这个：优先直接走已缓存的主窗口，只让最新的落地。
export function setSystemBarsHidden(context: common.UIAbilityContext, owner: string,
  hidden: boolean): void {
  const next: boolean | null = requestSystemBarsHidden(owner, hidden);
  if (next === null) {
    return;
  }
  enqueueWindowSystemBars(context, next);
}

// 媒体查看器开始退场时立即调用：在退场第 0 帧恢复系统状态栏与导航条，不等 300ms 后
// aboutToDisappear，并等待 TYPE_SYSTEM 安全区恢复后再兑现，防止 HdsNavDestination
// 标题栏在 TYPE_SYSTEM=0 期间先画在 y=0 再跳回状态栏下方。
export function restoreViewerSystemBars(context: common.UIAbilityContext | null = null): Promise<void> {
  const next: boolean | null = releaseAllViewerSystemBars();
  if (next !== null) {
    return enqueueWindowSystemBars(context, next).then((): Promise<void> => waitForSystemTopAvoidReady());
  }
  return waitForSystemTopAvoidReady();
}
