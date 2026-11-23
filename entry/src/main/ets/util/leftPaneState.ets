// 多栏时「左栏铺什么」的共享状态。
//
// 背景（用户 2026-11-24）：平板上「我的资料 / 联系人 / 设置」都不该整页铺满——
// 分栏布局里左栏（会话列表栏）才是承载这类"同一份内容"的地方，右栏该原样留着
// 正在看的聊天。原来的做法是把第 4 个 dock 槽当成页签切过去，中栏整页换成个人
// 资料，当前聊天直接消失。
//
// 这里是一条 AppStorage 字符串键：左栏平时画会话列表，被选中时被"另一个视图"
// 盖住。取值只有下面四个，'chats' 表示没盖。
//
// 为什么不用 splitRouting 的页面栈：栈是"目的地"的三方状态（返回键、深链、
// 账号切换都会投影到它上面），而"左栏显示什么"是页内态，不该在返回键链里当
// 一层页面，也不该让 decidePush 的 clearAndPush 规则绕进来。历史实现
// （6574abbe util/leftPaneState.ets → leftPaneMode = chats|archive|profile）
// 走的就是 AppStorage 单键；本分支的归档左栏已经用 KEY_ARCHIVE_PANE_OPEN 这套
// 写法跑通（pages/chatlist/ChatListPage.ets 的 archivePaneOpen），这里对齐它。
// 归档仍走自己那条键：它的标题条与返回箭头画在列表上方，与资料/联系人/设置
// 这种"整块替换"形态不同。
//
// 只有真正分栏时才允许它生效：消费方自己再乘 isSplitByBreakpoint 的结果，
// 单栏（手机/竖屏/强制单栏）时左栏=整页，读出来等于 'chats'，行为与改动前一致。

export const LEFT_PANE_CHATS: string = 'chats';
export const LEFT_PANE_PROFILE: string = 'profile';
export const LEFT_PANE_CONTACTS: string = 'contacts';
export const LEFT_PANE_SETTINGS: string = 'settings';

export const KEY_LEFT_PANE_VIEW: string = 'leftPaneView';

// 右栏是否正站着一个会话（分栏下由 ChatListPage 从 chat 栈的 onStateChange 写进来）。
// 用途：右栏空着的时候，dock 的「联系人 / 设置 / 个人资料」仍按老规矩切页签
// （整页分栏，右栏有占位提示）；只有右栏真的在聊，才把内容铺进左栏保住聊天。
export const KEY_SPLIT_OPEN_CHAT: string = 'splitOpenChatId';

export function leftPaneView(): string {
  const view: string | undefined = AppStorage.get<string>(KEY_LEFT_PANE_VIEW);
  return view === undefined || view === null || view === '' ? LEFT_PANE_CHATS : view;
}

export function leftPaneOpen(): boolean {
  return leftPaneView() !== LEFT_PANE_CHATS;
}

// 返回 true 表示这次真的切换了（写入了新值），false 表示本来就是该视图。
// 供 dock 槽位做幂等：连点同一格不会来回翻。
export function showLeftPane(view: string): boolean {
  if (view === LEFT_PANE_CHATS) {
    return closeLeftPane();
  }
  if (leftPaneView() === view) {
    return false;
  }
  AppStorage.setOrCreate<string>(KEY_LEFT_PANE_VIEW, view);
  return true;
}

// 返回 true 表示这次真的关掉了，供返回键链短路。
export function closeLeftPane(): boolean {
  if (!leftPaneOpen()) {
    return false;
  }
  AppStorage.setOrCreate<string>(KEY_LEFT_PANE_VIEW, LEFT_PANE_CHATS);
  return true;
}

// —— 「我的资料」的语义别名（历史调用点的措辞，读起来仍然成立）——
export function isProfilePaneOpen(): boolean {
  return leftPaneView() === LEFT_PANE_PROFILE;
}

export function openProfilePane(): boolean {
  return showLeftPane(LEFT_PANE_PROFILE);
}

export function closeProfilePane(): boolean {
  return closeLeftPane();
}
