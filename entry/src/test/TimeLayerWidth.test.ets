import { describe, expect, it } from '@ohos/hypium';
import { SiblingLabelWidths, timeLayerMinWidth } from '../main/ets/util/timeLayerWidth';

function labels(o: Partial<SiblingLabelWidths>): SiblingLabelWidths {
  return {
    forwardShown: o.forwardShown ?? false, forwardW: o.forwardW ?? 0,
    senderShown: o.senderShown ?? false, senderW: o.senderW ?? 0,
    commentsShown: o.commentsShown ?? false, commentsW: o.commentsW ?? 0
  };
}

export default function timeLayerWidthTest() {
  describe('timeLayerWidth', () => {
    it('显示着的最宽标签决定最小宽度', 0, () => {
      expect(timeLayerMinWidth(300, labels({
        forwardShown: true, forwardW: 120, senderShown: true, senderW: 210, commentsShown: true, commentsW: 90
      }))).assertEqual(210);
    });
    // 回归：复用后名字行和上一条一样宽时 onAreaChange 不会再来，旧值必须仍然可用。
    it('不显示的标签即使留着旧宽度也不参与', 0, () => {
      expect(timeLayerMinWidth(300, labels({ forwardShown: false, forwardW: 260, senderShown: true, senderW: 150 })))
        .assertEqual(150);
      expect(timeLayerMinWidth(300, labels({ senderShown: false, senderW: 260 }))).assertEqual(0);
    });
    it('全都不显示或全是 0 就不兜', 0, () => {
      expect(timeLayerMinWidth(300, labels({}))).assertEqual(0);
      expect(timeLayerMinWidth(300, labels({ senderShown: true, senderW: 0 }))).assertEqual(0);
    });
    it('封顶在正文上限，量到偏大也撑不出去', 0, () => {
      expect(timeLayerMinWidth(300, labels({ senderShown: true, senderW: 999 }))).assertEqual(300);
      expect(timeLayerMinWidth(0, labels({ senderShown: true, senderW: 120 }))).assertEqual(0);
    });
  });
}
