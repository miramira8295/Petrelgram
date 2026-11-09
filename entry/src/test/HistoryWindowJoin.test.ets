import { describe, it, expect } from '@ohos/hypium';
import {
  WINDOW_JOIN_TOLERANCE, historyPageDetached, messagesBetween, windowHasUnsent
} from '../main/ets/util/historyWindowJoin';

const STEP: number = 1048576;

function id(n: number): number {
  return n * STEP;
}

export default function historyWindowJoinTest() {
  describe('HistoryWindowJoin', () => {
    it('隔了多少条：相邻为 0，中间空一条为 1', 0, () => {
      expect(messagesBetween(id(10), id(11), STEP)).assertEqual(0);
      expect(messagesBetween(id(10), id(12), STEP)).assertEqual(1);
      expect(messagesBetween(id(10), id(1000), STEP)).assertEqual(989);
    });

    it('顺序反了或取不到值时一律当 0，不制造假断层', 0, () => {
      expect(messagesBetween(id(12), id(10), STEP)).assertEqual(0);
      expect(messagesBetween(0, id(10), STEP)).assertEqual(0);
      expect(messagesBetween(id(10), id(12), 0)).assertEqual(0);
    });

    // #213 的真机数据：跳去很早的媒体，新页落在窗口下方，中间隔着 979 条。
    it('新页落在窗口下方且隔着大段历史：判为断开', 0, () => {
      expect(historyPageDetached(
        id(18000), id(19019), id(20045), id(20098), STEP)).assertTrue();
    });

    // 反方向：从很早的位置跳回接近最新处。
    it('新页落在窗口上方且隔着大段历史：同样判为断开', 0, () => {
      expect(historyPageDetached(
        id(20045), id(20098), id(18000), id(19019), STEP)).assertTrue();
    });

    it('有重叠一定接得上', 0, () => {
      expect(historyPageDetached(
        id(100), id(140), id(120), id(180), STEP)).assertFalse();
      // 新页整个落在窗口内部。
      expect(historyPageDetached(
        id(130), id(140), id(100), id(200), STEP)).assertFalse();
    });

    // 删过的消息会在 id 上留正常的小空档，几条之内不算断层。
    it('容差之内照旧合并', 0, () => {
      const gap: number = WINDOW_JOIN_TOLERANCE;
      expect(historyPageDetached(
        id(100), id(200), id(200 + gap + 1), id(300), STEP)).assertFalse();
      expect(historyPageDetached(
        id(100), id(200), id(200 + gap + 2), id(300), STEP)).assertTrue();
    });

    it('取不到边界值时不换窗口', 0, () => {
      expect(historyPageDetached(0, id(19019), id(20045), id(20098), STEP)).assertFalse();
      expect(historyPageDetached(id(18000), id(19019), 0, id(20098), STEP)).assertFalse();
    });

    // 未发送的消息只活在本地，窗口一清就没了。
    it('窗口里有未发送的消息就认出来', 0, () => {
      expect(windowHasUnsent([id(10), id(11)], STEP)).assertFalse();
      expect(windowHasUnsent([id(10), id(11) + 7], STEP)).assertTrue();
      expect(windowHasUnsent([], STEP)).assertFalse();
      expect(windowHasUnsent([id(10)], 0)).assertFalse();
    });
  });
}
