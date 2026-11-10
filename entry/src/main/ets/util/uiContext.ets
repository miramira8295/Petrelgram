// 全局 UIContext 的唯一登记点。
//
// 从 API 18 起，`promptAction.*`、`router.*`、`animateTo()`、`getContext()`、
// `px2vp/vp2px` 这批"全局"接口全部改为 UIContext 作用域版本。组件里直接
// `this.getUIContext()` 即可；但 util/services 里的调用没有 `this`，所以由
// EntryAbility 在窗口就绪时登记一次，工具函数从 here 取。
//
// 约定：**组件内不要用这里**，组件内用 `this.getUIContext()`——多实例窗口
// （分栏、子窗口）时全局登记的那个不一定是对的那个。
import { display, promptAction, router, UIContext } from '@kit.ArkUI';

let uiContext: UIContext | null = null;

export function bindUIContext(context: UIContext): void {
  uiContext = context;
}

export function currentUIContext(): UIContext | null {
  return uiContext;
}

// vp/px 换算：拿到 UIContext 就用它（官方口径），否则退回显示密度算一次。
// 只在 util 层用；组件里请用 this.getUIContext().vp2px(...)。
export function vp2px(vp: number): number {
  const ui: UIContext | null = uiContext;
  if (ui !== null) {
    return ui.vp2px(vp);
  }
  return vp * display.getDefaultDisplaySync().densityPixels;
}

export function px2vp(px: number): number {
  const ui: UIContext | null = uiContext;
  if (ui !== null) {
    return ui.px2vp(px);
  }
  return px / display.getDefaultDisplaySync().densityPixels;
}

// 页面跳转的 util 入口。没有 UIContext 时退化为 no-op（这些调用都在页面建成之后，
// 正常路径拿得到上下文；拿不到说明还没有窗口，跳转本身也无意义）。
export function pushUrl(options: router.RouterOptions): Promise<void> {
  const ui: UIContext | null = uiContext;
  if (ui === null) {
    return Promise.resolve();
  }
  return ui.getRouter().pushUrl(options);
}

export function back(): void {
  const ui: UIContext | null = uiContext;
  if (ui !== null) {
    ui.getRouter().back();
  }
}

// util 层的对话框入口（同样在拿不到 UIContext 时 no-op）。
export function showDialog(options: promptAction.ShowDialogOptions): Promise<promptAction.ShowDialogSuccessResponse> {
  const ui: UIContext | null = uiContext;
  if (ui === null) {
    return Promise.reject(new Error('no UIContext'));
  }
  return ui.getPromptAction().showDialog(options);
}

export function showActionMenu(options: promptAction.ActionMenuOptions): Promise<promptAction.ActionMenuSuccessResponse> {
  const ui: UIContext | null = uiContext;
  if (ui === null) {
    return Promise.reject(new Error('no UIContext'));
  }
  return ui.getPromptAction().showActionMenu(options);
}

// 关掉当前上下文菜单（ContextMenu.close 已废弃，改用 UIContext 的控制器）。
export function closeContextMenu(): void {
  const ui: UIContext | null = uiContext;
  if (ui !== null) {
    ui.getContextMenuController().close();
  }
}

// 类（非组件）里没有 this.getUIContext()：用它包一次。
export function animateToUI(options: AnimateParam, event: () => void): void {
  const ui: UIContext | null = uiContext;
  if (ui === null) {
    event();
    return;
  }
  ui.animateTo(options, event);
}

// 给纯数学 util 用的换算（名字带 UI 后缀，避免和已废弃的全局同名遮蔽）。
export function vp2pxUI(vp: number): number {
  return vp2px(vp);
}

export function px2vpUI(px: number): number {
  return px2vp(px);
}
