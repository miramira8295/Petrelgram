import { describe, expect, it } from '@ohos/hypium';
import { MessageDragGesture } from '../main/ets/util/messageDragGesture';

export default function messageDragGestureTest() {
  describe('MessageDragGesture', (): void => {
    it('hold_then_move_prefers_drag_without_menu', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000);
      state.move(40, 0, 1600);
      expect(state.prefersDrag(1600)).assertTrue();
      expect(state.end(1700, false)).assertFalse();
      expect(state.prefersDrag(1700)).assertTrue();
    });
    it('hold_and_release_invokes_original_action_once', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000);
      expect(state.end(1600, false)).assertTrue();
      expect(state.end(1601, false)).assertFalse();
    });
    it('quick_swipe_keeps_original_swipe_action', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000);
      state.move(40, 0, 1100);
      expect(state.prefersDrag(1700)).assertFalse();
      expect(state.end(1700, false)).assertFalse();
    });
    it('drag_end_never_falls_back_to_menu', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000); state.claim();
      expect(state.end(1600, false)).assertFalse();
      expect(state.prefersDrag(1700)).assertTrue();
    });
    it('cancel_or_short_tap_does_not_long_press', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000);
      expect(state.end(1600, true)).assertFalse();
      state.begin(0, 0, 2000);
      expect(state.end(2200, false)).assertFalse();
      expect(state.prefersDrag(2600)).assertFalse();
    });
    it('new_press_resets_drag_claim', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000); state.claim();
      state.begin(0, 0, 2000);
      expect(state.prefersDrag(2000)).assertFalse();
      expect(state.end(2600, false)).assertTrue();
    });
    it('reset_cancels_held_and_claimed_old_gesture', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(40, 80, 1000);
      state.move(80, 80, 1600); state.claim(); state.reset();
      expect(state.prefersDrag(2000)).assertFalse();
      expect(state.end(2000, false)).assertFalse();
      state.begin(5, 8, 3000);
      expect(state.end(3600, false)).assertTrue();
    });
    it('reset_during_pending_hold_prevents_late_menu', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(40, 80, 1000);
      state.reset(); state.move(40, 80, 2000);
      expect(state.prefersDrag(2000)).assertFalse();
      expect(state.end(2000, false)).assertFalse();
    });
    it('reset_after_early_move_allows_next_long_press', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000);
      state.move(40, 0, 1100); state.end(1700, false); state.reset();
      state.begin(100, 200, 3000); state.move(105, 205, 3500);
      expect(state.end(3600, false)).assertTrue();
      expect(state.end(3601, false)).assertFalse();
    });
    it('recycle_and_reuse_reset_is_idempotent', 0, (): void => {
      const state = new MessageDragGesture(); state.begin(0, 0, 1000);
      state.end(1600, false); state.reset(); state.reset();
      expect(state.prefersDrag(2000)).assertFalse();
      state.begin(0, 0, 3000); state.move(40, 0, 3100);
      expect(state.end(3600, false)).assertFalse();
    });
  });
}
