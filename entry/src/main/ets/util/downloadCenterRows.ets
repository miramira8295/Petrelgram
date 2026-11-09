import {
  DC_SECTION_ACTIVE, DC_SECTION_DONE, DC_SORT_TIME, DC_STATE_DOWNLOADING, DownloadCenterItem, DownloadCenterSection,
  downloadCenterItemId, isUnsourcedCache
} from './downloadCenterModel';

// 下载中心列表的行（2026-09-15；第四版行复用，第五版加折叠行与排序）。
// 每段一行段头（「进行中 · N」带全部暂停/开始，「已完成 · N」带排序切换），下面是同一张圆角卡片里的条目行——
// 卡片由首行 / 末行的圆角和边框拼出来。「全部」页签里来源不明的磁盘缓存折成一行，点开接在它下面。
// 行的内容（进度、速度、勾选……）不进 LazyForEach 的 key：它们写进 util/downloadCenterRowVM 的 @Trace 字段原地刷新；
// key 只含身份和布局，布局变了（进行中 → 已完成）才换节点。

export const DC_ROW_HEADER: string = 'header';
export const DC_ROW_ITEM: string = 'item';
export const DC_ROW_GROUP: string = 'group';

// 布局 = 复用池的 reuseId。
export const DC_LAYOUT_HEADER: string = 'header';
export const DC_LAYOUT_ACTIVE: string = 'active';
export const DC_LAYOUT_DONE: string = 'done';
export const DC_LAYOUT_GROUP: string = 'group';

// 行内按钮 / 长按菜单报给页面的动作。
export const DC_ACTION_PAUSE: string = 'pause';
export const DC_ACTION_RESUME: string = 'resume';
export const DC_ACTION_RETRY: string = 'retry';
export const DC_ACTION_CANCEL: string = 'cancel';
export const DC_ACTION_SAVE: string = 'save';
export const DC_ACTION_OPEN: string = 'open';
export const DC_ACTION_DELETE: string = 'delete';
export const DC_ACTION_SELECT: string = 'select';
export const DC_ACTION_ALLOW_CELLULAR: string = 'allowCellular';
export const DC_ACTION_JUMP: string = 'jump';

// 至少这么多条才折：只有一条的话折起来反而多点一下。
const MIN_GROUP_SIZE: number = 2;

export interface DcRowOptions {
  batch: boolean;
  selectedIds: Set<string>;
  sort: string;               // 「已完成」段头上显示的排序
  collapseUnsourced: boolean; // 把来源不明的磁盘缓存折成一行（只在「全部」页签）
  unsourcedExpanded: boolean;
}

export function defaultDcRowOptions(): DcRowOptions {
  return {
    batch: false, selectedIds: new Set<string>(), sort: DC_SORT_TIME, collapseUnsourced: false,
    unsourcedExpanded: false
  };
}

export interface DcRow {
  type: string;
  section: string;
  count: number;           // 段头：本段条目数
  anyDownloading: boolean; // 段头（进行中）：有正在传的给「全部暂停」，否则「全部开始」
  sort: string;            // 段头（已完成）：当前排序；其它行空串
  item: DownloadCenterItem | null;
  first: boolean;
  last: boolean;
  selected: boolean;
  groupCount: number;      // 折叠行：折了几条
  groupBytes: number;      // 折叠行：共多大
  expanded: boolean;       // 折叠行：是否展开
}

function blankRow(type: string, section: string): DcRow {
  return {
    type: type, section: section, count: 0, anyDownloading: false, sort: '', item: null, first: false, last: false,
    selected: false, groupCount: 0, groupBytes: 0, expanded: false
  };
}

function itemRow(section: string, it: DownloadCenterItem, options: DcRowOptions): DcRow {
  const row: DcRow = blankRow(DC_ROW_ITEM, section);
  row.item = it;
  row.selected = options.batch && options.selectedIds.has(downloadCenterItemId(it));
  return row;
}

export function buildDownloadCenterRows(sections: DownloadCenterSection[], options: DcRowOptions): DcRow[] {
  const rows: DcRow[] = [];
  for (const s of sections) {
    const header: DcRow = blankRow(DC_ROW_HEADER, s.section);
    header.count = s.items.length;
    header.anyDownloading = s.section === DC_SECTION_ACTIVE &&
      s.items.some((it: DownloadCenterItem): boolean => it.state === DC_STATE_DOWNLOADING);
    header.sort = s.section === DC_SECTION_DONE ? options.sort : '';
    rows.push(header);
    let listed: DownloadCenterItem[] = s.items;
    let grouped: DownloadCenterItem[] = [];
    if (s.section === DC_SECTION_DONE && options.collapseUnsourced) {
      const unsourced: DownloadCenterItem[] = s.items.filter((it: DownloadCenterItem): boolean => isUnsourcedCache(it));
      if (unsourced.length >= MIN_GROUP_SIZE) {
        grouped = unsourced;
        listed = s.items.filter((it: DownloadCenterItem): boolean => !isUnsourcedCache(it));
      }
    }
    const card: DcRow[] = listed.map((it: DownloadCenterItem): DcRow => itemRow(s.section, it, options));
    if (grouped.length > 0) {
      const group: DcRow = blankRow(DC_ROW_GROUP, s.section);
      group.groupCount = grouped.length;
      group.groupBytes = grouped.reduce((sum: number, it: DownloadCenterItem): number => sum + Math.max(0, it.size), 0);
      group.expanded = options.unsourcedExpanded;
      card.push(group);
      if (options.unsourcedExpanded) {
        for (const it of grouped) {
          card.push(itemRow(s.section, it, options));
        }
      }
    }
    for (let i = 0; i < card.length; i++) {
      card[i].first = i === 0;
      card[i].last = i === card.length - 1;
      rows.push(card[i]);
    }
  }
  return rows;
}

export function dcRowId(r: DcRow): string {
  if (r.type === DC_ROW_HEADER) {
    return `h_${r.section}`;
  }
  if (r.type === DC_ROW_GROUP) {
    return `g_${r.section}`;
  }
  return `i_${r.item !== null ? downloadCenterItemId(r.item) : r.section}`;
}

export function dcRowLayout(r: DcRow): string {
  if (r.type === DC_ROW_HEADER) {
    return DC_LAYOUT_HEADER;
  }
  if (r.type === DC_ROW_GROUP) {
    return DC_LAYOUT_GROUP;
  }
  return r.section === DC_SECTION_DONE ? DC_LAYOUT_DONE : DC_LAYOUT_ACTIVE;
}

// LazyForEach 的 key：身份 + 布局。
export function dcRowStableKey(r: DcRow): string {
  return `${dcRowId(r)}|${dcRowLayout(r)}`;
}
