import { describe, expect, it } from '@ohos/hypium';
import {
  animationDurationFor, persistentAnimationDurationFor, scrollActiveNow, setScrollActive
} from '../main/ets/util/scrollEffects';

export default function scrollEffectsTest() {
  describe('animationDurationFor', () => {
    it('设置关掉时一律 0', 0, (): void => {
      expect(animationDurationFor(false, false, 150)).assertEqual(0);
      expect(animationDurationFor(false, true, 150)).assertEqual(0);
    });
    it('滑动中一律 0，哪怕设置开着', 0, (): void => {
      expect(animationDurationFor(true, true, 150)).assertEqual(0);
    });
    it('设置开着且没在滑动时原样返回', 0, (): void => {
      expect(animationDurationFor(true, false, 150)).assertEqual(150);
      expect(animationDurationFor(true, false, 0)).assertEqual(0);
    });
    it('setScrollActive 往返：置真、置假都能读回', 0, (): void => {
      setScrollActive(true);
      expect(scrollActiveNow()).assertTrue();
      setScrollActive(false);
      expect(scrollActiveNow()).assertFalse();
    });
  });

  // 长期视觉效果的时长决策。目前的调用方是 MessageBubble 里行内链接药丸的
  // 循环忙态与按下过渡（两支气泡的根节点已经不挂常驻动画，不再调用它）。
  // 这里只断言开关合取这一件事；动画是否真的被隔离在列表刷新之外，属于 ArkUI
  // 运行时行为，单元测试证明不了，只能由真机 trace 验证。
  describe('persistentAnimationDurationFor', () => {
    it('三个开关全开时原样返回', 0, (): void => {
      expect(persistentAnimationDurationFor(true, true, false, 110)).assertEqual(110);
      expect(persistentAnimationDurationFor(true, true, false, 0)).assertEqual(0);
    });
    it('聊天特效关掉时为 0', 0, (): void => {
      expect(persistentAnimationDurationFor(false, true, false, 110)).assertEqual(0);
    });
    it('消息特效关掉时为 0', 0, (): void => {
      expect(persistentAnimationDurationFor(true, false, false, 110)).assertEqual(0);
    });
    it('省电模式下为 0，哪怕两个开关都开着', 0, (): void => {
      expect(persistentAnimationDurationFor(true, true, true, 110)).assertEqual(0);
      expect(persistentAnimationDurationFor(false, false, true, 110)).assertEqual(0);
    });
    // 刻意不吃滑动门控：这类动画的参数在 build 之后才被消费，滑动中取 0 会让
    // 循环效果在滑动停下后永久静止。
    it('滑动态不影响长期效果时长', 0, (): void => {
      setScrollActive(true);
      expect(persistentAnimationDurationFor(true, true, false, 110)).assertEqual(110);
      setScrollActive(false);
      expect(persistentAnimationDurationFor(true, true, false, 110)).assertEqual(110);
    });
  });
}
