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

export function openSheetCount(): number {
  return entries.length;
}

// 仅供单测。
export function resetSheetDismissForTest(): void {
  entries = [];
  nextId = 1;
}
