import { FolderInfo } from '../store/FolderStore';

// 转发面板的文件夹页签（issue #200）。
// ChatStore 的会话列表按键分桶：'main' / 'archive' / `folder:${id}`，首页切文件夹
// 用的就是这套键；这里只负责「页签 → 键」的映射和页签顺序，不碰数据。
export const ALL_FOLDER_ID: number = 0;

export interface ForwardFolderChip {
  id: number;
  title: string;
  isAll: boolean;
}

export function forwardListKey(folderId: number): string {
  return folderId === ALL_FOLDER_ID ? 'main' : `folder:${folderId}`;
}

// 「全部」恒在首位；文件夹按 FolderStore 给的顺序（就是首页页签的顺序）。
// 「全部」的 title 由调用方翻译（这里不碰资源），留空串。
export function forwardFolderChips(folders: FolderInfo[]): ForwardFolderChip[] {
  const out: ForwardFolderChip[] = [{ id: ALL_FOLDER_ID, title: '', isAll: true }];
  for (const f of folders) {
    out.push({ id: f.id, title: f.title, isAll: false });
  }
  return out;
}

// 头像网格的列数按可用宽度自适应：每格按 72vp 算（头像 56 + 两侧留白），夹在
// 4–6 之间——360vp 手机 4 列、440vp 宽机 5 列、平板/分栏 6 列。头像与字号不变。
export const FORWARD_GRID_CELL_VP: number = 72;
export const FORWARD_GRID_MIN_COLUMNS: number = 4;
export const FORWARD_GRID_MAX_COLUMNS: number = 6;

export function forwardGridColumns(availableWidth: number): number {
  const fit: number = Math.floor(Math.max(0, availableWidth) / FORWARD_GRID_CELL_VP);
  return Math.max(FORWARD_GRID_MIN_COLUMNS, Math.min(FORWARD_GRID_MAX_COLUMNS, fit));
}

export function forwardColumnsTemplate(columns: number): string {
  const parts: string[] = [];
  for (let i = 0; i < columns; i++) {
    parts.push('1fr');
  }
  return parts.join(' ');
}
