import { str } from './strings';

// Formats a message auto-delete duration (seconds) into a compact avatar badge
// label:
// - Simplified Chinese: "30秒", "15分", "3时", "2天", "1周", "1月", "1年"
// - Traditional Chinese: "30秒", "15分", "3時", "2天", "1週", "1月", "1年"
// - English / others: "30s", "15m", "3h", "2d", "1w", "1mo", "1y"
// Returns '' when disabled (<= 0).
//
// 单位走资源（ttl_badge_*）而不是在这里按语言分支：以前用 ttlLocaleBucket 只分
// 中/繁/英三档，其余语言一律拿英文字母，等于把这些符号硬编码进了代码，i18n 门禁
// 也不许中文字面量留在这里。
export function formatTTL(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  if (seconds < 60) {
    return `${seconds}${str('ttl_badge_sec')}`;
  }
  if (seconds < 3600) {
    return `${Math.round(seconds / 60)}${str('ttl_badge_min')}`;
  }
  if (seconds < 86400) {
    return `${Math.round(seconds / 3600)}${str('ttl_badge_hour')}`;
  }
  if (seconds < 604800) {
    return `${Math.round(seconds / 86400)}${str('ttl_badge_day')}`;
  }
  if (seconds < 2592000) {
    return `${Math.round(seconds / 604800)}${str('ttl_badge_week')}`;
  }
  if (seconds < 31536000) {
    return `${Math.max(1, Math.round(seconds / 2592000))}${str('ttl_badge_month')}`;
  }
  return `${Math.max(1, Math.round(seconds / 31536000))}${str('ttl_badge_year')}`;
}
