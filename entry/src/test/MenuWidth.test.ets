import { describe, expect, it } from '@ohos/hypium';
import {
  MENU_MAX_W, MENU_MIN_W, MENU_ROW_CHROME, MENU_TRAILING_CHEVRON, menuWidthFor, textWidth
} from '../main/ets/util/menuWidth';

export default function menuWidthTest() {
  describe('menuWidth', () => {
    // 这条钉的是用户实测的那个回归：六个中文字 + 尾部箭头，176 放不下。
    it('六个中文字带箭头时必须比原来的 176 宽', 0, () => {
      const w: number = menuWidthFor(['添加到文件夹', '清空聊天记录'], true);
      expect(w > MENU_MIN_W).assertTrue();
      // 6 字 ×16 + 固定开销 + 箭头
      expect(w).assertEqual(6 * 16 + MENU_ROW_CHROME + MENU_TRAILING_CHEVRON);
    });

    it('短标签退回下限，短菜单不会窄成一条', 0, () => {
      expect(menuWidthFor(['搜索', '静音'], false)).assertEqual(MENU_MIN_W);
    });

    it('超长标签夹在上限，不把菜单撑到整屏', 0, () => {
      const w: number = menuWidthFor(['Updating notifications for this conversation'], false);
      expect(w).assertEqual(MENU_MAX_W);
    });

    it('全角比半角宽：同样字数的中文更宽', 0, () => {
      expect(textWidth('文件夹') > textWidth('abc')).assertTrue();
    });

    // 用一条**两边都不会被下限夹住**的标签，否则差值会被 clamp 吃掉
    // （'添加到文件夹' 不带箭头时只有 161，低于下限 176，差值就不是 28 了）。
    it('没有箭头时不留箭头的位置', 0, () => {
      const long: string = '正在更新通知设置';
      const withArrow: number = menuWidthFor([long], true);
      const without: number = menuWidthFor([long], false);
      expect(without > MENU_MIN_W).assertTrue();
      expect(withArrow - without).assertEqual(MENU_TRAILING_CHEVRON);
    });

    it('空列表也给得出下限，不返回 NaN', 0, () => {
      expect(menuWidthFor([], false)).assertEqual(MENU_MIN_W);
    });
  });
}
