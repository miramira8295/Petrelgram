import { fullDate, monthDay } from './intlFormat';

// Date pill between messages when the calendar day changes ("7月6日", or
// "2024年12月31日" once the year differs from the current one).
export function formatDateSeparator(dateSec: number): string {
  const d = new Date(dateSec * 1000);
  const now = new Date();
  if (d.getFullYear() === now.getFullYear()) {
    return monthDay(d);
  }
  return fullDate(d);
}

export function sameDay(aSec: number, bSec: number): boolean {
  const a = new Date(aSec * 1000);
  const b = new Date(bSec * 1000);
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
