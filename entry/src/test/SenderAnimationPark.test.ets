import { describe, expect, it } from '@ohos/hypium';
import {
  parkSenderAnimations, resetSenderAnimationPark, senderAnimationsParked,
  subscribeSenderAnimationPark
} from '../main/ets/util/senderAnimationPark';

// 退出会话那一帧的修复（2026-09-18）。真机 trace：退场最差帧 47–57ms，落在转场
// 结束那一刻，SenderAnimatedLayer 是单节点销毁成本的冠军（1.02ms/个 × 17）。
// 这道闸让播放器在转场的 600ms 里就被卸掉。

export default function senderAnimationParkTest() {
  describe('SenderAnimationPark', () => {
    it('默认没停车', 0, (): void => {
      resetSenderAnimationPark();
      expect(senderAnimationsParked()).assertFalse();
    });

    // 订阅要立刻回灌当前值：转场**途中**才挂上来的那些行，不能默认"没停车"
    // ——否则它们会在退场半路又去建一个播放器。
    it('订阅时立刻收到当前值', 0, (): void => {
      resetSenderAnimationPark();
      parkSenderAnimations(true);
      let seen: number = -1;
      const off: () => void = subscribeSenderAnimationPark((parked: boolean): void => {
        seen = parked ? 1 : 0;
      });
      expect(seen).assertEqual(1);
      off();
    });

    it('翻面时广播给所有订阅者', 0, (): void => {
      resetSenderAnimationPark();
      let a: number = 0;
      let b: number = 0;
      const offA: () => void = subscribeSenderAnimationPark((p: boolean): void => { a += p ? 1 : 0; });
      const offB: () => void = subscribeSenderAnimationPark((p: boolean): void => { b += p ? 1 : 0; });
      parkSenderAnimations(true);
      expect(a).assertEqual(1);
      expect(b).assertEqual(1);
      offA();
      offB();
    });

    // 同值不广播：退场路径上 willHide 可能连来两次，让十几个头像层各自白跑一遍
    // evaluate() 正是这次要省掉的开销。
    it('同值不再广播', 0, (): void => {
      resetSenderAnimationPark();
      let n: number = 0;
      const off: () => void = subscribeSenderAnimationPark((): void => { n++; });
      expect(n).assertEqual(1);   // 订阅时那一次
      parkSenderAnimations(true);
      parkSenderAnimations(true);
      expect(n).assertEqual(2);
      off();
    });

    it('退订之后不再收到', 0, (): void => {
      resetSenderAnimationPark();
      let n: number = 0;
      const off: () => void = subscribeSenderAnimationPark((): void => { n++; });
      off();
      parkSenderAnimations(true);
      expect(n).assertEqual(1);
    });
  });
}
