import { TdObject } from '../tdkit/TdTypes';
import { clockTime, fullDate, fullDateTime, monthDay } from './intlFormat';
import { str } from './strings';

export type CallTone = 'normal' | 'missed' | 'warning' | 'active';

export interface ParsedCallContent {
  valid: boolean;
  isGroup: boolean;
  isVideo: boolean;
  missed: boolean;
  active: boolean;
  duration: number;
  reasonType: string;
  participantCount: number;
}

export interface CallStatusPresentation {
  text: string;
  tone: CallTone;
}

export function parseCallContent(content: TdObject | undefined, outgoing: boolean): ParsedCallContent {
  const type = (content?.['@type'] as string | undefined) ?? '';
  if (type === 'messageCall') {
    const reason = content?.['discard_reason'] as TdObject | undefined;
    const reasonType = (reason?.['@type'] as string | undefined) ?? 'callDiscardReasonEmpty';
    return {
      valid: true,
      isGroup: false,
      isVideo: (content?.['is_video'] as boolean | undefined) ?? false,
      missed: reasonType === 'callDiscardReasonMissed' || reasonType === 'callDiscardReasonDeclined',
      active: false,
      duration: Math.max(0, (content?.['duration'] as number | undefined) ?? 0),
      reasonType,
      participantCount: 0
    };
  }
  if (type === 'messageGroupCall') {
    const participants = (content?.['other_participant_ids'] as TdObject[] | undefined) ?? [];
    return {
      valid: true,
      isGroup: true,
      isVideo: (content?.['is_video'] as boolean | undefined) ?? false,
      missed: !outgoing && ((content?.['was_missed'] as boolean | undefined) ?? false),
      active: (content?.['is_active'] as boolean | undefined) ?? false,
      duration: Math.max(0, (content?.['duration'] as number | undefined) ?? 0),
      reasonType: '',
      participantCount: participants.length > 0 ? participants.length + 1 : 0
    };
  }
  return {
    valid: false, isGroup: false, isVideo: false, missed: false,
    active: false, duration: 0, reasonType: '', participantCount: 0
  };
}

// Abbreviated units, so no plural forms are needed ("1 min" and "2 min" are
// both correct); the digits are small enough that grouping never applies.
export function compactCallDuration(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  if (value < 60) { return str('duration_sec', value); }
  const minutes = Math.floor(value / 60);
  const rest = value % 60;
  if (minutes < 60) {
    return rest > 0 ? str('duration_min_sec', minutes, rest) : str('duration_min', minutes);
  }
  const hours = Math.floor(minutes / 60);
  const minuteRest = minutes % 60;
  return minuteRest > 0 ? str('duration_hour_min', hours, minuteRest) : str('duration_hour', hours);
}

// The video/voice word is substituted rather than baked into 20 separate keys:
// every language that needs these sentences puts the medium in one slot
// ("未接群组%1$s通话" / "Missed group %1$s call").
export function callStatus(parsed: ParsedCallContent, outgoing: boolean): CallStatusPresentation {
  const media = parsed.isVideo ? str('call_media_video') : str('call_media_voice');
  if (parsed.isGroup) {
    if (parsed.missed) { return { text: str('call_group_missed', media), tone: 'missed' }; }
    if (parsed.active) { return { text: str('call_group_active', media), tone: 'active' }; }
    if (parsed.duration > 0) {
      return {
        text: str('call_group_duration', media, compactCallDuration(parsed.duration)),
        tone: 'normal'
      };
    }
    return { text: str('call_group', media), tone: 'normal' };
  }
  if (parsed.duration > 0) {
    const dur = compactCallDuration(parsed.duration);
    return {
      text: outgoing ? str('call_out_duration', media, dur) : str('call_in_duration', media, dur),
      tone: 'normal'
    };
  }
  if (parsed.reasonType === 'callDiscardReasonMissed') {
    return {
      text: outgoing ? str('call_missed_outgoing', media) : str('call_missed_incoming', media),
      tone: 'missed'
    };
  }
  if (parsed.reasonType === 'callDiscardReasonDeclined') {
    return {
      text: outgoing ? str('call_declined_outgoing', media) : str('call_declined_incoming', media),
      tone: 'missed'
    };
  }
  if (parsed.reasonType === 'callDiscardReasonDisconnected') {
    return { text: str('call_disconnected', media), tone: 'warning' };
  }
  if (parsed.reasonType === 'callDiscardReasonUpgradeToGroupCall') {
    return { text: str('call_upgraded_group', media), tone: 'normal' };
  }
  if (parsed.reasonType === 'callDiscardReasonHungUp') {
    return {
      text: outgoing ? str('call_hungup_outgoing', media) : str('call_hungup_incoming', media),
      tone: 'normal'
    };
  }
  return {
    text: outgoing ? str('call_outgoing', media) : str('call_incoming', media),
    tone: 'normal'
  };
}

function sameLocalDay(left: Date, right: Date): boolean {
  return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth()
    && left.getDate() === right.getDate();
}

export function callDayKey(timestamp: number): string {
  const date = new Date(Math.max(0, timestamp) * 1000);
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

export function callSectionLabel(timestamp: number, nowSeconds: number = Math.floor(Date.now() / 1000)): string {
  const date = new Date(Math.max(0, timestamp) * 1000);
  const now = new Date(nowSeconds * 1000);
  if (sameLocalDay(date, now)) { return str('date_today'); }
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (sameLocalDay(date, yesterday)) { return str('date_yesterday'); }
  if (date.getFullYear() === now.getFullYear()) { return monthDay(date); }
  return fullDate(date);
}

export function callClockLabel(timestamp: number): string {
  return clockTime(new Date(Math.max(0, timestamp) * 1000));
}

export function formatCallTime(timestamp: number): string {
  return fullDateTime(new Date(Math.max(0, timestamp) * 1000));
}
