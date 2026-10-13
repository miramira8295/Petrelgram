import { describe, expect, it } from '@ohos/hypium';
import { HoldRewindState } from '../main/ets/util/holdRewind';

export default function holdRewindTest() {
  describe('HoldRewind', () => {
    it('首次识别立即退两秒，后续至少间隔400ms', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      expect(state.nextTarget(1000)).assertEqual(8000);
      state.seekCompleted();
      expect(state.nextTarget(1399)).assertEqual(-1);
      expect(state.nextTarget(1400)).assertEqual(6000);
    });

    it('慢跳转未完成不追加请求，完成后从独立目标继续', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      expect(state.nextTarget(1000)).assertEqual(8000);
      expect(state.nextTarget(2000)).assertEqual(-1);
      expect(state.nextTarget(4000)).assertEqual(-1);
      state.seekCompleted();
      expect(state.nextTarget(4100)).assertEqual(6000);
      state.seekCompleted();
      expect(state.nextTarget(4101)).assertEqual(-1);
    });

    it('靠近片头只退剩余时间，不重复跳零', 0, () => {
      const state = new HoldRewindState();
      state.start(750, true);
      expect(state.nextTarget(1000)).assertEqual(0);
      state.seekCompleted();
      expect(state.nextTarget(2000)).assertEqual(-1);
      expect(state.active).assertTrue();
      expect(state.stop(true)).assertTrue();
    });

    it('已经在片头保持手势但不发无效跳转', 0, () => {
      const state = new HoldRewindState();
      state.start(0, false);
      expect(state.nextTarget(1000)).assertEqual(-1);
      expect(state.stop(true)).assertFalse();
    });

    it('播放中松手恢复一次，重复停止不再恢复', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      expect(state.stop(true)).assertTrue();
      expect(state.stop(true)).assertFalse();
      expect(state.nextTarget(1000)).assertEqual(-1);
    });

    it('暂停或播完后快退，松手不会自动播放', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, false);
      expect(state.nextTarget(1000)).assertEqual(8000);
      expect(state.stop(true)).assertFalse();
    });

    it('后台或焦点打断取消续播意图，迟到松手不启动', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      expect(state.stop(false)).assertFalse();
      expect(state.stop(true)).assertFalse();
    });

    it('停止后的跳转回调不产生下一步', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      state.nextTarget(1000);
      state.stop(true);
      state.seekCompleted();
      expect(state.nextTarget(2000)).assertEqual(-1);
      expect(state.active).assertFalse();
    });

    it('快速松手再长按，等待上一轮未完成跳转', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      state.nextTarget(1000);
      state.stop(true);
      state.start(8000, true);
      expect(state.nextTarget(1600)).assertEqual(-1);
      state.seekCompleted();
      expect(state.nextTarget(1700)).assertEqual(6000);
    });

    it('长按也等待此前的双击或滑条跳转', 0, () => {
      const state = new HoldRewindState();
      state.seekStarted(500);
      state.start(20000, true);
      expect(state.nextTarget(1000)).assertEqual(-1);
      state.seekCompleted();
      expect(state.nextTarget(1100)).assertEqual(18000);
    });

    it('等待五秒超时，已停止的手势不再报超时', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      state.nextTarget(1000);
      expect(state.timedOut(5999)).assertFalse();
      expect(state.timedOut(6000)).assertTrue();
      state.stop(true);
      expect(state.timedOut(7000)).assertFalse();
    });

    it('跳转完成取消超时等待', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      state.nextTarget(1000);
      state.seekCompleted();
      expect(state.timedOut(7000)).assertFalse();
    });

    it('重复开始不覆盖原手势位置和播放意图', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      state.nextTarget(1000);
      state.start(20000, false);
      expect(state.targetMs).assertEqual(8000);
      expect(state.stop(true)).assertTrue();
    });

    it('换视频清空等待与续播状态，新视频从新位置开始', 0, () => {
      const state = new HoldRewindState();
      state.start(10000, true);
      state.nextTarget(1000);
      state.reset();
      expect(state.stop(true)).assertFalse();
      state.start(30000, false);
      expect(state.nextTarget(1200)).assertEqual(28000);
      expect(state.stop(true)).assertFalse();
    });
  });
}
