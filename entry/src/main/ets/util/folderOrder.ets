// 文件夹设置页的排序：「所有」（主会话列表）与各文件夹混在同一张可拖动的列表里。
//
// TDLib 用两样东西表达顺序：文件夹 id 的数组 + main_chat_list_position（「所有」
// 插在第几位，0 起）。设置页拖动的是一张混合列表，这里负责两种表达之间互转。
// 注意：main_chat_list_position 只有 Telegram Premium 账号才能是非 0，非会员时
// 「所有」钉在第 0 行（minRowFor）。纯函数，有单测。

// 混合列表里代表「所有」的那一项。文件夹 id 都是正数，取 -1 不会撞。
export const MAIN_LIST_ROW: number = -1;

// 文件夹顺序 + 「所有」的位置 → 混合列表。位置越界时夹到合法范围。
export function combinedRows(folderIds: number[], mainPosition: number): number[] {
  const pos: number = Math.max(0, Math.min(folderIds.length, mainPosition));
  const rows: number[] = folderIds.slice();
  rows.splice(pos, 0, MAIN_LIST_ROW);
  return rows;
}

export interface FolderOrder {
  folderIds: number[];
  mainPosition: number;
}

// 混合列表 → 文件夹顺序 + 「所有」的位置（reorderChatFolders 的两个参数）。
export function splitRows(rows: number[]): FolderOrder {
  const at: number = rows.indexOf(MAIN_LIST_ROW);
  return {
    folderIds: rows.filter((id: number): boolean => id !== MAIN_LIST_ROW),
    mainPosition: at < 0 ? 0 : at
  };
}

// 把第 from 行挪到第 to 行，返回新数组。越界或原地不动时原样返回同一个数组。
export function moveRow(rows: number[], from: number, to: number): number[] {
  if (from === to || from < 0 || to < 0 || from >= rows.length || to >= rows.length) {
    return rows;
  }
  const next: number[] = rows.slice();
  const moved: number = next.splice(from, 1)[0];
  next.splice(to, 0, moved);
  return next;
}

// 能落到的最小行号：非会员时「所有」钉在第 0 行，别的行最高只能到第 1 行。
export function minRowFor(premium: boolean): number {
  return premium ? 0 : 1;
}
