import { describe, it, expect } from '@ohos/hypium';
import { formatUserStatus } from '../main/ets/util/formatUserStatus';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// No string source is installed in host tests, so str()/plural() return the key
// (with arguments appended). Asserting on keys tests the decision this function
// actually makes — which message, with which count — instead of pinning the
// copy, so rewording no longer breaks the suite while a wrong key still does.
export default function formatUserStatusTest() {
  describe('formatUserStatus', () => {
    it('online', 0, () => {
      const s: TdObject = { '@type': 'userStatusOnline' };
      expect(formatUserStatus(s, 1000)).assertEqual('user_status_online');
    });

    it('recently', 0, () => {
      const s: TdObject = { '@type': 'userStatusRecently' };
      expect(formatUserStatus(s, 1000)).assertEqual('user_status_recently');
    });

    it('last week and last month', 0, () => {
      expect(formatUserStatus({ '@type': 'userStatusLastWeek' }, 1000))
        .assertEqual('user_status_last_week');
      expect(formatUserStatus({ '@type': 'userStatusLastMonth' }, 1000))
        .assertEqual('user_status_last_month');
    });

    it('offline just now', 0, () => {
      const s: TdObject = { '@type': 'userStatusOffline' };
      s['was_online'] = 980;
      expect(formatUserStatus(s, 1000))
        .assertEqual('user_status_last_seen(user_status_just_now)');
    });

    it('offline minutes carries the count', 0, () => {
      const s: TdObject = { '@type': 'userStatusOffline' };
      s['was_online'] = 940;
      expect(formatUserStatus(s, 1000))
        .assertEqual('user_status_last_seen(user_status_minutes_ago(1,1))');
    });

    it('offline hours carries the count', 0, () => {
      const s: TdObject = { '@type': 'userStatusOffline' };
      s['was_online'] = 1000 - 7200;
      expect(formatUserStatus(s, 1000))
        .assertEqual('user_status_last_seen(user_status_hours_ago(2,2))');
    });

    it('offline days carries the count', 0, () => {
      const s: TdObject = { '@type': 'userStatusOffline' };
      s['was_online'] = 1000 - 86400 * 3;
      expect(formatUserStatus(s, 1000))
        .assertEqual('user_status_last_seen(user_status_days_ago(3,3))');
    });

    it('empty and undefined', 0, () => {
      expect(formatUserStatus({ '@type': 'userStatusEmpty' }, 1000)).assertEqual('');
      expect(formatUserStatus(undefined, 1000)).assertEqual('');
    });
  });
}
