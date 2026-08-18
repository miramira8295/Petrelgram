import { describe, expect, it } from '@ohos/hypium';
import {
  GESTURE_CLASSIC, GESTURE_TAP_FIRST, MessageGesturePolicy, messageGesturePolicy
} from '../main/ets/util/messageGestures';

// 消息气泡上只有两个手势可分配：单击和长按。两套方案换的就是它们的分工。
//
// 多选态不在这里管——ChatPage 的行外层在多选时把 hitTestBehavior 设成 Block，
// 所有点击都被行接走用于勾选，气泡根本收不到。
export default function messageGesturesTest() {
  describe('messageGestures', () => {
    it('classic keeps the menu on long press', 0, () => {
      const p: MessageGesturePolicy = messageGesturePolicy(GESTURE_CLASSIC);
      expect(p.longPressOpensMenu).assertTrue();
      expect(p.tapOpensMenu).assertFalse();
      expect(p.longPressSelects).assertFalse();
    });

    it('tap-first moves the menu to a single tap and long press to select', 0, () => {
      const p: MessageGesturePolicy = messageGesturePolicy(GESTURE_TAP_FIRST);
      expect(p.tapOpensMenu).assertTrue();
      expect(p.longPressOpensMenu).assertFalse();
      expect(p.longPressSelects).assertTrue();
    });

    // 菜单必须恰好有一个入口。两个都关 = 菜单永远打不开；两个都开 = 长按时
    // 菜单和多选抢同一个手势。
    it('always leaves exactly one way into the menu', 0, () => {
      for (const scheme of [GESTURE_CLASSIC, GESTURE_TAP_FIRST]) {
        const p: MessageGesturePolicy = messageGesturePolicy(scheme);
        expect(p.tapOpensMenu !== p.longPressOpensMenu).assertTrue();
      }
    });

    // 长按不能同时开菜单又进多选。
    it('never gives long press two jobs', 0, () => {
      for (const scheme of [GESTURE_CLASSIC, GESTURE_TAP_FIRST]) {
        const p: MessageGesturePolicy = messageGesturePolicy(scheme);
        expect(p.longPressOpensMenu && p.longPressSelects).assertFalse();
      }
    });

    // 存量用户升级上来时读到的是空串；将来加了新方案、又装回旧版本时读到的
    // 是不认识的值。两种都必须退回老交互，而不是把人扔进一个没有菜单的状态。
    it('falls back to classic for an unknown or empty value', 0, () => {
      for (const bad of ['', 'nope', 'TAPFIRST', ' tapFirst']) {
        const p: MessageGesturePolicy = messageGesturePolicy(bad);
        expect(p.longPressOpensMenu).assertTrue();
        expect(p.tapOpensMenu).assertFalse();
      }
    });
  });
}
