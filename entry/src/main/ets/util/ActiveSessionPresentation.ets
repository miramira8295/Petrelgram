import { plural, str } from './strings';
import { TdObject } from '../tdkit/TdTypes';

export const FRESH_SESSION_PROTECTION_SECONDS: number = 24 * 60 * 60;

export type SessionErrorKind =
  'fresh' | 'missing' | 'rate_limit' | 'network' | 'qr' | 'password' | 'generic';

export interface SessionErrorPresentation {
  kind: SessionErrorKind;
  text: string;
  shouldRefresh: boolean;
}

export function sessionDeviceType(session: TdObject): string {
  const device = session['device_type'] as TdObject | undefined;
  if (device !== undefined) {
    return (device['@type'] as string | undefined) ?? '';
  }
  // Compatibility with cached objects produced by early app builds.
  const legacy = session['type'] as TdObject | undefined;
  return (legacy?.['@type'] as string | undefined) ?? '';
}

export function freshSessionSeconds(
  loginDate: number, nowSeconds: number = Math.floor(Date.now() / 1000)
): number {
  if (loginDate <= 0) { return 0; }
  return Math.max(0, loginDate + FRESH_SESSION_PROTECTION_SECONDS - nowSeconds);
}

// "in 2 hours 5 minutes" cannot be one plural resource: a plural picks its form
// from a single number, and this has two. Each unit is pluralized on its own and
// the wrapper places them — which also lets a language reorder or re-join them.
export function sessionWaitText(seconds: number): string {
  if (seconds <= 0) { return str('session_wait_later'); }
  const totalMinutes = Math.max(1, Math.ceil(seconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const minuteText = plural('session_unit_minutes', minutes, minutes);
  if (hours <= 0) { return str('session_wait_in', minuteText); }
  const hourText = plural('session_unit_hours', hours, hours);
  if (minutes === 0) { return str('session_wait_in', hourText); }
  return str('session_wait_in_two', hourText, minuteText);
}

export function inactiveSessionTtlLabel(days: number): string {
  if (days === 7) { return str('session_ttl_1_week'); }
  if (days === 30) { return str('session_ttl_1_month'); }
  if (days === 90) { return str('session_ttl_3_months'); }
  if (days === 180) { return str('session_ttl_6_months'); }
  if (days === 365 || days === 366) { return str('session_ttl_1_year'); }
  const n = Math.max(1, Math.min(366, Math.round(days)));
  return plural('session_unit_days', n, n);
}

function floodWaitSeconds(message: string): number {
  const marker = 'FLOOD_WAIT_';
  const start = message.toUpperCase().indexOf(marker);
  if (start < 0) { return 0; }
  const tail = message.substring(start + marker.length);
  let digits = '';
  for (let index = 0; index < tail.length; index += 1) {
    const code = tail.charCodeAt(index);
    if (code < 48 || code > 57) { break; }
    digits += tail.charAt(index);
  }
  const parsed = Number(digits);
  return Number.isFinite(parsed) ? parsed : 0;
}

function rateLimitText(seconds: number): string {
  if (seconds <= 0) { return str('session_error_flood'); }
  if (seconds < 60) { return str('session_error_flood_seconds', seconds); }
  const minutes = Math.max(1, Math.ceil(seconds / 60));
  return str('session_error_flood_minutes', minutes);
}

export function activeSessionError(
  rawMessage: string, fallback: string = str('session_error_generic')
): SessionErrorPresentation {
  const upper = rawMessage.toUpperCase();
  if (upper.indexOf('FRESH_RESET_AUTHORISATION_FORBIDDEN') >= 0 ||
    upper.indexOf('FRESH_RESET_AUTHORIZATION_FORBIDDEN') >= 0 ||
    upper.indexOf('SESSION_TOO_FRESH') >= 0) {
    return {
      kind: 'fresh',
      text: str('session_error_fresh_login'),
      shouldRefresh: false
    };
  }
  if (upper.indexOf('SESSION_NOT_FOUND') >= 0 || upper.indexOf('HASH_INVALID') >= 0) {
    return { kind: 'missing', text: str('session_error_stale'), shouldRefresh: true };
  }
  if (upper.indexOf('FLOOD_WAIT') >= 0 || upper.indexOf('TOO_MANY_REQUESTS') >= 0) {
    return {
      kind: 'rate_limit', text: rateLimitText(floodWaitSeconds(upper)), shouldRefresh: false
    };
  }
  if (upper.indexOf('AUTH_TOKEN_INVALID') >= 0 || upper.indexOf('AUTH_TOKEN_EXPIRED') >= 0 ||
    upper.indexOf('AUTH_TOKEN_ALREADY_ACCEPTED') >= 0 || upper.indexOf('QR') >= 0) {
    return { kind: 'qr', text: str('session_error_qr_invalid'), shouldRefresh: false };
  }
  if (upper.indexOf('PASSWORD_HASH_INVALID') >= 0 || upper.indexOf('PASSWORD') >= 0) {
    return { kind: 'password', text: str('session_error_needs_2fa'), shouldRefresh: true };
  }
  if (upper.indexOf('TIMEOUT') >= 0 || upper.indexOf('NETWORK') >= 0 ||
    upper.indexOf('CONNECTION') >= 0 || upper.indexOf('OFFLINE') >= 0) {
    return { kind: 'network', text: str('session_error_network'), shouldRefresh: false };
  }
  return { kind: 'generic', text: fallback, shouldRefresh: false };
}
