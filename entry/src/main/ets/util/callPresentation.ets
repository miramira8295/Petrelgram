import { str } from './strings';

// 1对1 通话页的展示纯函数（可单测）。

// 通话中（active）与空闲不显示状态行，由计时/无内容代替。
export function callPhaseLabel(phase: string, isVideo: boolean): string {
  if (phase === 'dialing') {
    return str('call_state_dialing');
  }
  if (phase === 'ringing') {
    return str(isVideo ? 'call_state_incoming_video' : 'call_state_incoming_voice');
  }
  if (phase === 'connecting') {
    return str('call_state_connecting');
  }
  return '';
}

// 通话时长：m:ss，超过 1 小时 h:mm:ss；未接通返回空。
export function callDurationLabel(startedAtMs: number, nowMs: number): string {
  if (startedAtMs <= 0) {
    return '';
  }
  const totalSeconds: number = Math.max(0, Math.floor((nowMs - startedAtMs) / 1000));
  const hours: number = Math.floor(totalSeconds / 3600);
  const minutes: number = Math.floor((totalSeconds % 3600) / 60);
  const seconds: number = totalSeconds % 60;
  const two = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  if (hours > 0) {
    return `${hours}:${two(minutes)}:${two(seconds)}`;
  }
  return `${minutes}:${two(seconds)}`;
}

export function callEndLabel(reason: string, errorText: string): string {
  if (reason === 'declined') {
    return str('call_ended_declined');
  }
  if (reason === 'missed') {
    return str('call_ended_missed');
  }
  if (reason === 'busy') {
    return str('call_ended_busy');
  }
  if (reason === 'error') {
    return errorText !== '' ? errorText : str('call_ended_failed');
  }
  return str('call_ended_normal');
}
