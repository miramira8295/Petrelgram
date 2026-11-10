// 全局 Toast 的唯一出口。
//
// 为什么需要它：`promptAction.showToast()` 这个全局 API 从 API 18 起废弃，
// 官方迁移路径是 `UIContext.getPromptAction().showToast()`。本项目有 400+
// 处 toast 调用，散在 util 与页面里，其中大多数不在组件作用域内，拿不到
// `this.getUIContext()`——所以在这里登记一次 UIContext，调用方只保留
// `showToast(message, duration)` 这一种写法。
//
// 登记点：EntryAbility.onWindowStageCreate 拿到主窗口 UIContext 后调
// bindToastContext 一次。窗口就绪之前不会有 toast（那时页面还没建）。
import { UIContext, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { currentUIContext } from './uiContext';

const DOMAIN: number = 0x0000;
const TAG: string = 'Toast';


export function showToast(message: ResourceStr, duration: number = 2000): void {
  const ui: UIContext | null = currentUIContext();
  if (ui === null) {
    hilog.warn(DOMAIN, TAG, 'showToast before UIContext bound: %{public}s', stringify(message));
    return;
  }
  ui.getPromptAction().showToast({ message: message, duration: duration });
}

// 少数调用点传的是整个 options 对象（含 alignment/offset 等字段），单独留一个入口。
export function showToastOptions(options: promptAction.ShowToastOptions): void {
  const ui: UIContext | null = currentUIContext();
  if (ui === null) {
    hilog.warn(DOMAIN, TAG, 'showToastOptions before UIContext bound');
    return;
  }
  ui.getPromptAction().showToast(options);
}

function stringify(message: ResourceStr): string {
  return typeof message === 'string' ? message : 'resource';
}
