// 转发/分享面板里「选了哪几个会话」的集合运算。
//
// 和 util/messageSelection 的区别：那边选中的单位是"行"（一条相册消息整行
// 选中，不存在半选），这边就是单纯的 chatId 集合。但两条不变量是一样的：
//
//   · **不可变**——每个函数都返回新数组，传进去的那份一个字不动。面板的
//     @State 靠整份替换触发刷新，就地改写会出现"改了但不重画"。
//   · **不重复**——同一个 chatId 进两次，扇出时就会真的发两遍。
//
// 抽出来单测是因为 chatId 的取值范围最容易写错：只有私聊是正数，普通群是
// 负数、超级群和频道是 -100… 开头的负数。任何"id > 0"式的判据都会把所有
// 群组悄悄排除掉（ForwardSheet.applyChats 的注释里记着同一个坑）。

export function targetSelected(selectedIds: number[], chatId: number): boolean {
  return selectedIds.indexOf(chatId) >= 0;
}

export function selectionCount(selectedIds: number[]): number {
  return selectedIds.length;
}

// 切换一个目标：不在就加到末尾，在就去掉。
//
// 加在**末尾**而不是开头：发送顺序跟着选择顺序走，用户先选谁就先发给谁，
// 这在部分失败的提示里是可解释的。
export function toggleTarget(selectedIds: number[], chatId: number): number[] {
  if (targetSelected(selectedIds, chatId)) {
    return selectedIds.filter((id: number): boolean => id !== chatId);
  }
  return [...selectedIds, chatId];
}

// 只保留 keep 里点名的那些。
//
// **不要拿"当前列表里有没有"当 keep**：会话列表会翻页、会按文件夹页签换一批，
// 在"全部"里选中的会话切到某个页签后就不在列表里了——那时剔掉等于用户选的
// 东西凭空消失。这个函数是给"会话真的没了"（退群、被删）准备的，判据由调用方给。
export function trimSelection(selectedIds: number[], keep: number[]): number[] {
  return selectedIds.filter((id: number): boolean => keep.indexOf(id) >= 0);
}
