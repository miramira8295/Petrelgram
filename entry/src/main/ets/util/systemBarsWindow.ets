// 把 util/systemBarsHidden 的仲裁结果推给窗口。记账在那边（纯函数、有单测），
// 这里只负责取窗口、排队、调 setWindowSystemBarEnable。
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { requestSystemBarsHidden, systemBarsApplyFailed } from './systemBarsHidden';
import { logE } from './log';

// 窗口操作串行排队；序号保证只有最新的决定落地。
let applyTask: Promise<void> = Promise.resolve();
let applySeq: number = 0;

function barsFor(hidden: boolean): Array<'status' | 'navigation'> {
  return hidden ? [] : ['status', 'navigation'];
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

// 手上只有 context 的调用方（媒体查看器）用这个：自己取窗口、排队、只让最新的落地。
export function setSystemBarsHidden(context: common.UIAbilityContext, owner: string,
  hidden: boolean): void {
  const next: boolean | null = requestSystemBarsHidden(owner, hidden);
  if (next === null) {
    return;
  }
  const seq: number = ++applySeq;
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
}
