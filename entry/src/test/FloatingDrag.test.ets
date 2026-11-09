import { describe, expect, it } from '@ohos/hypium';
import {
  FloatingDragAnchor, FloatingDragBounds, clampFloatingTranslation, dragFloatingTranslation
} from '../main/ets/util/floatingDrag';

function anchor(): FloatingDragAnchor {
  // Player laid out at bottom-right of a 360x780 root, 196x112 small window.
  return { x: 152, y: 578, width: 196, height: 112 };
}

function bounds(): FloatingDragBounds {
  return { width: 360, height: 780, margin: 8 };
}

export default function floatingDragTest() {
  describe('FloatingDrag', (): void => {
    it('keeps_translation_that_stays_inside_bounds', 0, (): void => {
      const result = clampFloatingTranslation(-40, -100, anchor(), bounds());
      expect(result.x).assertEqual(-40);
      expect(result.y).assertEqual(-100);
    });
    it('clamps_to_left_and_top_margins', 0, (): void => {
      const result = clampFloatingTranslation(-500, -900, anchor(), bounds());
      expect(result.x).assertEqual(8 - 152);
      expect(result.y).assertEqual(8 - 578);
    });
    it('clamps_to_right_and_bottom_margins', 0, (): void => {
      const result = clampFloatingTranslation(500, 900, anchor(), bounds());
      expect(result.x).assertEqual(360 - 8 - 196 - 152);
      expect(result.y).assertEqual(780 - 8 - 112 - 578);
    });
    it('pins_to_start_margin_when_window_exceeds_bounds', 0, (): void => {
      const wide: FloatingDragAnchor = { x: 0, y: 0, width: 500, height: 900 };
      const result = clampFloatingTranslation(120, 260, wide, bounds());
      expect(result.x).assertEqual(8);
      expect(result.y).assertEqual(8);
    });
    it('composes_pan_delta_from_drag_start_then_clamps', 0, (): void => {
      const result = dragFloatingTranslation(-20, -30, -10, -900, anchor(), bounds());
      expect(result.x).assertEqual(-30);
      expect(result.y).assertEqual(8 - 578);
    });
    it('reclamps_existing_translation_after_window_grows', 0, (): void => {
      // Expanded window: 320x180 anchored further left at the same right edge.
      const large: FloatingDragAnchor = { x: 28, y: 510, width: 320, height: 180 };
      const held = clampFloatingTranslation(20, 120, large, bounds());
      expect(held.x).assertEqual(360 - 8 - 320 - 28);
      expect(held.y).assertEqual(780 - 8 - 180 - 510);
    });
  });
}
