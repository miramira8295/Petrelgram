// 「返回键该先关掉谁」的登记处。
//
// 【为什么需要】ChatPage 在 HdsNavDestination 上接管了 onBackPressed，返回键
// 一律先问它。它认识自己那几个浮层（录制、菜单、转发、表态、查看器…），但认不得
// **别人用 bindSheet 弹出来的面板**——面板开着按返回，它返回 false，框架就把
// 整页出栈了。用户 2026-09-14：「贴纸弹窗弹出的时候，返回键不会收起，会直接退出」。
//
// 面板自己在打开时登记一个关闭回调、关闭时注销；返回键按**后进先出**取最上面
// 那个。这样新加面板的人不用去改 ChatPage 的那串 if。
type Dismiss = () => void;

interface Entry {
  id: number;
  dismiss: Dismiss;
}

let entries: Entry[] = [];
let nextId: number = 1;

// 返回取消登记的函数。**必须在面板关闭时调用**，否则返回键会去关一个已经不在
// 的面板（表现是"按一次返回没反应"）。
export function pushSheetDismiss(dismiss: Dismiss): () => void {
  const id: number = nextId++;
  entries = [...entries, { id: id, dismiss: dismiss }];
  return (): void => {
    entries = entries.filter((e: Entry): boolean => e.id !== id);
  };
}

// 关掉最上面那个面板。返回 true 表示"这次返回键已经被消费了"。
export function dismissTopSheet(): boolean {
  if (entries.length === 0) {
    return false;
  }
  const top: Entry = entries[entries.length - 1];
  entries = entries.slice(0, entries.length - 1);
  top.dismiss();
  return true;
}

// 关掉**所有**登记过的面板，从最上面往下（LIFO，和用户连续按返回一致）。
// 返回关掉了几个。
//
// 【为什么需要】bindSheet 画在窗口的浮层里，压得住同窗口内的任何在树组件。
// 「分享到…」（Index 那层 ShareTargetSheet）是普通 Stack 子节点，所以当别的
// 应用把内容分享进 Petrelgram、而我们正开着贴纸合集/全屏编辑这类 bindSheet 时，
// 分享选择器被盖在下面（用户 2026-10-30：「系统分享抽屉会显示在添加贴纸抽屉
// 下方」）。分享进来的那一刻先把面板全收掉，选择器才露得出来。
//
// 条目是**边关边弹**的，所以每个 dismiss 回调里那句注销调用都是幂等的空操作；
// 反过来，注销函数也必须在面板自己关掉时照常调用（见 pushSheetDismiss）。
export function dismissAllSheets(): number {
  let closed: number = 0;
  while (entries.length > 0) {
    const top: Entry = entries[entries.length - 1];
    entries = entries.slice(0, entries.length - 1);
    top.dismiss();
    closed++;
  }
  return closed;
}

export function openSheetCount(): number {
  return entries.length;
}

// 仅供单测。
export function resetSheetDismissForTest(): void {
  entries = [];
  nextId = 1;
}
