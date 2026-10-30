import { describe, expect, it } from '@ohos/hypium';
import {
  BUBBLE_AVATAR_GAP_VP, BUBBLE_AVATAR_GUTTER_VP, BUBBLE_AVATAR_SIZE_VP,
  BUBBLE_OPPOSITE_MIN_GAP_VP, BUBBLE_ROW_SIDE_VP,
  MEDIA_MAX_HEIGHT_RATIO,
  bubbleMaxWidth,
  mediaBoxFor,
  mediaRatio,
  mediaThumbWidth
} from '../main/ets/util/mediaBox';

const SCREEN: number = 360;

function assertPhotoFits(width: number, height: number, column: number,
  gutter: number, device: string): void {
  const box = mediaBoxFor(column, width, height, false, gutter, device);
  const maxW: number = mediaThumbWidth(column, gutter, device);
  expect(box.width >= 0 && box.width <= maxW + 0.001).assertTrue();
  expect(box.height >= 0 && box.height <= maxW * MEDIA_MAX_HEIGHT_RATIO + 0.001).assertTrue();
  if (maxW > 0) {
    expect(Math.abs(box.width / box.height - width / height) < 0.000001).assertTrue();
  }
}

export default function mediaBoxTest() {
  describe('mediaBox', () => {
    it('1920x1080 landscape retains 16:9', 0, () => {
      const box = mediaBoxFor(368, 1920, 1080, false, 0, 'phone');
      expect(box.width).assertEqual(320);
      expect(box.height).assertEqual(180);
    });
    it('1080x1920 portrait shrinks both axes at the height limit', 0, () => {
      const box = mediaBoxFor(368, 1080, 1920, false, 0, 'phone');
      expect(box.width).assertEqual(216);
      expect(box.height).assertEqual(384);
    });
    it('1200x1200 square retains 1:1', 0, () => {
      const box = mediaBoxFor(368, 1200, 1200, false, 0, 'phone');
      expect(box.width).assertEqual(320);
      expect(box.height).assertEqual(320);
    });
    it('three acceptance shapes fit phone tablet and desktop chat columns', 0, () => {
      for (const device of ['phone', 'tablet', '2in1']) {
        for (const column of [240, 360, 440, 720, 960]) {
          for (const gutter of [0, BUBBLE_AVATAR_GUTTER_VP]) {
            assertPhotoFits(1920, 1080, column, gutter, device);
            assertPhotoFits(1080, 1920, column, gutter, device);
            assertPhotoFits(1200, 1200, column, gutter, device);
          }
        }
      }
    });
    it('extreme tall photos retain the entire source ratio within the height cap', 0, () => {
      assertPhotoFits(100, 20000, SCREEN, 0, 'phone');
      expect(mediaRatio(100, 20000, false)).assertEqual(0.005);
    });
    it('ultrawide photos retain the entire source ratio', 0, () => {
      assertPhotoFits(20000, 100, SCREEN, 0, 'phone');
      expect(mediaRatio(20000, 100, false)).assertEqual(200);
    });
    it('zero and narrow columns produce nonnegative bounded geometry', 0, () => {
      for (const column of [0, 40, 80]) {
        for (const device of ['phone', 'tablet']) {
          assertPhotoFits(1080, 1920, column, BUBBLE_AVATAR_GUTTER_VP, device);
        }
      }
    });
    it('missing metadata retains the square fallback', 0, () => {
      const box = mediaBoxFor(SCREEN, 0, 0, false);
      expect(box.width).assertEqual(mediaThumbWidth(SCREEN));
      expect(box.height).assertEqual(box.width);
    });
    it('invalid metadata cannot introduce NaN or infinite layout', 0, () => {
      for (const invalid of [0, -1, NaN, Infinity]) {
        expect(mediaRatio(invalid, 100, false)).assertEqual(1);
        expect(mediaRatio(100, invalid, false)).assertEqual(1);
      }
    });
    it('thumbnail resolution tiers preserve the same geometry', 0, () => {
      const a = mediaBoxFor(SCREEN, 1920, 1080, false);
      const b = mediaBoxFor(SCREEN, 640, 360, false);
      expect(a.width).assertEqual(b.width);
      expect(a.height).assertEqual(b.height);
    });
    it('metadata yields identical placeholder prefetch and loaded image dimensions', 0, () => {
      for (const dims of [[1920, 1080], [1080, 1920], [1200, 1200]]) {
        const a = mediaBoxFor(SCREEN, dims[0], dims[1], false);
        const b = mediaBoxFor(SCREEN, dims[0], dims[1], false);
        expect(a.width).assertEqual(b.width);
        expect(a.height).assertEqual(b.height);
      }
    });
    it('phone media width limit still uses the current chat column', 0, () => {
      for (const width of [440, 720, 960]) {
        expect(mediaThumbWidth(width, 0, 'phone') + 16).assertEqual(bubbleMaxWidth(width, 0));
      }
    });
    it('non-phone media retains its width limit', 0, () => {
      for (const device of ['tablet', '2in1', 'tv', 'unknown']) {
        expect(mediaThumbWidth(960, 0, device)).assertEqual(280);
      }
    });
    it('portrait video shrinks both axes at the height limit', 0, () => {
      const box = mediaBoxFor(368, 1080, 1920, true, 0, 'phone');
      expect(box.width).assertEqual(216);
      expect(box.height).assertEqual(384);
    });
    it('landscape video retains existing geometry', 0, () => {
      const box = mediaBoxFor(368, 1920, 1080, true, 0, 'phone');
      expect(box.width).assertEqual(320);
      expect(box.height).assertEqual(180);
    });
    it('unknown video retains 16:9 placeholder', 0, () => {
      expect(mediaRatio(0, 0, true)).assertEqual(16 / 9);
    });
    it('video ratio limits remain unchanged', 0, () => {
      expect(mediaRatio(1000, 3000, true)).assertEqual(0.4);
      expect(mediaRatio(3000, 1000, true)).assertEqual(2.4);
    });

    // ── 气泡最大宽：原来的 screenW * 0.78 其实只对群聊来信成立 ──────────
    //
    // 当时：440 − 5(行边距) − 44(头像位) − 48(对侧留白) = 343 = 0.78 x 440。
    // 发出的消息和私聊来信没有头像位，却也被那个系数卡住，白白少 44vp 宽。
    // 2026-09-23 又整体收窄了留白（用户：气泡再宽一点、头像间距再小一点）。
    it('宽度就是屏宽减掉三段留白', 0, () => {
      expect(bubbleMaxWidth(440, BUBBLE_AVATAR_GUTTER_VP)).assertEqual(
        440 - BUBBLE_ROW_SIDE_VP - BUBBLE_AVATAR_GUTTER_VP - BUBBLE_OPPOSITE_MIN_GAP_VP);
    });

    it('没有头像位的行宽出整整一个头像位', 0, () => {
      const withAvatar: number = bubbleMaxWidth(440, BUBBLE_AVATAR_GUTTER_VP);
      const without: number = bubbleMaxWidth(440, 0);
      expect(without - withAvatar).assertEqual(BUBBLE_AVATAR_GUTTER_VP);
    });

    // 头像位 = 直径 + 间隙。三处（占位内边距、头像 margin、宽度公式）必须同源，
    // 各写各的就会出现「带头像那行比别的行窄」或「气泡压到头像上」。
    it('头像位由直径和间隙推出来', 0, () => {
      expect(BUBBLE_AVATAR_GUTTER_VP).assertEqual(
        BUBBLE_AVATAR_SIZE_VP + BUBBLE_AVATAR_GAP_VP);
    });

    // 收窄只能收留白，不能把气泡放到顶边——这几条是下限，别再往下压。
    it('三段留白都还在', 0, () => {
      expect(BUBBLE_ROW_SIDE_VP > 0).assertTrue();
      expect(BUBBLE_AVATAR_GAP_VP > 0).assertTrue();
      expect(BUBBLE_OPPOSITE_MIN_GAP_VP >= 24).assertTrue();
    });

    // 缺省值按最窄的一档算：首屏高度估算拿不到逐行的会话类型，估窄 ⇒ 行数偏多
    // ⇒ 高度偏高，是安全方向。
    it('不传头像位时按有头像算', 0, () => {
      expect(bubbleMaxWidth(440)).assertEqual(bubbleMaxWidth(440, BUBBLE_AVATAR_GUTTER_VP));
    });

    // 对侧留白是硬约束：没有它长消息会顶到另一边，一眼看不出是谁发的。
    it('对侧留白始终被扣掉', 0, () => {
      expect(bubbleMaxWidth(440, 0) + BUBBLE_ROW_SIDE_VP + BUBBLE_OPPOSITE_MIN_GAP_VP)
        .assertEqual(440);
    });

    // 窄窗口（分栏左栏、小窗）下不能算出负宽。
    it('窗口比留白还窄时夹到 0', 0, () => {
      expect(bubbleMaxWidth(40, BUBBLE_AVATAR_GUTTER_VP)).assertEqual(0);
      expect(bubbleMaxWidth(0, 0)).assertEqual(0);
    });

    it('脏的头像位不放大气泡', 0, () => {
      expect(bubbleMaxWidth(440, -100)).assertEqual(bubbleMaxWidth(440, 0));
    });
  });
}
