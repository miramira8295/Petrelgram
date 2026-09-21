import { describe, it, expect } from '@ohos/hypium';
import { thumbBackdropColor } from '../main/ets/util/thumbBackdrop';

export default function thumbBackdropTest() {
  describe('ThumbBackdrop', () => {
    it('视频与图片是两个不同的底色', 0, () => {
      expect(thumbBackdropColor(true) === thumbBackdropColor(false)).assertFalse();
    });

    // 这两个值必须和 AlbumCellView.placeholderWithFile /
    // MessageBubble.singleMediaPlaceholder 画的占位底色**逐位一致**：不一致就会
    // 在"撤占位 → 位图落地"那一帧看到跳色，正是 2026-09-20 要消掉的那个闪。
    // 改这两个值前先改那两处占位。
    it('取值钉住：视频 #AEB6C0、图片 #D7DCE2', 0, () => {
      expect(thumbBackdropColor(true)).assertEqual('#AEB6C0');
      expect(thumbBackdropColor(false)).assertEqual('#D7DCE2');
    });

    it('是不透明的 6 位十六进制——半透明会把后面透出来，等于没垫', 0, () => {
      const video: string = thumbBackdropColor(true);
      const photo: string = thumbBackdropColor(false);
      expect(video.length).assertEqual(7);
      expect(photo.length).assertEqual(7);
      expect(video.startsWith('#')).assertTrue();
      expect(photo.startsWith('#')).assertTrue();
    });

    // 空串在 CachedImage 里表示"不垫"，所以这个函数永远不能返回空串——
    // 返回空串等于静默关掉整条修复。
    it('永远不返回空串（空串在 CachedImage 里意为不垫底色）', 0, () => {
      expect(thumbBackdropColor(true) !== '').assertTrue();
      expect(thumbBackdropColor(false) !== '').assertTrue();
    });
  });
}
