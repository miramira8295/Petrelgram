import { describe, it, expect } from '@ohos/hypium';
import {
  CacheRecord, parseCacheRecords, removeCacheRecord, serializeCacheRecords, upsertCacheRecord
} from '../main/ets/util/cacheRegistryModel';

// 缓存记录：同一文件只留一条、最新在前、字段不被空值覆盖、后台缓存标记不降级、读坏了当空（2026-09-15）。

function rec(fileId: number, name: string, background: boolean, addedAt: number, size: number = 0): CacheRecord {
  return {
    fileId: fileId, chatId: 7, messageId: fileId * 10, kind: 'video', name: name, size: size,
    mimeType: '', preview: '', background: background, addedAt: addedAt
  };
}

export default function cacheRegistryModelTest() {
  describe('cacheRegistryModel', () => {
    it('同一 fileId 只留一条，最新登记的排最前', 0, () => {
      let list: CacheRecord[] = [];
      list = upsertCacheRecord(list, rec(1, 'a', false, 1), 10);
      list = upsertCacheRecord(list, rec(2, 'b', false, 2), 10);
      list = upsertCacheRecord(list, rec(1, 'a2', false, 3), 10);
      expect(list.map((r: CacheRecord): number => r.fileId).join(',')).assertEqual('1,2');
      expect(list[0].name).assertEqual('a2');
    });

    it('后台缓存标记一旦为真就保持，空字段沿用旧值', 0, () => {
      let list: CacheRecord[] = [rec(1, 'movie.mp4', true, 1, 5000)];
      list = upsertCacheRecord(list, rec(1, '', false, 2), 10);
      expect(list[0].background).assertTrue();
      expect(list[0].name).assertEqual('movie.mp4');
      expect(list[0].size).assertEqual(5000);
    });

    it('超出上限丢最旧的；fileId 为 0 不登记', 0, () => {
      let list: CacheRecord[] = [];
      for (let i = 1; i <= 5; i++) {
        list = upsertCacheRecord(list, rec(i, `f${i}`, false, i), 3);
      }
      expect(list.map((r: CacheRecord): number => r.fileId).join(',')).assertEqual('5,4,3');
      expect(upsertCacheRecord(list, rec(0, 'x', false, 9), 3).length).assertEqual(3);
      expect(removeCacheRecord(list, 4).map((r: CacheRecord): number => r.fileId).join(',')).assertEqual('5,3');
    });

    it('序列化往返；读坏了当空；非法条目跳过', 0, () => {
      const list: CacheRecord[] = [rec(3, 'c', true, 9, 100)];
      const back = parseCacheRecords(serializeCacheRecords(list));
      expect(back.length).assertEqual(1);
      expect(back[0].background).assertTrue();
      expect(back[0].size).assertEqual(100);
      expect(parseCacheRecords('not json').length).assertEqual(0);
      expect(parseCacheRecords('').length).assertEqual(0);
      expect(parseCacheRecords('[{"fileId":0},{"fileId":"x"},{"fileId":5,"name":"ok"}]').length).assertEqual(1);
    });
  });
}
