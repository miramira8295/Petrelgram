import { describe, expect, it } from '@ohos/hypium';
import { VideoProgressClock } from '../main/ets/util/videoProgressClock';

interface ProgressTask { tick: () => void; ms: number; cancelled: boolean; }
class ProgressTimers {
  tasks: ProgressTask[] = [];
  reads: number = 0;
  clock: VideoProgressClock = new VideoProgressClock((): void => { this.reads++; },
    (tick: () => void, ms: number): number => {
      this.tasks.push({ tick: tick, ms: ms, cancelled: false });
      return this.tasks.length - 1;
    }, (id: number): void => { this.tasks[id].cancelled = true; });

  elapse(ms: number): void {
    this.tasks.forEach((task: ProgressTask): void => {
      if (!task.cancelled) {
        for (let i: number = 0; i < Math.floor(ms / task.ms); i++) { task.tick(); }
      }
    });
  }
}

export default function videoProgressClockTest() {
  describe('VideoProgressClock', () => {
    it('hidden_controls_publish_resume_position_once_per_second', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      t.clock.sync(true, false);
      t.elapse(60000);
      expect(t.reads).assertEqual(60);
    });
    it('visible_controls_keep_existing_progress_cadence', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      t.clock.sync(true, true);
      t.elapse(3500);
      expect(t.reads).assertEqual(10);
    });
    it('paused_controls_and_repeated_state_notifications_do_not_poll', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      t.clock.sync(false, false);
      t.clock.sync(false, true);
      t.elapse(60000);
      expect(t.tasks.length).assertEqual(0);
      expect(t.reads).assertEqual(0);
    });
    it('pause_cancels_pending_tick_and_resume_keeps_one_timer', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      t.clock.sync(true, false);
      t.clock.sync(false, false);
      t.clock.sync(true, false);
      t.clock.sync(true, false);
      t.tasks[0].tick();
      expect(t.reads).assertEqual(0);
      t.elapse(3000);
      expect(t.reads).assertEqual(3);
      expect(t.tasks.length).assertEqual(2);
      expect(t.tasks[0].cancelled).assertTrue();
    });
    it('show_hide_drops_old_cadence_without_duplicate_callbacks', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      t.clock.sync(true, true);
      t.clock.sync(true, false);
      t.clock.sync(true, false);
      t.tasks[0].tick();
      t.elapse(2000);
      expect(t.reads).assertEqual(2);
      t.clock.sync(true, true);
      t.elapse(3500);
      expect(t.reads).assertEqual(12);
    });
    it('release_rejects_queued_callback_even_after_player_reuse', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      t.clock.sync(true, true);
      t.clock.stop();
      t.clock.stop();
      t.clock.sync(true, false);
      t.tasks[0].tick();
      expect(t.reads).assertEqual(0);
      t.elapse(1000);
      expect(t.reads).assertEqual(1);
    });
    it('rapid_visibility_changes_leave_only_the_latest_timer_live', 0, () => {
      const t: ProgressTimers = new ProgressTimers();
      for (let i: number = 0; i < 20; i++) {
        t.clock.sync(true, true);
        t.clock.sync(true, false);
      }
      for (let i: number = 0; i < t.tasks.length - 1; i++) { t.tasks[i].tick(); }
      expect(t.reads).assertEqual(0);
      t.elapse(1000);
      expect(t.reads).assertEqual(1);
      t.clock.stop();
      expect(t.tasks.filter((task: ProgressTask): boolean => !task.cancelled).length).assertEqual(0);
    });
  });
}
