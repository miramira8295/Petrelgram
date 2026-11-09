import { describe, it, expect } from '@ohos/hypium';
import { ComposerLayoutMeasurement, composerMeasuredHeight } from '../main/ets/util/composerLayout';

function sample(text: string, height: number = 51, lines: number = 2): ComposerLayoutMeasurement {
  return { text: text, widthVp: 220, probeLineVp: 22, contentHeightVp: height, lines: lines };
}

export default function composerLayoutTest() {
  describe('ComposerLayout', () => {
    const original: string = '啊啊啊啊啊啊啊啊啊啊啊啊啊啊啊🤣';

    it('两行混排使用真实高度而非两倍估算行高', 0, () => {
      expect(composerMeasuredHeight(sample(original), original, 220, 22, 4)).assertEqual(51);
    });
    it('无表情时同样纠正系统字体的高度差异', 0, () => {
      const text: string = '啊'.repeat(16);
      expect(composerMeasuredHeight(sample(text, 54), text, 220, 22, 4)).assertEqual(54);
    });
    it('矩形尚为零时真实行数仍可补偿漏行', 0, () => {
      expect(composerMeasuredHeight(sample(original, 0, 3), original, 220, 22, 4)).assertEqual(66);
    });
    it('超过四行仍限制高度而非展开整个长草稿', 0, () => {
      expect(composerMeasuredHeight(sample(original, 200, 8), original, 220, 22, 4)).assertEqual(100);
    });
    it('删除或清空后不沿用旧文本高度', 0, () => {
      expect(composerMeasuredHeight(sample(original), '啊', 220, 22, 4)).assertEqual(0);
      expect(composerMeasuredHeight(sample(original), '', 220, 22, 4)).assertEqual(0);
      expect(composerMeasuredHeight(undefined, original, 220, 22, 4)).assertEqual(0);
    });
    it('宽度改变后拒绝旧折行结果并容忍小数抖动', 0, () => {
      expect(composerMeasuredHeight(sample(original), original, 180, 22, 4)).assertEqual(0);
      expect(composerMeasuredHeight(sample(original), original, 220.2, 22, 4)).assertEqual(51);
    });
    it('字号测量变化后拒绝旧高度', 0, () => {
      expect(composerMeasuredHeight(sample(original), original, 220, 28, 4)).assertEqual(0);
    });
    it('无效控制器几何信息不会污染布局', 0, () => {
      expect(composerMeasuredHeight(sample(original, NaN), original, 220, 22, 4)).assertEqual(0);
      expect(composerMeasuredHeight(sample(original, -1), original, 220, 22, 4)).assertEqual(0);
      expect(composerMeasuredHeight(sample(original, 51, 0), original, 220, 22, 4)).assertEqual(0);
      expect(composerMeasuredHeight(sample(original), original, 0, 22, 4)).assertEqual(0);
    });
  });
}
