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

  // 按压反馈的时长决策。完整气泡（MessageBubble）和轻量气泡
  // （LightweightPlainTextBubble）的 persistentEffectDuration() 都只是转发到这里，
  // 所以这组断言同时覆盖两支——以前两支各写一份表达式，改一支漏一支没人发现。
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
    // 刻意不吃滑动门控：按下态的参数在 build 之后才被消费，滑动中取 0 会让
    // 滑动停下后按气泡没有过渡。滑动期间的数据刷新之所以不再产生动画，靠的是
    // 属性链上的作用域隔离（气泡的几何属性排在 .animation() 之后），不是靠这里
    // 把时长压成 0。
    it('滑动态不影响按压时长', 0, (): void => {
      setScrollActive(true);
      expect(persistentAnimationDurationFor(true, true, false, 110)).assertEqual(110);
      setScrollActive(false);
      expect(persistentAnimationDurationFor(true, true, false, 110)).assertEqual(110);
    });
  });
}
