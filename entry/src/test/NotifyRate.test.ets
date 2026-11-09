import { describe, expect, it } from '@ohos/hypium';
import {
  NOTIFY_MIN_GAP_MS, NOTIFY_QUEUE_MAX, overflowCount, publishDelayMs
} from '../main/ets/util/notifyRate';

export default function notifyRateTest() {
  describe('notifyRate', () => {
    it('first_notice_goes_out_immediately', 0, (): void => {
      expect(publishDelayMs(0, 1000)).assertEqual(0);
      expect(publishDelayMs(-1, 1000)).assertEqual(0);
    });

    // 间隔已满就立刻放行。
    it('waits_out_the_remaining_gap', 0, (): void => {
      expect(publishDelayMs(1000, 1000 + NOTIFY_MIN_GAP_MS)).assertEqual(0);
      expect(publishDelayMs(1000, 5000)).assertEqual(0);
    });

    it('returns_the_remainder_when_too_soon', 0, (): void => {
      expect(publishDelayMs(1000, 1000)).assertEqual(NOTIFY_MIN_GAP_MS);
      expect(publishDelayMs(1000, 1050)).assertEqual(NOTIFY_MIN_GAP_MS - 50);
    });

    // 时钟回拨不能把一整队一次性放出去，否则又撞限频。
    it('clock_going_backwards_still_waits', 0, (): void => {
      expect(publishDelayMs(5000, 1000)).assertEqual(NOTIFY_MIN_GAP_MS);
    });

    // 间隔必须严格压在系统的 10 条/秒之下（100ms），否则这层排队白做。
    it('gap_stays_under_the_system_limit', 0, (): void => {
      expect(NOTIFY_MIN_GAP_MS >= 100).assertTrue();
    });

    it('queue_only_overflows_past_the_cap', 0, (): void => {
      expect(overflowCount(0)).assertEqual(0);
      expect(overflowCount(NOTIFY_QUEUE_MAX)).assertEqual(0);
      expect(overflowCount(NOTIFY_QUEUE_MAX + 3)).assertEqual(3);
    });
  });
}
