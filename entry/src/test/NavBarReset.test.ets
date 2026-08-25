import { describe, expect, it } from '@ohos/hypium';
import { navBarVisibleOnAppear, navBarVisibleOnChange } from '../main/ets/util/navBarReset';

export default function navBarResetTest() {
  describe('navBarReset', () => {
    it('分栏下恒可见', 0, () => {
      // 平板左栏常驻，栈里有没有东西都不影响 navBar。
      expect(navBarVisibleOnAppear(true, 0)).assertTrue();
      expect(navBarVisibleOnAppear(true, 3)).assertTrue();
    });

    it('单栏栈空 → 可见', 0, () => {
      // 这一支是复位存在的理由：上一轮留下的 false 必须被清掉，否则 dock 永久
      // 藏着——onNavBarStateChange 只在变化时触发，不会补发。
      expect(navBarVisibleOnAppear(false, 0)).assertTrue();
    });

    it('单栏栈非空 → 不可见', 0, () => {
      // **这一条是这次修的 bug。** 原来无条件写 true，前提是"刚建好时栈必然是
      // 空的"。整页 router 跳转（应用内浏览器）回来时那棵树会重建，而页签栈还
      // 压着聊天详情——于是 dock 被放出来，和输入框叠在一起。
      expect(navBarVisibleOnAppear(false, 1)).assertFalse();
      expect(navBarVisibleOnAppear(false, 5)).assertFalse();
    });

    it('负数深度按空栈处理', 0, () => {
      // 不该出现，但栈的实现换了之后 size() 的语义未必还一样；宁可显示 dock
      // 也不要让它永久消失——那个故障用户没法自己恢复。
      expect(navBarVisibleOnAppear(false, -1)).assertTrue();
    });
  });

  describe('navBarVisibleOnChange', () => {
    it('浏览器退掉后补发的 visible=true，单栏且栈非空时不算数', 0, (): void => {
      expect(navBarVisibleOnChange(true, false, 1)).assertFalse();
      expect(navBarVisibleOnChange(true, false, 0)).assertTrue();
      expect(navBarVisibleOnChange(false, false, 0)).assertFalse();
    });
    it('分栏下照单全收', 0, (): void => {
      expect(navBarVisibleOnChange(true, true, 3)).assertTrue();
      expect(navBarVisibleOnChange(false, true, 3)).assertFalse();
    });
  });
}
