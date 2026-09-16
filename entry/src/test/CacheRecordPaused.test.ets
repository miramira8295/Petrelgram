import { describe, it, expect } from '@ohos/hypium';
import {
  CacheRecord, parseCacheRecords, serializeCacheRecords, upsertCacheRecord, withCacheAllowCellular, withCachePaused
} from '../main/ets/util/cacheRegistryModel';

// 缓存记录的两个用户标记：暂停（重启后不续上）、用流量继续（不受「只在 Wi‑Fi 下后台缓存」限制）。
// 只由 with* 改，upsert 沿用旧值，能落盘读回（2026-09-15，后台缓存）。

function rec(fileId: number, addedAt: number): CacheRecord {
  return {
    fileId: fileId, chatId: 1, messageId: 1, kind: 'video', name: '', size: 0, mimeType: '', preview: '',
    background: true, addedAt: addedAt
  };
}

export default function cacheRecordPausedTest() {
  describe('cacheRecordPaused', () => {
    it('withCachePaused 只改目标那条', 0, () => {
      const list: CacheRecord[] = withCachePaused([rec(1, 1), rec(2, 2)], 2, true);
      expect(list[0].paused === true).assertFalse();
      expect(list[1].paused === true).assertTrue();
    });

    it('再次登记（upsert）沿用旧的暂停标记', 0, () => {
      const paused: CacheRecord[] = withCachePaused([rec(1, 1)], 1, true);
      const again: CacheRecord[] = upsertCacheRecord(paused, rec(1, 5), 10);
      expect(again[0].paused === true).assertTrue();
      expect(again[0].addedAt).assertEqual(5);
    });

    it('落盘读回保留暂停标记；旧数据没有这个字段读成未暂停', 0, () => {
      const back: CacheRecord[] = parseCacheRecords(serializeCacheRecords(withCachePaused([rec(1, 1)], 1, true)));
      expect(back[0].paused === true).assertTrue();
      const legacy: CacheRecord[] = parseCacheRecords('[{"fileId":3,"background":true}]');
      expect(legacy[0].paused === true).assertFalse();
      expect(legacy[0].allowCellular === true).assertFalse();
    });

    it('用流量继续：只改目标那条，upsert 沿用，和暂停标记互不覆盖，落盘读回', 0, () => {
      const list: CacheRecord[] = withCacheAllowCellular([rec(1, 1), rec(2, 2)], 1, true);
      expect(list[0].allowCellular === true).assertTrue();
      expect(list[1].allowCellular === true).assertFalse();
      const again: CacheRecord[] = upsertCacheRecord(list, rec(1, 9), 10);
      expect(again[0].allowCellular === true).assertTrue();
      const both: CacheRecord[] = withCachePaused(again, 1, true);
      expect(both[0].allowCellular === true && both[0].paused === true).assertTrue();
      const back: CacheRecord[] = parseCacheRecords(serializeCacheRecords(both));
      expect(back[0].allowCellular === true && back[0].paused === true).assertTrue();
    });
  });
}
