import { describe, it, expect } from '@ohos/hypium';
import {
  DC_KIND_FILE, DC_SECTION_ACTIVE, DC_SECTION_DONE, DC_SORT_SIZE, DC_SOURCE_DISK, DC_SOURCE_MANAGER,
  DC_STATE_COMPLETE, DC_STATE_DOWNLOADING, DC_STATE_PAUSED, DownloadCenterItem, DownloadCenterSection, displayNameOf,
  isGeneratedCacheName
} from '../main/ets/util/downloadCenterModel';
import {
  buildDownloadCenterRows, DC_LAYOUT_ACTIVE, DC_LAYOUT_DONE, DC_LAYOUT_GROUP, DC_LAYOUT_HEADER, DC_ROW_GROUP,
  DC_ROW_HEADER, DC_ROW_ITEM, DcRow, DcRowOptions, dcRowId, dcRowLayout, dcRowStableKey, defaultDcRowOptions
} from '../main/ets/util/downloadCenterRows';

// 下载中心的行：段头（条数、全部暂停/开始、排序），卡片首尾，折叠来源不明的缓存；
// key 只含身份 + 布局——进度、勾选不进 key（行复用 + @Trace 原地刷新）。

function item(fileId: number, state: string): DownloadCenterItem {
  return {
    fileId: fileId, path: '', name: `f${fileId}`, kind: DC_KIND_FILE, size: 10, downloaded: 5, state: state,
    source: DC_SOURCE_MANAGER, mtime: fileId, preview: '', chatId: 0, messageId: 0, mimeType: '',
    session: '', savedLocal: false, speed: 0
  };
}

function diskItem(path: string, size: number): DownloadCenterItem {
  return {
    fileId: 0, path: path, name: '123.jpg', kind: DC_KIND_FILE, size: size, downloaded: size, state: DC_STATE_COMPLETE,
    source: DC_SOURCE_DISK, mtime: 1, preview: '', chatId: 0, messageId: 0, mimeType: '',
    session: '', savedLocal: false, speed: 0
  };
}

function opts(batch: boolean = false, selected: string[] = []): DcRowOptions {
  const o: DcRowOptions = defaultDcRowOptions();
  o.batch = batch;
  o.selectedIds = new Set<string>(selected);
  return o;
}

function types(rows: DcRow[]): string {
  return rows.map((r: DcRow): string => r.type === DC_ROW_HEADER ? 'H' : (r.type === DC_ROW_GROUP ? 'G' : 'I')).join(',');
}

export default function downloadCenterRowsTest() {
  describe('downloadCenterRows', () => {
    it('每段一行段头带条数，条目行标出卡片首尾', 0, () => {
      const sections: DownloadCenterSection[] = [
        { section: DC_SECTION_ACTIVE, items: [item(1, DC_STATE_DOWNLOADING), item(2, DC_STATE_PAUSED)] },
        { section: DC_SECTION_DONE, items: [item(3, DC_STATE_COMPLETE)] }
      ];
      const rows: DcRow[] = buildDownloadCenterRows(sections, opts());
      expect(types(rows)).assertEqual('H,I,I,H,I');
      expect(rows[0].count).assertEqual(2);
      expect(rows[0].anyDownloading).assertTrue();
      expect(rows[0].sort).assertEqual('');
      expect(rows[1].first).assertTrue();
      expect(rows[1].last).assertFalse();
      expect(rows[2].last).assertTrue();
      expect(rows[3].anyDownloading).assertFalse();
      expect(rows[4].first && rows[4].last).assertTrue();
      expect(rows[4].type).assertEqual(DC_ROW_ITEM);
    });

    it('布局决定复用池；已完成段头带当前排序', 0, () => {
      const o: DcRowOptions = opts();
      o.sort = DC_SORT_SIZE;
      const rows = buildDownloadCenterRows([
        { section: DC_SECTION_ACTIVE, items: [item(1, DC_STATE_PAUSED)] },
        { section: DC_SECTION_DONE, items: [item(2, DC_STATE_COMPLETE)] }
      ], o);
      expect(rows.map((r: DcRow): string => dcRowLayout(r)).join(','))
        .assertEqual(`${DC_LAYOUT_HEADER},${DC_LAYOUT_ACTIVE},${DC_LAYOUT_HEADER},${DC_LAYOUT_DONE}`);
      expect(rows[0].anyDownloading).assertFalse();
      expect(rows[2].sort).assertEqual(DC_SORT_SIZE);
    });

    it('批量勾选与进度都不进 key；不在批量模式时不算勾选', 0, () => {
      const sections: DownloadCenterSection[] = [{ section: DC_SECTION_DONE, items: [item(1, DC_STATE_COMPLETE)] }];
      const off = buildDownloadCenterRows(sections, opts(true));
      const on = buildDownloadCenterRows(sections, opts(true, ['f1']));
      expect(on[1].selected).assertTrue();
      expect(dcRowStableKey(on[1])).assertEqual(dcRowStableKey(off[1]));
      expect(buildDownloadCenterRows(sections, opts(false, ['f1']))[1].selected).assertFalse();
      const changed = item(1, DC_STATE_COMPLETE);
      changed.downloaded = 9;
      const moved = buildDownloadCenterRows([{ section: DC_SECTION_DONE, items: [changed] }], opts());
      expect(dcRowStableKey(moved[1])).assertEqual(dcRowStableKey(off[1]));
    });

    it('同一条从进行中变成已完成：身份不变、key 变（换对应布局的节点）', 0, () => {
      const active = buildDownloadCenterRows([{ section: DC_SECTION_ACTIVE, items: [item(7, DC_STATE_DOWNLOADING)] }], opts());
      const done = buildDownloadCenterRows([{ section: DC_SECTION_DONE, items: [item(7, DC_STATE_COMPLETE)] }], opts());
      expect(dcRowId(active[1])).assertEqual(dcRowId(done[1]));
      expect(dcRowStableKey(active[1]) === dcRowStableKey(done[1])).assertFalse();
    });

    it('来源不明的缓存折成一行放在卡片末尾，展开接在它下面；只有一条不折', 0, () => {
      const named: DownloadCenterItem = item(1, DC_STATE_COMPLETE);
      const sections: DownloadCenterSection[] = [
        { section: DC_SECTION_DONE, items: [diskItem('/x', 10), named, diskItem('/y', 30)] }
      ];
      const o: DcRowOptions = opts();
      o.collapseUnsourced = true;
      const collapsed: DcRow[] = buildDownloadCenterRows(sections, o);
      expect(types(collapsed)).assertEqual('H,I,G');
      expect(collapsed[0].count).assertEqual(3);
      expect(collapsed[2].groupCount).assertEqual(2);
      expect(collapsed[2].groupBytes).assertEqual(40);
      expect(collapsed[2].last).assertTrue();
      expect(dcRowLayout(collapsed[2])).assertEqual(DC_LAYOUT_GROUP);
      o.unsourcedExpanded = true;
      const expanded: DcRow[] = buildDownloadCenterRows(sections, o);
      expect(types(expanded)).assertEqual('H,I,G,I,I');
      expect(expanded[2].expanded && !expanded[2].last).assertTrue();
      expect(expanded[4].last).assertTrue();
      const single: DcRow[] = buildDownloadCenterRows(
        [{ section: DC_SECTION_DONE, items: [named, diskItem('/x', 10)] }], o);
      expect(types(single)).assertEqual('H,I,I');
    });

    it('TDLib 生成的数字文件名不当标题', 0, () => {
      expect(isGeneratedCacheName('4985985701404937637_121.jpg')).assertTrue();
      expect(isGeneratedCacheName('5192003.mp4')).assertTrue();
      expect(isGeneratedCacheName('旅行.mp4')).assertFalse();
      expect(isGeneratedCacheName('report_2024.pdf')).assertFalse();
      expect(displayNameOf('4985985701404937637_121.jpg')).assertEqual('');
      expect(displayNameOf('会议纪要.docx')).assertEqual('会议纪要.docx');
    });
  });
}
