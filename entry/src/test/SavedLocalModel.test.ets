import { describe, it, expect } from '@ohos/hypium';
import {
  parseSavedLocal, removeSavedLocal, SavedLocalRecord, savedLocalBytes, serializeSavedLocal, upsertSavedLocal
} from '../main/ets/util/savedLocalModel';

// 「已存本地」记录：按路径去重、上限、累计字节、序列化容错（2026-09-15，下载中心设计稿）。

function rec(path: string, size: number, savedAt: number): SavedLocalRecord {
  return { path: path, size: size, savedAt: savedAt };
}

function paths(list: SavedLocalRecord[]): string {
  return list.map((r: SavedLocalRecord): string => r.path).join(',');
}

export default function savedLocalModelTest() {
  describe('savedLocalModel', () => {
    it('按路径去重、新存的排最前、超上限丢最旧、空路径忽略', 0, () => {
      let list: SavedLocalRecord[] = [];
      list = upsertSavedLocal(list, rec('/a', 1, 1), 2);
      list = upsertSavedLocal(list, rec('/b', 2, 2), 2);
      list = upsertSavedLocal(list, rec('/a', 3, 3), 2);
      expect(paths(list)).assertEqual('/a,/b');
      expect(list[0].size).assertEqual(3);
      list = upsertSavedLocal(list, rec('/c', 4, 4), 2);
      expect(paths(list)).assertEqual('/c,/a');
      expect(upsertSavedLocal(list, rec('', 5, 5), 2).length).assertEqual(2);
    });

    it('删除与累计字节（负数不计）', 0, () => {
      const list: SavedLocalRecord[] = [rec('/a', 10, 1), rec('/b', -3, 2), rec('/c', 5, 3)];
      expect(savedLocalBytes(list)).assertEqual(15);
      expect(paths(removeSavedLocal(list, '/a'))).assertEqual('/b,/c');
    });

    it('序列化往返；读坏了当没有', 0, () => {
      const back: SavedLocalRecord[] = parseSavedLocal(serializeSavedLocal([rec('/a', 10, 1)]));
      expect(back.length).assertEqual(1);
      expect(back[0].path).assertEqual('/a');
      expect(back[0].size).assertEqual(10);
      expect(parseSavedLocal('not json').length).assertEqual(0);
      expect(parseSavedLocal('{"a":1}').length).assertEqual(0);
      expect(parseSavedLocal('[{"size":3}]').length).assertEqual(0);
      expect(parseSavedLocal('').length).assertEqual(0);
    });
  });
}
