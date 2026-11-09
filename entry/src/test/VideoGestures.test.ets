import { describe, it, expect } from '@ohos/hypium';
import {
  GESTURE_ZONE_LEFT, GESTURE_ZONE_RIGHT, LEVEL_TRAVEL_RATIO,
  gestureZoneOf, levelAfterDrag
} from '../main/ets/util/videoGestures';

export default function videoGesturesTest() {
  describe('videoGestures', () => {
    // 左右分区按**起手点**，不是当前点——手指拖过中线不该把亮度变成音量。
    it('zone_comes_from_the_touch_down_x', 0, () => {
      expect(gestureZoneOf(100, 800)).assertEqual(GESTURE_ZONE_LEFT);
      expect(gestureZoneOf(700, 800)).assertEqual(GESTURE_ZONE_RIGHT);
      // 正中间归右（音量），与双击 ±15s 的分区一致。
      expect(gestureZoneOf(400, 800)).assertEqual(GESTURE_ZONE_RIGHT);
    });

    it('zone_is_safe_on_degenerate_width', 0, () => {
      expect(gestureZoneOf(0, 0)).assertEqual(GESTURE_ZONE_RIGHT);
    });

    // ── 亮度 / 音量 ───────────────────────────────────────────────────
    // **向上是加**：屏幕坐标 y 向下为正，所以 dy 为负才是加。判反了就是
    // "往上滑越滑越暗"。
    it('dragging_up_increases_the_level', 0, () => {
      const h: number = 1000;
      const travel: number = h * LEVEL_TRAVEL_RATIO;
      // 划过 travel 的四分之一 = 0.25 档。
      expect(levelAfterDrag(0.5, -travel / 4, h)).assertEqual(0.75);
      expect(levelAfterDrag(0.5, travel / 4, h)).assertEqual(0.25);
      // 划满 travel 就是从 0 到 1。
      expect(levelAfterDrag(0, -travel, h)).assertEqual(1);
    });

    it('level_clamps_to_zero_and_one', 0, () => {
      expect(levelAfterDrag(0.9, -10000, 1000)).assertEqual(1);
      expect(levelAfterDrag(0.1, 10000, 1000)).assertEqual(0);
    });

    it('level_is_safe_on_degenerate_height', 0, () => {
      expect(levelAfterDrag(0.4, -100, 0)).assertEqual(0.4);
    });
  });
}
