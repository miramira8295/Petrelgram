import { describe, expect, it } from '@ohos/hypium';
import { SEND_THUMB_MAX_EDGE, SendThumb, thumbTargetSize } from '../main/ets/util/sendThumb';

export default function SendThumbTest() {
  describe('sendThumb', () => {
    // 这条钉的是一个真实回归：实况的静图 1440x1920 被原样当成
    // inputMessageVideo.thumbnail 发出去，超了内联缩略图的长边约定，
    // 接收端与本端都拿不到预览图。
    it('竖图：长边缩到 320，比例不变', 0, () => {
      const t: SendThumb = thumbTargetSize(1440, 1920, SEND_THUMB_MAX_EDGE);
      expect(t.height).assertEqual(320);
      expect(t.width).assertEqual(240);
    });

    it('横图：按长边那一侧缩', 0, () => {
      const t: SendThumb = thumbTargetSize(1920, 1080, 320);
      expect(t.width).assertEqual(320);
      expect(t.height).assertEqual(180);
    });

    it('已经够小的不放大', 0, () => {
      const t: SendThumb = thumbTargetSize(200, 100, 320);
      expect(t.width).assertEqual(200);
      expect(t.height).assertEqual(100);
    });

    it('正方形', 0, () => {
      const t: SendThumb = thumbTargetSize(1000, 1000, 320);
      expect(t.width).assertEqual(320);
      expect(t.height).assertEqual(320);
    });

    // 极端长条：短边等比缩下来会归零，解码器不收 0。
    it('极端长条图：短边保底 1px', 0, () => {
      const t: SendThumb = thumbTargetSize(10000, 5, 320);
      expect(t.width).assertEqual(320);
      expect(t.height).assertEqual(1);
    });

    it('非法入参一律给 0，调用方按"没有封面"处理', 0, () => {
      expect(thumbTargetSize(0, 100, 320).width).assertEqual(0);
      expect(thumbTargetSize(100, 0, 320).width).assertEqual(0);
      expect(thumbTargetSize(100, 100, 0).width).assertEqual(0);
      expect(thumbTargetSize(-1, -1, 320).height).assertEqual(0);
    });
  });
}
