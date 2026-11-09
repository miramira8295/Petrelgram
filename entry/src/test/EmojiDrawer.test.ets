import { describe, expect, it } from '@ohos/hypium';
import {
  drawerTopOverlap, emojiDrawerHeight, mediaPanelColumns, mediaPanelTemplate, EmojiDrawerState
} from '../main/ets/pages/chat/EmojiDrawerState';

export default function emojiDrawerTest() {
  describe('EmojiDrawer', (): void => {
    it('compact_keeps_existing_height', 0, (): void => {
      expect(emojiDrawerHeight(800, 100, 76, 24, false)).assertEqual(312);
    });
    it('expanded_reserves_header_composer_and_safe_area', 0, (): void => {
      expect(emojiDrawerHeight(800, 100, 76, 24, true)).assertEqual(592);
    });
    it('compact_clamps_to_short_window', 0, (): void => {
      expect(emojiDrawerHeight(300, 100, 76, 24, false)).assertEqual(92);
      expect(emojiDrawerHeight(100, 100, 76, 24, true)).assertEqual(0);
    });
    it('composer_growth_reduces_expanded_height', 0, (): void => {
      expect(emojiDrawerHeight(800, 100, 176, 24, true)).assertEqual(492);
    });
    it('uses_pane_width_for_columns', 0, (): void => {
      expect(mediaPanelColumns(380, 'sticker')).assertEqual(5);
      expect(mediaPanelColumns(740, 'sticker')).assertEqual(10);
      expect(mediaPanelColumns(360, 'gif')).assertEqual(2);
      expect(mediaPanelColumns(740, 'gif')).assertEqual(4);
      expect(mediaPanelColumns(30, 'emoji')).assertEqual(1);
    });
    it('template_matches_count', 0, (): void => {
      expect(mediaPanelTemplate(3)).assertEqual('1fr 1fr 1fr');
    });
    it('back_collapses_only_once', 0, (): void => {
      const state = new EmojiDrawerState(); state.expanded = true;
      expect(state.collapse()).assertTrue(); expect(state.collapse()).assertFalse();
    });
    it('invalid_measurement_does_not_erase_layout', 0, (): void => {
      const state = new EmojiDrawerState(); state.measureViewport(800); state.measureComposer(76);
      state.measureViewport(0); state.measureComposer(Number.NaN); state.expanded = true;
      expect(state.height(100, 24)).assertEqual(592);
      state.measureViewport(400); expect(state.height(100, 24)).assertEqual(192);
    });
    it('lift_height_absorbs_composer_safe_gap_diff_so_close_ends_at_zero', 0, (): void => {
      const state = new EmojiDrawerState();
      state.measureViewport(800);
      state.measureComposer(76);
      expect(drawerTopOverlap(28, false)).assertEqual(22);
      expect(drawerTopOverlap(0, false)).assertEqual(2);
      expect(drawerTopOverlap(28, true)).assertEqual(0);
      expect(state.totalHeight(100, 28)).assertEqual(340);
      expect(state.liftHeight(100, 28)).assertEqual(318);
      expect(state.topOverlap(28)).assertEqual(22);
      state.closingToIme = true;
      expect(state.topOverlap(28)).assertEqual(0);
    });
  });
}
