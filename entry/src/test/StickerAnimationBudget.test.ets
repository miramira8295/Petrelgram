import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_ANIMATION_SLOTS, OTHER_ANIMATION_SLOTS, PANEL_ANIMATION_SLOTS, stickerAnimationSlots
} from '../main/ets/util/stickerAnimationBudget';
import { AnimationSlotPool } from '../main/ets/util/animationSlotPool';

// 贴纸动画名额按区域分池：抽屉、会话、其余互不挤占（2026-09-15）。

function drain(pool: AnimationSlotPool): number {
  let n = 0;
  while (pool.tryAcquire()) {
    n++;
  }
  for (let i = 0; i < n; i++) {
    pool.release();
  }
  return n;
}

export default function stickerAnimationBudgetTest() {
  describe('stickerAnimationBudget', () => {
    it('三个区域各自的容量', 0, () => {
      expect(drain(stickerAnimationSlots(false, true))).assertEqual(PANEL_ANIMATION_SLOTS);
      expect(drain(stickerAnimationSlots(true, false))).assertEqual(CHAT_ANIMATION_SLOTS);
      expect(drain(stickerAnimationSlots(false, false))).assertEqual(OTHER_ANIMATION_SLOTS);
    });

    it('抽屉占满不影响会话', 0, () => {
      const panel = stickerAnimationSlots(false, true);
      let taken = 0;
      while (panel.tryAcquire()) {
        taken++;
      }
      expect(stickerAnimationSlots(true, false).tryAcquire()).assertTrue();
      stickerAnimationSlots(true, false).release();
      for (let i = 0; i < taken; i++) {
        panel.release();
      }
      expect(panel.liveCount()).assertEqual(0);
    });

    it('同一区域取到的是同一个池', 0, () => {
      expect(stickerAnimationSlots(false, true) === stickerAnimationSlots(true, true)).assertTrue();
      expect(stickerAnimationSlots(true, false) === stickerAnimationSlots(true, false)).assertTrue();
    });
  });
}
