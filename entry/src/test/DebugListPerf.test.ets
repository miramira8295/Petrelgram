import { describe, it, expect } from '@ohos/hypium';
import {
  KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT, LIST_CACHED_COUNT_OPTIONS,
  normalizeListCachedCount
} from '../main/ets/util/debugListPerf';

export default function debugListPerfTest() {
  describe('DebugListPerf', () => {
    it('默认档位是 6 —— 这个开关不改变现状', 0, () => {
      expect(LIST_CACHED_COUNT_DEFAULT).assertEqual(6);
    });

    it('默认档在候选列表里，且候选列表是 4/6/8 升序', 0, () => {
      expect(LIST_CACHED_COUNT_OPTIONS.indexOf(LIST_CACHED_COUNT_DEFAULT) >= 0).assertTrue();
      expect(LIST_CACHED_COUNT_OPTIONS.length).assertEqual(3);
      expect(LIST_CACHED_COUNT_OPTIONS[0]).assertEqual(4);
      expect(LIST_CACHED_COUNT_OPTIONS[1]).assertEqual(6);
      expect(LIST_CACHED_COUNT_OPTIONS[2]).assertEqual(8);
      for (let i = 1; i < LIST_CACHED_COUNT_OPTIONS.length; i++) {
        expect(LIST_CACHED_COUNT_OPTIONS[i] > LIST_CACHED_COUNT_OPTIONS[i - 1]).assertTrue();
      }
    });

    it('键名带 debug 前缀，表明它不是用户设置', 0, () => {
      expect(KEY_DEBUG_LIST_CACHED.startsWith('debug')).assertTrue();
    });

    it('候选档位原样通过', 0, () => {
      for (const option of LIST_CACHED_COUNT_OPTIONS) {
        expect(normalizeListCachedCount(option)).assertEqual(option);
      }
    });

    it('空值回默认档', 0, () => {
      expect(normalizeListCachedCount(undefined)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(null)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
    });

    it('非法值回默认档，而不是就近取整', 0, () => {
      // 5 离 4 和 6 都只差 1，就近取整会把它变成一个看起来合理的档位；
      // 标定时那就是假数据，所以一律回可辨认的默认档。
      expect(normalizeListCachedCount(5)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(7)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(0)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(-4)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(999)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(6.5)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
    });

    it('NaN / Infinity 回默认档', 0, () => {
      expect(normalizeListCachedCount(Number.NaN)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(Number.POSITIVE_INFINITY)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
      expect(normalizeListCachedCount(Number.NEGATIVE_INFINITY)).assertEqual(LIST_CACHED_COUNT_DEFAULT);
    });
  });
}
