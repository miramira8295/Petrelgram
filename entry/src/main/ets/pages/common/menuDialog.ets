import { promptAction, UIContext } from '@kit.ArkUI';
import { MENU_DISMISS_MS } from '../../util/chatPageTuning';
import { logI } from '../../util/log';

// 在 bindContextMenu 的菜单项 onClick 里弹确认框。
//
// 【为什么不能直接调全局 promptAction.showDialog】菜单是独立子窗口，收起过程中
// 弹出的对话框没有可依附的 UI 上下文：Promise 既不 resolve 也不 reject，界面上
// 什么都不发生——用户看到的是「点了删除，什么都没发生，东西也没删掉」。
// 首页会话行踩过一次（见 pages/chatlist/ChatRow.showConfirm 的注释），联系人
// 删除（ContactsPage）与通话记录删除（CallsPage）是同一个坑的另外两处。
//
// 两处修正，与会话行一致：
//   1. 用 UIContext 作用域的 promptAction，而不是全局那个；
//   2. 延后到菜单收起动画之后（MENU_DISMISS_MS）再弹。
//
// onResult 只在用户点了按钮时回调；点遮罩关掉走 catch，只记日志。
export function showMenuDialog(ui: UIContext, options: promptAction.ShowDialogOptions,
  what: string, onResult: (index: number) => void): void {
  const prompt = ui.getPromptAction();
  setTimeout((): void => {
    prompt.showDialog(options).then((result: promptAction.ShowDialogSuccessResponse): void => {
      onResult(result.index);
    }).catch((e: Object): void => {
      logI(`menuDialog.${what} dismissed: ${JSON.stringify(e)}`);
    });
  }, MENU_DISMISS_MS);
}
