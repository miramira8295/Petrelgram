import { describe, expect, it } from '@ohos/hypium';
import {
  ACCOUNT_POPUP_W, ACCOUNT_ROW_H, PopupRect, accountPopupRect, accountRowAt
} from '../main/ets/util/accountSwitchLayout';

export default function accountSwitchLayoutTest() {
  describe('accountSwitchLayout', () => {
    it('底边贴在按下点上方，横向以按下点为中心', 0, () => {
      const r: PopupRect = accountPopupRect(200, 700, 400, 800, 3);
      expect(r.h).assertEqual(3 * ACCOUNT_ROW_H);
      expect(r.y + r.h).assertEqual(700 - 8);
      expect(r.x + r.w / 2).assertEqual(200);
      expect(r.w).assertEqual(ACCOUNT_POPUP_W);
      expect(r.scrolls).assertFalse();
    });
    it('按在屏幕右下角时整体钳回屏幕内', 0, () => {
      const r: PopupRect = accountPopupRect(395, 795, 400, 800, 2);
      expect(r.x + r.w).assertEqual(400 - 12);
      expect(r.y + r.h <= 800 - 12).assertTrue();
      expect(r.x >= 12).assertTrue();
    });
    it('按得太靠上时不会越过顶边', 0, () => {
      const r: PopupRect = accountPopupRect(100, 20, 400, 800, 4);
      expect(r.y).assertEqual(12);
    });
    it('行数超过屏高六成就限高并标记要滚', 0, () => {
      const r: PopupRect = accountPopupRect(200, 700, 400, 500, 20);
      expect(r.h).assertEqual(Math.floor(500 * 0.6));
      expect(r.scrolls).assertTrue();
    });
    it('坐标落在第几行；弹窗外是 -1', 0, () => {
      const r: PopupRect = accountPopupRect(200, 700, 400, 800, 3);
      expect(accountRowAt(r, 3, r.x + 10, r.y + 1)).assertEqual(0);
      expect(accountRowAt(r, 3, r.x + 10, r.y + ACCOUNT_ROW_H * 2 + 5)).assertEqual(2);
      expect(accountRowAt(r, 3, r.x - 1, r.y + 10)).assertEqual(-1);
      expect(accountRowAt(r, 3, r.x + 10, r.y + r.h)).assertEqual(-1);
      expect(accountRowAt(r, 0, r.x + 10, r.y + 10)).assertEqual(-1);
    });
    it('内容滚过之后按滚动量折算行号', 0, () => {
      const r: PopupRect = accountPopupRect(200, 700, 400, 500, 20);
      expect(accountRowAt(r, 20, r.x + 10, r.y + 1, ACCOUNT_ROW_H, ACCOUNT_ROW_H * 5)).assertEqual(5);
    });
  });
}
