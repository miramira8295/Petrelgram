import { describe, it, expect } from '@ohos/hypium';
import {
  DC_KIND_FILE, DC_SOURCE_DISK, DC_STATE_COMPLETE, DC_STATE_DOWNLOADING, DownloadCenterItem
} from '../main/ets/util/downloadCenterModel';
import {
  applyDoneWatermark, DC_MIN_VISIBLE_ITEMS, DcSourceWindow, doneWatermark, oldestMtime, shouldTopUp
} from '../main/ets/util/downloadCenterPaging';

// 下载中心分页：「已完成」的水位线、自动续拉的条件（2026-09-15 第四版）。

function item(name: string, state: string, mtime: number): DownloadCenterItem {
  return {
    fileId: 0, path: `/${name}`, name: name, kind: DC_KIND_FILE, size: 1, downloaded: 1, state: state,
    source: DC_SOURCE_DISK, mtime: mtime, preview: '', chatId: 0, messageId: 0, mimeType: '',
    session: '', savedLocal: false, speed: 0
  };
}

function win(hasMore: boolean, loadedCount: number, oldest: number): DcSourceWindow {
  return { hasMore: hasMore, loadedCount: loadedCount, oldestLoadedMtime: oldest };
}

export default function downloadCenterPagingTest() {
  describe('downloadCenterPaging', () => {
    it('各路都翻到底：没有水位线，全显示', 0, () => {
      const mark: number = doneWatermark([win(false, 100, 5), win(false, 0, 0)]);
      expect(mark).assertEqual(Number.NEGATIVE_INFINITY);
      const items = [item('a', DC_STATE_COMPLETE, 1), item('b', DC_STATE_COMPLETE, 2)];
      expect(applyDoneWatermark(items, mark).length).assertEqual(2);
    });

    it('还有下一页的几路里取最新的前沿；翻到底的那路不参与', 0, () => {
      expect(doneWatermark([win(true, 100, 500), win(true, 100, 800), win(false, 100, 900)])).assertEqual(800);
    });

    it('有下一页却一条都没加载：整段压住', 0, () => {
      expect(doneWatermark([win(true, 0, 0), win(true, 100, 800)])).assertEqual(Number.POSITIVE_INFINITY);
    });

    it('水位线只挡已完成，进行中照常显示', 0, () => {
      const items = [item('d900', DC_STATE_COMPLETE, 900), item('d700', DC_STATE_COMPLETE, 700),
        item('dl', DC_STATE_DOWNLOADING, 100)];
      const shown = applyDoneWatermark(items, 800);
      expect(shown.map((it: DownloadCenterItem): string => it.name).join(',')).assertEqual('d900,dl');
    });

    it('最旧时间与自动续拉的条件', 0, () => {
      expect(oldestMtime([])).assertEqual(Number.POSITIVE_INFINITY);
      expect(oldestMtime([item('a', DC_STATE_COMPLETE, 5), item('b', DC_STATE_COMPLETE, 3)])).assertEqual(3);
      expect(shouldTopUp(DC_MIN_VISIBLE_ITEMS - 1, true, false)).assertTrue();
      expect(shouldTopUp(DC_MIN_VISIBLE_ITEMS, true, false)).assertFalse();
      expect(shouldTopUp(0, false, false)).assertFalse();
      expect(shouldTopUp(0, true, true)).assertFalse();
    });
  });
}
