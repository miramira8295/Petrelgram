import { TdObject } from '../tdkit/TdTypes';
import { plural, str } from './strings';

// "N 分钟前" and friends go through plural(): Chinese has one form, English has
// two ("1 minute ago" / "2 minutes ago"), so a plain placeholder would produce
// "1 minutes ago" the moment the app ships in English.
function relative(wasOnline: number, nowSec: number): string {
  const d = nowSec - wasOnline;
  if (d < 60) {
    return str('user_status_just_now');
  }
  if (d < 3600) {
    const n = Math.floor(d / 60);
    return plural('user_status_minutes_ago', n, n);
  }
  if (d < 86400) {
    const n = Math.floor(d / 3600);
    return plural('user_status_hours_ago', n, n);
  }
  const n = Math.floor(d / 86400);
  return plural('user_status_days_ago', n, n);
}

export function formatUserStatus(status: TdObject | undefined, nowSec: number): string {
  if (status === undefined) {
    return '';
  }
  const type = status['@type'] as string | undefined;
  if (type === 'userStatusOnline') {
    return str('user_status_online');
  }
  if (type === 'userStatusOffline') {
    const wasOnline = (status['was_online'] as number | undefined) ?? 0;
    return str('user_status_last_seen', relative(wasOnline, nowSec));
  }
  if (type === 'userStatusRecently') {
    return str('user_status_recently');
  }
  if (type === 'userStatusLastWeek') {
    return str('user_status_last_week');
  }
  if (type === 'userStatusLastMonth') {
    return str('user_status_last_month');
  }
  return '';
}
