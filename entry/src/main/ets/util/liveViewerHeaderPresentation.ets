import { plural, str } from './strings';

// The header used to work out which of these it was by substring-matching the
// Chinese sentence in mediaStatus. That was wrong twice over: it misfired on
// unrelated text ("摄像头首帧等待超时，请重试" contains 重试, so a camera
// timeout was presented as a connection recovery, pulse and all), and it would
// have stopped matching altogether — silently, with no error — the moment those
// pages were translated. The pages now declare the phase where they set the
// text, so the two cannot drift apart.
export const LIVE_PHASE_NONE = 'none';
export const LIVE_PHASE_RECOVERING = 'recovering';
export const LIVE_PHASE_WAITING = 'waiting';
export const LIVE_PHASE_AUDIO = 'audio';

export interface LiveViewerHeaderInput {
  valid: boolean;
  resolved: boolean;
  queryFailed: boolean;
  active: boolean;
  joined: boolean;
  joinedOnce: boolean;
  recovering: boolean;
  ending: boolean;
  terminalError: boolean;
  reconnectAttempt: number;
  retrySeconds: number;
  canMinimize: boolean;
  participantCount: number;
  mediaPhase: string;
}

export interface LiveViewerHeaderPresentation {
  kind: string;
  statusText: string;
  fullscreenText: string;
  pulse: boolean;
  retryable: boolean;
  actionsEnabled: boolean;
}

export function liveViewerHeaderPresentation(
  input: LiveViewerHeaderInput
): LiveViewerHeaderPresentation {
  if (!input.valid) {
    return {
      kind: 'invalid', statusText: str('live_status_invalid'), fullscreenText: str('live_short_invalid'),
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.ending) {
    return {
      kind: 'ending', statusText: str('live_status_ending'), fullscreenText: str('live_short_ending'),
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.resolved && !input.active) {
    return {
      kind: 'ended', statusText: str('live_status_ended'), fullscreenText: str('live_short_ended'),
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.terminalError) {
    return {
      kind: 'error', statusText: str('live_status_mode_changed'), fullscreenText: str('live_short_go_back'),
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.queryFailed && !input.joinedOnce && !input.joined) {
    return {
      kind: 'error', statusText: str('live_status_connect_failed'), fullscreenText: str('live_short_connect_failed'),
      pulse: false, retryable: true, actionsEnabled: input.canMinimize
    };
  }
  if (input.recovering || input.mediaPhase === LIVE_PHASE_RECOVERING) {
    const retryText = input.retrySeconds > 0
      ? str('live_status_retry_in', input.retrySeconds)
      : str(input.reconnectAttempt > 0 ? 'live_status_reconnecting' : 'live_status_recovering');
    return {
      kind: 'recovering', statusText: retryText, fullscreenText: str('live_short_reconnecting'),
      pulse: true, retryable: true, actionsEnabled: input.canMinimize
    };
  }
  if (!input.resolved && !input.joinedOnce && !input.joined) {
    return {
      kind: 'connecting', statusText: str('live_status_connecting'), fullscreenText: str('live_short_connecting'),
      pulse: true, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  if (input.mediaPhase === LIVE_PHASE_WAITING) {
    return {
      kind: 'waiting', statusText: str('live_status_waiting_host'), fullscreenText: str('live_short_waiting'),
      pulse: false, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  if (input.mediaPhase === LIVE_PHASE_AUDIO) {
    return {
      kind: 'audio', statusText: str('live_status_audio'), fullscreenText: str('live_short_audio'),
      pulse: true, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  if (!input.joined && !input.joinedOnce) {
    return {
      kind: 'joining', statusText: str('live_status_joining'), fullscreenText: str('live_short_joining'),
      pulse: true, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  return {
    kind: 'live',
    statusText: input.participantCount > 0
      ? plural('live_status_watching', input.participantCount, input.participantCount) : str('live_status_live'),
    fullscreenText: 'LIVE', pulse: true, retryable: false, actionsEnabled: input.canMinimize
  };
}
