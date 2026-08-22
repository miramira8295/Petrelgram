import { describe, it, expect } from '@ohos/hypium';
import { updateCheckThrottled } from '../main/ets/util/updateThrottle';

const H6: number = 6 * 3600 * 1000;

export default function updateThrottleTest() {
  describe('updateThrottle', () => {
    // 同一个版本、刚查过：该节流，别每次启动都打网络。
    it('throttles_a_recent_check_on_the_same_version', 0, () => {
      expect(updateCheckThrottled(1000, 1000 + H6 / 2, H6, '1.3.8', '1.3.8')).assertTrue();
    });

    // 同一个版本、超过间隔：该查。
    it('allows_check_after_the_interval', 0, () => {
      expect(updateCheckThrottled(1000, 1000 + H6 + 1, H6, '1.3.8', '1.3.8')).assertFalse();
    });

    // **issue #87 的核心**：应用刚升级过，缓存里那条结果是上一版查的，
    // 无论多新都已经失效——必须放行，否则"关于"页一直显示旧的最新版本号和
    // 更新内容，要用户手动点一次才刷新。
    it('never_throttles_when_the_app_version_changed', 0, () => {
      expect(updateCheckThrottled(1000, 1001, H6, '1.3.8', '1.3.9')).assertFalse();
    });

    // 没有记录过是哪个版本查的（旧版本升上来、第一次带这个字段）：
    // 同样当作失效，放行一次把基准补上。
    it('never_throttles_when_the_checked_version_is_unknown', 0, () => {
      expect(updateCheckThrottled(1000, 1001, H6, '', '1.3.9')).assertFalse();
    });

    // 从没查过：放行。
    it('allows_the_very_first_check', 0, () => {
      expect(updateCheckThrottled(0, 1000, H6, '', '1.3.9')).assertFalse();
    });

    // 时间戳是脏数据（未来时间/NaN）不能当成"刚查过"而把检查永久挡住。
    it('ignores_a_corrupt_timestamp', 0, () => {
      expect(updateCheckThrottled(Number.NaN, 1000, H6, '1.3.8', '1.3.8')).assertFalse();
      expect(updateCheckThrottled(9e15, 1000, H6, '1.3.8', '1.3.8')).assertFalse();
    });
  });
}
