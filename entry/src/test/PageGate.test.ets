import { describe, expect, it } from '@ohos/hypium';
import {
  armedPageGate, canFirePageGate, draggedPageGate, firedPageGate,
  PAGE_GATE_REARM_DRAG_VP, PageGate, pageGateShotIsUserDriven, reachedNewerPageTrigger,
  rearmPageGate, idlePageGate
} from '../main/ets/util/pageGate';

// 攒够阈值所需的一帧位移：一帧就跨过去，用例里不必凑循环。
const BIG_DRAG: number = PAGE_GATE_REARM_DRAG_VP + 1;

export default function pageGateTest() {
  describe('pageGate', () => {
    // 开局不上膛：落在未读锚点时末行本来就可见，满膛的闸会立刻自动打一页 newer。
    it('startup_gate_is_idle_until_the_user_drags', 0, () => {
      const idle: PageGate = idlePageGate();
      expect(canFirePageGate(idle, 13)).assertFalse();
      expect(pageGateShotIsUserDriven(idle)).assertFalse();
      const dragged: PageGate = draggedPageGate(idle, BIG_DRAG);
      expect(canFirePageGate(dragged, 13)).assertTrue();
      expect(pageGateShotIsUserDriven(dragged)).assertTrue();
    });

    it('initial_gate_is_loaded_but_not_by_the_user', 0, () => {
      const gate: PageGate = armedPageGate();
      expect(gate.armed).assertTrue();
      expect(gate.firedAtEnd).assertEqual(-1);
      expect(gate.dragSinceFire).assertEqual(0);
      expect(canFirePageGate(gate, 0)).assertTrue();
      // 开局那一发是留给首屏自动补页的，不是用户扣的扳机。
      expect(pageGateShotIsUserDriven(gate)).assertFalse();
    });

    it('explicit_user_arm_is_tagged_as_user_driven', 0, () => {
      expect(pageGateShotIsUserDriven(armedPageGate(true))).assertTrue();
    });

    it('a_shot_disarms_immediately', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(), 130);
      expect(fired.armed).assertFalse();
      expect(fired.firedAtEnd).assertEqual(130);
      expect(fired.dragSinceFire).assertEqual(0);
      expect(canFirePageGate(fired, 131)).assertFalse();
    });

    // 7c83b32 防的那条跑飞链：每追加一页 30 行，stackFromEnd 把视口往下推，
    // end 就涨 ~28。弱闸（end > firedAtEnd）每次都放行，armed 必须挡住。
    // 关键是这些位移都是程序性的（ScrollState.Idle），一帧手指位移都没有，
    // 所以累计量恒 0，闸永远上不了膛。
    it('content_growth_alone_never_rearms_the_gate', 0, () => {
      let gate: PageGate = firedPageGate(armedPageGate(true), 130);
      const ends: number[] = [158, 186, 214, 242, 270, 298, 326, 354];
      for (const end of ends) {
        expect(canFirePageGate(gate, end)).assertFalse();
        // 程序性位移不进 draggedPageGate，这里连喂都不喂——等价于喂 0。
        gate = draggedPageGate(gate, 0);
      }
      expect(gate.armed).assertFalse();
      expect(gate.dragSinceFire).assertEqual(0);
      expect(gate.firedAtEnd).assertEqual(130);
    });

    // 缺陷 1 的核心：用户停在最后几行（end 恒等于 rows - 1）时也必须能上膛。
    // 判据里根本没有视口位置这一维，所以"贴着尾部"不再是永久锁死的理由。
    it('drag_rearms_even_while_pinned_at_the_tail', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(true), 80);
      const rearmed: PageGate = draggedPageGate(fired, BIG_DRAG);
      expect(rearmed.armed).assertTrue();
      expect(pageGateShotIsUserDriven(rearmed)).assertTrue();
      // firedAtEnd 归零，同一个 end 也能再打——用户又推了一段就该翻得动。
      expect(canFirePageGate(rearmed, 80)).assertTrue();
    });

    // 真机回归：42 行末端打出一页后变成 70 行，手动锚点复位把视口放回 end=41。
    // 复位发生在手指仍按住时会被 ArkUI 报成 Scroll，足以重新上膛；但此刻已经
    // 远离新窗口末端，绝不能立即再请求一页。
    it('anchor_restore_away_from_the_new_tail_cannot_kick_another_page', 0, () => {
      expect(reachedNewerPageTrigger(41, 42)).assertTrue();
      expect(reachedNewerPageTrigger(41, 70)).assertFalse();
    });

    it('newer_trigger_zone_is_the_last_five_rows_only', 0, () => {
      expect(reachedNewerPageTrigger(64, 70)).assertFalse();
      expect(reachedNewerPageTrigger(65, 70)).assertTrue();
      expect(reachedNewerPageTrigger(69, 70)).assertTrue();
      // 布局抖动偶尔会上报越界末行，仍按进入末端触发区处理。
      expect(reachedNewerPageTrigger(70, 70)).assertTrue();
    });

    it('invalid_visible_ranges_never_reach_the_newer_trigger', 0, () => {
      expect(reachedNewerPageTrigger(-1, 70)).assertFalse();
      expect(reachedNewerPageTrigger(0, 0)).assertFalse();
      expect(reachedNewerPageTrigger(69, 70, 0)).assertFalse();
    });

    it('drag_below_the_threshold_does_not_rearm_yet', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(true), 80);
      const half: number = PAGE_GATE_REARM_DRAG_VP / 2;
      const partial: PageGate = draggedPageGate(fired, half);
      expect(partial.armed).assertFalse();
      expect(partial.dragSinceFire).assertEqual(half);
      // 位移是累计的：下一帧补上剩下那一半就够了。
      const full: PageGate = draggedPageGate(partial, half);
      expect(full.armed).assertTrue();
    });

    // 一帧一帧地喂真实位移，攒够才放一发——"想要 N 页就得真拖 N 个阈值"。
    it('each_page_costs_one_full_drag_quantum', 0, () => {
      let gate: PageGate = firedPageGate(armedPageGate(true), 80);
      let fires: number = 0;
      const frameVp: number = 12;
      const frames: number = 40; // 40 * 12 = 480vp = 4 个阈值
      for (let i = 0; i < frames; i++) {
        gate = draggedPageGate(gate, frameVp);
        if (canFirePageGate(gate, 80 + fires)) {
          fires++;
          gate = firedPageGate(gate, 80 + fires);
        }
      }
      expect(fires).assertEqual(Math.floor(frames * frameVp / PAGE_GATE_REARM_DRAG_VP));
    });

    it('sign_of_the_offset_does_not_matter', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(true), 80);
      expect(draggedPageGate(fired, -BIG_DRAG).armed).assertTrue();
    });

    it('a_loaded_gate_absorbs_no_drag', 0, () => {
      const gate: PageGate = armedPageGate(true);
      expect(draggedPageGate(gate, BIG_DRAG) === gate).assertTrue();
    });

    it('zero_offset_frames_are_ignored', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(true), 80);
      expect(draggedPageGate(fired, 0) === fired).assertTrue();
    });

    it('weak_gate_still_blocks_a_repeat_knock_at_the_same_end', 0, () => {
      // 上膛态下 end 没往下走（比如布局抖了一下又报同一批行号）不该重复取页。
      const rearmed: PageGate = {
        armed: true, armedByUser: true, firedAtEnd: 130, dragSinceFire: 0
      };
      expect(canFirePageGate(rearmed, 130)).assertFalse();
      expect(canFirePageGate(rearmed, 131)).assertTrue();
    });

    it('rearm_only_accepts_user_driven_input', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(true), 130);
      expect(rearmPageGate(fired, false).armed).assertFalse();
      const rearmed: PageGate = rearmPageGate(fired, true);
      expect(rearmed.armed).assertTrue();
      expect(rearmed.firedAtEnd).assertEqual(-1);
      expect(pageGateShotIsUserDriven(rearmed)).assertTrue();
    });

    it('a_fully_loaded_gate_is_returned_as_is', 0, () => {
      const gate: PageGate = armedPageGate();
      expect(rearmPageGate(gate, true) === gate).assertTrue();
      expect(rearmPageGate(gate, false) === gate).assertTrue();
    });

    it('never_mutates_the_input', 0, () => {
      const gate: PageGate = armedPageGate(true);
      firedPageGate(gate, 42);
      expect(gate.armed).assertTrue();
      expect(gate.armedByUser).assertTrue();
      expect(gate.firedAtEnd).assertEqual(-1);
      const fired: PageGate = firedPageGate(gate, 42);
      draggedPageGate(fired, 30);
      expect(fired.dragSinceFire).assertEqual(0);
    });
  });
}
