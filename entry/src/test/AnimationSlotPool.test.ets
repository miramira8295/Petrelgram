import { describe, it, expect } from '@ohos/hypium';
import { AnimationSlotPool } from '../main/ets/util/animationSlotPool';

// 贴纸动画的同时播放名额（起初只给 webm 帧序列）：满了排队，让出时直接转给最后排进来的格子
// （2026-09-15：贴纸面板溢出的格子原来退回 ijkplayer，滑动时崩在 ijk 的回调引用竞态上）。

export default function animationSlotPoolTest() {
  describe('animationSlotPool', () => {
    it('名额内都能拿到，满了拒绝', 0, () => {
      const pool = new AnimationSlotPool(2);
      expect(pool.tryAcquire()).assertTrue();
      expect(pool.tryAcquire()).assertTrue();
      expect(pool.tryAcquire()).assertFalse();
      expect(pool.liveCount()).assertEqual(2);
    });

    it('没人排队时让出就是空出一格', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.tryAcquire();
      pool.release();
      expect(pool.liveCount()).assertEqual(0);
      expect(pool.tryAcquire()).assertTrue();
    });

    it('有人排队时名额直接转给最后排进来的', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.tryAcquire();
      const log: string[] = [];
      pool.wait((): void => { log.push('a'); });
      pool.wait((): void => { log.push('b'); });
      pool.release();
      expect(log.join(',')).assertEqual('b');
      expect(pool.liveCount()).assertEqual(1);
      expect(pool.waitingCount()).assertEqual(1);
      expect(pool.tryAcquire()).assertFalse();
    });

    it('撤销的排队不会被叫到', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.tryAcquire();
      const log: string[] = [];
      const cancel = pool.wait((): void => { log.push('a'); });
      cancel();
      pool.release();
      expect(log.length).assertEqual(0);
      expect(pool.liveCount()).assertEqual(0);
    });

    it('拿到之后再撤销是空操作，不误删别人', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.tryAcquire();
      const log: string[] = [];
      pool.wait((): void => { log.push('a'); });
      const cancelB = pool.wait((): void => { log.push('b'); });
      pool.release();
      cancelB();
      expect(pool.waitingCount()).assertEqual(1);
      pool.release();
      expect(log.join(',')).assertEqual('b,a');
    });

    it('转过来的名额当场让出，接着转给下一个', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.tryAcquire();
      const log: string[] = [];
      pool.wait((): void => { log.push('a'); });
      pool.wait((): void => { log.push('b'); pool.release(); });
      pool.release();
      expect(log.join(',')).assertEqual('b,a');
      expect(pool.liveCount()).assertEqual(1);
      expect(pool.waitingCount()).assertEqual(0);
    });

    it('悄悄让出：空出一格但不叫醒排队的', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.tryAcquire();
      const log: string[] = [];
      pool.wait((): void => { log.push('a'); });
      pool.releaseQuietly();
      expect(log.length).assertEqual(0);
      expect(pool.liveCount()).assertEqual(0);
      expect(pool.waitingCount()).assertEqual(1);
      expect(pool.tryAcquire()).assertTrue();
    });

    it('悄悄让出之后，正常让出仍然转给排队的', 0, () => {
      const pool = new AnimationSlotPool(2);
      pool.tryAcquire();
      pool.tryAcquire();
      const log: string[] = [];
      pool.wait((): void => { log.push('a'); });
      pool.releaseQuietly();
      pool.release();
      expect(log.join(',')).assertEqual('a');
      expect(pool.liveCount()).assertEqual(1);
    });

    it('多让出一次不会变成负数', 0, () => {
      const pool = new AnimationSlotPool(1);
      pool.release();
      expect(pool.liveCount()).assertEqual(0);
      expect(pool.tryAcquire()).assertTrue();
      expect(pool.tryAcquire()).assertFalse();
    });
  });
}
