import { currentLocale } from './intlFormat';

function ttlLocaleBucket(locale: string): 'zh-Hans' | 'zh-Hant' | 'en' {
  const lower = locale.toLowerCase();
  if (!lower.startsWith('zh')) {
    return 'en';
  }
  if (lower.indexOf('hant') >= 0 || lower.indexOf('tw') >= 0 ||
    lower.indexOf('hk') >= 0 || lower.indexOf('mo') >= 0) {
    return 'zh-Hant';
  }
  return 'zh-Hans';
}

// Formats a message auto-delete duration (seconds) into a compact avatar badge
// label according to the active language:
// - Simplified Chinese: "30秒", "15分", "3时", "2天", "1周", "1月", "1年"
// - Traditional Chinese: "30秒", "15分", "3時", "2天", "1週", "1月", "1年"
// - English / others: "30s", "15m", "3h", "2d", "1w", "1mo", "1y"
// Returns '' when disabled (<= 0).
export function formatTTL(seconds: number, localeOverride?: string): string {
  if (seconds <= 0) {
    return '';
  }
  const bucket = ttlLocaleBucket(localeOverride ?? currentLocale());
  if (seconds < 60) {
    return `${seconds}${bucket === 'en' ? 's' : '秒'}`;
  }
  if (seconds < 3600) {
    return `${Math.round(seconds / 60)}${bucket === 'en' ? 'm' : '分'}`;
  }
  if (seconds < 86400) {
    const unit = bucket === 'en' ? 'h' : (bucket === 'zh-Hant' ? '時' : '时');
    return `${Math.round(seconds / 3600)}${unit}`;
  }
  if (seconds < 604800) {
    return `${Math.round(seconds / 86400)}${bucket === 'en' ? 'd' : '天'}`;
  }
  if (seconds < 2592000) {
    const unit = bucket === 'en' ? 'w' : (bucket === 'zh-Hant' ? '週' : '周');
    return `${Math.round(seconds / 604800)}${unit}`;
  }
  if (seconds < 31536000) {
    return `${Math.max(1, Math.round(seconds / 2592000))}${bucket === 'en' ? 'mo' : '月'}`;
  }
  return `${Math.max(1, Math.round(seconds / 31536000))}${bucket === 'en' ? 'y' : '年'}`;
}
