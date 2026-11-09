import { describe, it, expect } from '@ohos/hypium';
import { segmentDurationMs, quantizeToGrid, startOffset, nextTimeOffset } from '../main/ets/services/StreamSegmentMath';

export default function streamSegmentMathTest() {
  describe('StreamSegmentMath', () => {
    it('duration_scale0_is_1000ms', 0, () => {
      expect(segmentDurationMs(0)).assertEqual(1000);
    });
    it('duration_scale1_is_500ms', 0, () => {
      expect(segmentDurationMs(1)).assertEqual(500);
    });
    it('quantize_floors_to_grid', 0, () => {
      // scale 0 -> 1000ms grid; 12345 -> 12000
      expect(quantizeToGrid(12345, 0)).assertEqual(12000);
    });
    it('start_offset_backs_off_n_segments', 0, () => {
      // edge 20000, scale 0 (1000ms), back 3 -> 17000
      expect(startOffset(20000, 0, 3)).assertEqual(17000);
    });
    it('next_offset_adds_one_segment', 0, () => {
      expect(nextTimeOffset(17000, 1)).assertEqual(17500);
    });
  });
}
