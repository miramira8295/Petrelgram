import { describe, it, expect } from '@ohos/hypium';
import {
  DC_KIND_VIDEO, DC_SECTION_ACTIVE, DC_SOURCE_CACHE, DC_STATE_DOWNLOADING, DownloadCenterItem
} from '../main/ets/util/downloadCenterModel';
import {
  buildDownloadCenterRows, DC_LAYOUT_ACTIVE, DC_LAYOUT_HEADER, DcRow, defaultDcRowOptions
} from '../main/ets/util/downloadCenterRows';
import { DcRowVM } from '../main/ets/util/downloadCenterRowVM';

// 下载中心的行模型：从 DcRow 拷字段、原地更新保持身份、速度按 KB/s 取整、能不能定位到消息（2026-09-15）。

function item(downloaded: number, speed: number, chatId: number): DownloadCenterItem {
  return {
    fileId: 5, path: '', name: 'trip.mp4', kind: DC_KIND_VIDEO, size: 1000, downloaded: downloaded,
    state: DC_STATE_DOWNLOADING, source: DC_SOURCE_CACHE, mtime: 9, preview: '', chatId: chatId, messageId: 2,
    mimeType: '', session: 'Kevin', savedLocal: false, speed: speed
  };
}

function rows(downloaded: number, speed: number, chatId: number = 1): DcRow[] {
  return buildDownloadCenterRows([{ section: DC_SECTION_ACTIVE, items: [item(downloaded, speed, chatId)] }],
    defaultDcRowOptions());
}

export default function downloadCenterRowVMTest() {
  describe('downloadCenterRowVM', () => {
    it('段头与条目行的字段', 0, () => {
      const r: DcRow[] = rows(100, 1500);
      const header: DcRowVM = DcRowVM.of(r[0]);
      expect(header.layout).assertEqual(DC_LAYOUT_HEADER);
      expect(header.count).assertEqual(1);
      expect(header.anyDownloading).assertTrue();
      const row: DcRowVM = DcRowVM.of(r[1]);
      expect(row.layout).assertEqual(DC_LAYOUT_ACTIVE);
      expect(row.itemId).assertEqual('f5');
      expect(row.session).assertEqual('Kevin');
      expect(row.first && row.last).assertTrue();
      expect(row.speed).assertEqual(1024);
      expect(row.canJump).assertTrue();
      expect(DcRowVM.of(rows(100, 0, 0)[1]).canJump).assertFalse();
    });

    it('原地更新：身份不变，进度跟着变', 0, () => {
      const row: DcRowVM = DcRowVM.of(rows(100, 0)[1]);
      const id: string = row.rowId;
      row.apply(rows(600, 0)[1]);
      expect(row.rowId).assertEqual(id);
      expect(row.downloaded).assertEqual(600);
    });
  });
}
