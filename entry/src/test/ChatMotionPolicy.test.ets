import { describe, expect, it } from '@ohos/hypium';
import { chatMotionAllowed, chatTimelineSuspended } from '../main/ets/util/chatMotionPolicy';
import { BackdropPhaseClock, BACKDROP_PHASE_MS } from '../main/ets/util/backdropPhaseClock';
import { AnimationGate } from '../main/ets/util/animationGate';

interface PhaseTask {
  id: number;
  tick: () => void;
}

class PhaseTimers {
  tasks: PhaseTask[] = [];
  cancelled: number[] = [];
  intervals: number[] = [];

  schedule(tick: () => void, ms: number): number {
    const id: number = this.tasks.length;
    this.tasks.push({ id: id, tick: tick });
    this.intervals.push(ms);
    return id;
  }

  cancel(id: number): void {
    this.cancelled.push(id);
  }
}

export default function chatMotionPolicyTest() {
  describe('chatMotionPolicy', () => {
    it('可见前台聊天允许运行，隐藏或后台均暂停', 0, () => {
      expect(chatMotionAllowed(true, true, false)).assertTrue();
      expect(chatMotionAllowed(false, true, false)).assertFalse();
      expect(chatMotionAllowed(true, false, false)).assertFalse();
    });

    it('覆盖只作用于所属聊天列，分栏中未覆盖区域仍可运行', 0, () => {
      expect(chatMotionAllowed(true, true, true)).assertFalse();
      expect(chatMotionAllowed(true, true, false)).assertTrue();
    });

    it('后台关闭查看器仍暂停，回前台后才恢复', 0, () => {
      expect(chatMotionAllowed(true, false, true)).assertFalse();
      expect(chatMotionAllowed(true, false, false)).assertFalse();
      expect(chatMotionAllowed(true, true, false)).assertTrue();
    });

    it('查看器未关时返回前台或滚动结束不能恢复', 0, () => {
      const allowed: boolean = chatMotionAllowed(true, true, true);
      expect(chatTimelineSuspended(allowed, false, false, false)).assertTrue();
    });

    it('恢复可见后仍保留首屏、滚动和等待稳定三道暂停条件', 0, () => {
      expect(chatTimelineSuspended(true, true, false, false)).assertTrue();
      expect(chatTimelineSuspended(true, false, true, false)).assertTrue();
      expect(chatTimelineSuspended(true, false, false, true)).assertTrue();
      expect(chatTimelineSuspended(true, false, false, false)).assertFalse();
    });

    it('覆盖到恢复的状态实际驱动已挂载与覆盖中新挂载的订阅者', 0, () => {
      const gate: AnimationGate = new AnimationGate(0);
      const first: boolean[] = [];
      const late: boolean[] = [];
      gate.subscribe((paused: boolean): void => { first.push(paused); });
      gate.setSuspended(chatTimelineSuspended(chatMotionAllowed(true, true, true), false, false, false));
      gate.subscribe((paused: boolean): void => { late.push(paused); });
      gate.setSuspended(chatTimelineSuspended(chatMotionAllowed(true, false, false), false, false, false));
      expect(first.join(',')).assertEqual('false,true');
      expect(late.join(',')).assertEqual('true');
      gate.setSuspended(chatTimelineSuspended(chatMotionAllowed(true, true, false), false, false, false));
      expect(first.join(',')).assertEqual('false,true,false');
      expect(late.join(',')).assertEqual('true,false');
    });
  });

  describe('backdropPhaseClock', () => {
    it('重复放行只建一个4200ms时钟，正常回调推进相位', 0, () => {
      const timers: PhaseTimers = new PhaseTimers();
      let ticks: number = 0;
      const clock: BackdropPhaseClock = new BackdropPhaseClock((): void => { ticks++; },
        (tick: () => void, ms: number): number => timers.schedule(tick, ms),
        (id: number): void => { timers.cancel(id); });
      clock.setRunning(true);
      clock.setRunning(true);
      expect(timers.tasks.length).assertEqual(1);
      expect(timers.intervals[0]).assertEqual(BACKDROP_PHASE_MS);
      timers.tasks[0].tick();
      expect(ticks).assertEqual(1);
    });

    it('未运行就暂停不建时钟，停止幂等且废弃排队回调', 0, () => {
      const timers: PhaseTimers = new PhaseTimers();
      let ticks: number = 0;
      const clock: BackdropPhaseClock = new BackdropPhaseClock((): void => { ticks++; },
        (tick: () => void, ms: number): number => timers.schedule(tick, ms),
        (id: number): void => { timers.cancel(id); });
      clock.setRunning(false);
      expect(timers.tasks.length).assertEqual(0);
      clock.setRunning(true);
      clock.setRunning(false);
      clock.setRunning(false);
      timers.tasks[0].tick();
      expect(timers.cancelled.join(',')).assertEqual('0');
      expect(ticks).assertEqual(0);
    });

    it('快速开关20轮，每轮只留一个时钟，旧回调不能在恢复后复活', 0, () => {
      const timers: PhaseTimers = new PhaseTimers();
      let ticks: number = 0;
      const clock: BackdropPhaseClock = new BackdropPhaseClock((): void => { ticks++; },
        (tick: () => void, ms: number): number => timers.schedule(tick, ms),
        (id: number): void => { timers.cancel(id); });
      for (let i = 0; i < 20; i++) {
        clock.setRunning(true);
        clock.setRunning(false);
      }
      clock.setRunning(true);
      for (let i = 0; i < 20; i++) {
        timers.tasks[i].tick();
      }
      expect(ticks).assertEqual(0);
      expect(timers.cancelled.length).assertEqual(20);
      expect(timers.tasks.length).assertEqual(21);
      timers.tasks[20].tick();
      expect(ticks).assertEqual(1);
      clock.setRunning(false);
    });
  });
}
