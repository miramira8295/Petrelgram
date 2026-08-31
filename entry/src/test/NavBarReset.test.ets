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

    // 【Pad 版 dock 偶尔不回收】窗口跨过分栏断点、而栈里还压着详情页，是这个
    // 标志唯一会「不通知就变值」的场合：分栏那侧恒为 true，单栏那侧因为栈非空
    // 变成 false。此前只有框架的 onNavBarStateChange 会写它，回调没来（或它读
    // 到的窗口尺寸还没刷新）标志就停在 true，dock 浮在会话详情上不收。
    // 三个可分栏的页签现在都在窗口尺寸变化时按这个判据自己重算一次。
    it('跨过分栏断点时，同一个栈深度会翻出不同的结论', 0, () => {
      expect(navBarVisibleOnAppear(true, 1)).assertTrue();   // 平板分栏：左栏常驻
      expect(navBarVisibleOnAppear(false, 1)).assertFalse(); // 缩成单栏：navBar 被盖住
      // 栈空时两侧同为 true——那时窗口怎么变都不该动 dock。
      expect(navBarVisibleOnAppear(true, 0)).assertTrue();
      expect(navBarVisibleOnAppear(false, 0)).assertTrue();
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
      // 页签切到后台会临时报告 false；栈空的根页仍应让 dock 保持可见。
      expect(navBarVisibleOnChange(false, false, 0)).assertTrue();
    });
    it('分栏下照单全收', 0, (): void => {
      expect(navBarVisibleOnChange(true, true, 3)).assertTrue();
      // 分栏左侧 navBar 常驻，后台页签的临时 false 不能隐藏 dock。
      expect(navBarVisibleOnChange(false, true, 3)).assertTrue();
    });
  });
}
