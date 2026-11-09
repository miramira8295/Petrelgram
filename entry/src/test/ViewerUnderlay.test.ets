import { describe, expect, it } from '@ohos/hypium';
import { ViewerUnderlay } from '../main/ets/util/viewerUnderlay';

class UnderlayHarness {
  hidden: boolean = false;
  changes: boolean[] = [];
  gate: ViewerUnderlay = new ViewerUnderlay((hidden: boolean): void => {
    this.hidden = hidden;
    this.changes.push(hidden);
  });
  open(): number {
    this.gate.setActive(true);
    return this.gate.mount();
  }
}

export default function viewerUnderlayTest() {
  describe('ViewerUnderlay', () => {
    it('chat_stays_visible_until_the_viewer_finishes_entering', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      expect(t.hidden).assertFalse();
      t.gate.entranceFinished(session);
      expect(t.hidden).assertTrue();
    });
    it('drag_reveals_chat_and_only_completed_spring_back_hides_it', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.entranceFinished(session);
      const motion: number = t.gate.reveal(session);
      expect(t.hidden).assertFalse();
      t.gate.settled(session, motion);
      expect(t.changes.join(',')).assertEqual('true,false,true');
    });
    it('entrance_completion_during_drag_does_not_hide_exposed_chat', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      const motion: number = t.gate.reveal(session);
      t.gate.entranceFinished(session);
      expect(t.hidden).assertFalse();
      t.gate.settled(session, motion);
      expect(t.hidden).assertTrue();
    });
    it('finishing_a_drag_during_entry_still_waits_for_opacity', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      const motion: number = t.gate.reveal(session);
      t.gate.settled(session, motion);
      expect(t.hidden).assertFalse();
      t.gate.entranceFinished(session);
      expect(t.hidden).assertTrue();
    });
    it('old_spring_back_cannot_hide_chat_during_a_new_drag', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.entranceFinished(session);
      const old: number = t.gate.reveal(session);
      const current: number = t.gate.reveal(session);
      t.gate.settled(session, old);
      expect(t.hidden).assertFalse();
      t.gate.settled(session, current);
      expect(t.hidden).assertTrue();
    });
    it('close_restores_chat_before_fade_and_rejects_late_completions', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.entranceFinished(session);
      t.gate.prepareClose();
      expect(t.hidden).assertFalse();
      t.gate.entranceFinished(session);
      t.gate.settled(session, t.gate.reveal(session));
      expect(t.hidden).assertFalse();
    });
    it('closing_before_entry_finishes_never_hides_the_thumbnail', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.prepareClose();
      t.gate.entranceFinished(session);
      expect(t.changes.length).assertEqual(0);
    });
    it('old_viewer_cannot_hide_or_reveal_a_new_viewer_session', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const old: number = t.open();
      const oldMotion: number = t.gate.reveal(old);
      t.gate.prepareClose();
      const current: number = t.gate.mount();
      t.gate.entranceFinished(old);
      t.gate.settled(old, oldMotion);
      expect(t.hidden).assertFalse();
      t.gate.entranceFinished(current);
      t.gate.unmount(old);
      t.gate.reveal(old);
      expect(t.hidden).assertTrue();
    });
    it('background_restores_chat_and_foreground_reuses_opaque_state', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.entranceFinished(session);
      t.gate.setActive(false);
      expect(t.hidden).assertFalse();
      t.gate.setActive(true);
      expect(t.hidden).assertTrue();
    });
    it('background_animation_completion_cannot_hide_until_foreground', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.setActive(false);
      t.gate.entranceFinished(session);
      expect(t.hidden).assertFalse();
      t.gate.setActive(true);
      expect(t.hidden).assertTrue();
    });
    it('unmount_restores_and_invalidates_all_callbacks', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.entranceFinished(session);
      t.gate.unmount(session);
      t.gate.entranceFinished(session);
      t.gate.settled(session, 0);
      expect(t.changes.join(',')).assertEqual('true,false');
    });
    it('split_columns_have_independent_coverage', 0, () => {
      const left: UnderlayHarness = new UnderlayHarness();
      const right: UnderlayHarness = new UnderlayHarness();
      const session: number = right.open();
      right.gate.entranceFinished(session);
      expect(right.hidden).assertTrue();
      expect(left.hidden).assertFalse();
      left.gate.setActive(false);
      expect(right.hidden).assertTrue();
    });
    it('repeated_target_or_visibility_notifications_do_not_republish', 0, () => {
      const t: UnderlayHarness = new UnderlayHarness();
      const session: number = t.open();
      t.gate.entranceFinished(session);
      for (let i: number = 0; i < 20; i++) {
        t.gate.setActive(true);
        t.gate.entranceFinished(session);
      }
      expect(t.changes.join(',')).assertEqual('true');
    });
  });
}
