import { TdObject } from '../tdkit/TdTypes';
import { clockTime, fullDateTime, monthDayTime } from './intlFormat';
import { str } from './strings';

// "最近上线于" line for the contacts list. Unlike formatUserStatus (which gives
// a coarse "X 分钟前"), this mirrors the official client's concrete clock time:
// today → HH:mm, yesterday → 昨天 HH:mm, this year → M月D日 HH:mm.
//
// Three sentence keys rather than one with a date slot: English needs "last
// seen at 09:05" but "last seen yesterday at 09:05", and that "at" cannot be
// moved by substitution alone.
export function formatLastSeen(status: TdObject | undefined, nowSec: number): string {
  if (status === undefined) {
    return '';
  }
  const type = status['@type'] as string | undefined;
  if (type === 'userStatusOnline') {
    return str('status_online');
  }
  if (type === 'userStatusRecently') {
    return str('status_recently');
  }
  if (type === 'userStatusLastWeek') {
    return str('status_last_week');
  }
  if (type === 'userStatusLastMonth') {
    return str('status_last_month');
  }
  if (type !== 'userStatusOffline') {
    return '';
  }
  const was = (status['was_online'] as number | undefined) ?? 0;
  if (was <= 0) {
    return str('status_recently');
  }
  const d = new Date(was * 1000);
  const now = new Date(nowSec * 1000);
  const sameDay = d.getFullYear() === now.getFullYear()
    && d.getMonth() === now.getMonth()
    && d.getDate() === now.getDate();
  if (sameDay) {
    return str('last_seen_time', clockTime(d));
  }
  const y = new Date((nowSec - 86400) * 1000);
  const yesterday = d.getFullYear() === y.getFullYear()
    && d.getMonth() === y.getMonth()
    && d.getDate() === y.getDate();
  if (yesterday) {
    return str('last_seen_yesterday', clockTime(d));
  }
  if (d.getFullYear() === now.getFullYear()) {
    return str('last_seen_date', monthDayTime(d));
  }
  return str('last_seen_date', fullDateTime(d));
}
