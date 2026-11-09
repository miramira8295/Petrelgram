import { describe, expect, it } from '@ohos/hypium';
import { MENU_PREVIEW_MIN_WINDOW_H, menuPreviewCompact } from '../main/ets/util/menuPreview';

export default function menuPreviewTest() {
  describe('menuPreviewCompact', () => {
    it('键盘起来了就不带预览——窗口已被压矮，带预览的菜单弹不出来（issue #114）', 0, (): void => {
      expect(menuPreviewCompact(300, 780)).assertTrue();
    });

    it('窗口本身矮（悬浮小窗 / 分屏下半截）也不带', 0, (): void => {
      expect(menuPreviewCompact(0, MENU_PREVIEW_MIN_WINDOW_H - 1)).assertTrue();
    });

    it('正常竖屏、键盘收着才带预览', 0, (): void => {
      expect(menuPreviewCompact(0, 780)).assertFalse();
      expect(menuPreviewCompact(0, MENU_PREVIEW_MIN_WINDOW_H)).assertFalse();
    });
  });
}
