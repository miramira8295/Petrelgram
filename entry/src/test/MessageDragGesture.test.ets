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
  });
}
