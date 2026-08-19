import { describe, expect, it } from '@ohos/hypium';
import {
  SEARCH_FETCH, SEARCH_JUMP, SEARCH_STAY, SearchStep,
  searchCounterText, stepNewer, stepOlder
} from '../main/ets/util/searchPaging';

// 结果按新→旧排列：∧ 往更旧（下标 +1），∨ 往更新（下标 -1）。
export default function searchPagingTest() {
  describe('searchPaging', () => {
    it('∧ 在已加载范围内直接跳', 0, () => {
      const s: SearchStep = stepOlder([9, 8, 7], 0, 3);
      expect(s.action).assertEqual(SEARCH_JUMP);
      expect(s.index).assertEqual(1);
    });

    it('∧ 到已加载尽头且还有更多：翻页，锚点是最后一条', 0, () => {
      const s: SearchStep = stepOlder([9, 8, 7], 2, 50);
      expect(s.action).assertEqual(SEARCH_FETCH);
      expect(s.index).assertEqual(3);
      expect(s.fromMessageId).assertEqual(7);
    });

    it('∧ 已经全部加载完：不动', 0, () => {
      expect(stepOlder([9, 8, 7], 2, 3).action).assertEqual(SEARCH_STAY);
    });

    it('∧ 空结果集不翻页（没有锚点可用）', 0, () => {
      expect(stepOlder([], 0, 0).action).assertEqual(SEARCH_STAY);
      expect(stepOlder([], 0, 50).action).assertEqual(SEARCH_STAY);
    });

    it('∨ 往更新走', 0, () => {
      const s: SearchStep = stepNewer(2);
      expect(s.action).assertEqual(SEARCH_JUMP);
      expect(s.index).assertEqual(1);
    });

    it('∨ 已在最新一条：不动', 0, () => {
      expect(stepNewer(0).action).assertEqual(SEARCH_STAY);
    });

    it('计数按新→旧换算成人读的序号', 0, () => {
      expect(searchCounterText(0, 12)).assertEqual('12 / 12');
      expect(searchCounterText(11, 12)).assertEqual('1 / 12');
    });

    it('没有结果时计数为空串', 0, () => {
      expect(searchCounterText(0, 0)).assertEqual('');
    });
  });
}
