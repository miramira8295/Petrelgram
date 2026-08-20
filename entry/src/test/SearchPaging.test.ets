import { describe, expect, it } from '@ohos/hypium';
import {
  SEARCH_FETCH, SEARCH_JUMP, SEARCH_STAY, SearchStep,
  SEARCH_LABEL_COUNTER, SEARCH_LABEL_HINT, SEARCH_LABEL_NONE,
  canStepNewer, canStepOlder, searchCounterText, searchLabelKind, stepNewer, stepOlder
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

    it('底部标签：有结果显示计数，查空显示空白，没查显示提示', 0, () => {
      expect(searchLabelKind(3, 12, '关键词')).assertEqual(SEARCH_LABEL_COUNTER);
      // 查过了、没结果——显示空白而不是提示语，否则像没反应过。
      expect(searchLabelKind(0, 0, '关键词')).assertEqual(SEARCH_LABEL_NONE);
      // 还没敲东西。
      expect(searchLabelKind(0, 0, '')).assertEqual(SEARCH_LABEL_HINT);
      // 只敲了空格也算没查。
      expect(searchLabelKind(0, 0, '   ')).assertEqual(SEARCH_LABEL_HINT);
      // 总数非 0 但结果还没到货：仍显示提示语，别急着说"没有"。
      expect(searchLabelKind(0, 5, '关键词')).assertEqual(SEARCH_LABEL_HINT);
    });

    it('一条都没到货时 ∧ 不亮——页面原来的式子在这里说亮', 0, () => {
      // total=5 但 loaded 为空：没有锚点可翻，stepOlder 只会 STAY。
      // 旧式子 `idx + 1 < total` 在这里返回 true，靠"箭头挂在 results.length > 0
      // 里"才没出事。
      expect(canStepOlder(0, 0, 5)).assertFalse();
      expect(stepOlder([], 0, 5).action).assertEqual(SEARCH_STAY);
    });

    it('箭头的亮灭必须和 stepOlder / stepNewer 一致', 0, () => {
      // 按钮看着能点、点下去没反应是最难查的那类 bug，这里穷举钉住。
      for (let total = 0; total <= 6; total++) {
        for (let loadedN = 0; loadedN <= total; loadedN++) {
          const loaded: number[] = [];
          for (let k = 0; k < loadedN; k++) {
            loaded.push(100 + k);
          }
          for (let idx = 0; idx < Math.max(1, loadedN); idx++) {
            const olderActs: boolean = stepOlder(loaded, idx, total).action !== SEARCH_STAY;
            expect(olderActs).assertEqual(canStepOlder(loadedN, idx, total));
            const newerActs: boolean = stepNewer(idx).action !== SEARCH_STAY;
            expect(newerActs).assertEqual(canStepNewer(idx));
          }
        }
      }
    });
  });
}
