import { LIVE_PHASE_AUDIO } from './liveViewerHeaderPresentation';
import { plural, str } from './strings';

export interface LiveViewerMediaInput {
  mode: string;
  valid: boolean;
  resolved: boolean;
  active: boolean;
  joined: boolean;
  joinedOnce: boolean;
  recovering: boolean;
  ending: boolean;
  terminalError: boolean;
  reconnectAttempt: number;
  retrySeconds: number;
  retryable: boolean;
  hasVideo: boolean;
  visualReady: boolean;
  participantCount: number;
  mediaPhase: string;
  error: string;
}

export interface LiveViewerMediaPresentation {
  kind: string;
  title: string;
  detail: string;
  badgeText: string;
  badgeTone: string;
  showProgress: boolean;
  pulse: boolean;
  retryable: boolean;
  actionText: string;
  keepVisual: boolean;
}

function countDetail(count: number): string {
  return count > 0 ? plural('live_media_in_room', count, count) : str('live_media_audio_continues');
}

export function liveViewerMediaPresentation(
  input: LiveViewerMediaInput
): LiveViewerMediaPresentation {
  if (!input.valid) {
    return {
      kind: 'invalid', title: str('live_media_invalid_title'), detail: str('live_media_invalid_detail'),
      badgeText: '', badgeTone: 'muted', showProgress: false, pulse: false,
      retryable: false, actionText: '', keepVisual: false
    };
  }
  if (input.ending) {
    return {
      kind: 'ending', title: str('live_media_ending_title'), detail: str('live_media_ending_detail'),
      badgeText: str('live_media_ending_short'), badgeTone: 'danger', showProgress: true, pulse: false,
      retryable: false, actionText: '', keepVisual: input.hasVideo
    };
  }
  if (input.resolved && !input.active) {
    return {
      kind: 'ended', title: str('live_media_ended_title'), detail: str('live_media_ended_detail'),
      badgeText: str('live_media_ended_short'), badgeTone: 'muted', showProgress: false, pulse: false,
      retryable: false, actionText: '', keepVisual: input.hasVideo
    };
  }
  if (input.terminalError) {
    return {
      kind: 'error', title: str('live_media_mode_title'), detail: str('live_media_mode_detail'),
      badgeText: str('live_media_mode_short'), badgeTone: 'danger', showProgress: false, pulse: false,
      retryable: false, actionText: '', keepVisual: input.hasVideo
    };
  }
  if (input.recovering) {
    let detail = str('live_media_resume_on_network');
    if (input.retrySeconds > 0) {
      const attempt = Math.max(1, input.reconnectAttempt);
      detail = str('live_media_attempt_retry', attempt, input.retrySeconds);
    } else if (input.reconnectAttempt > 0) {
      detail = str('live_media_attempt_n', input.reconnectAttempt);
    }
    return {
      kind: 'recovering', title: input.retrySeconds > 0 ? str('live_media_interrupted') : str('live_media_recovering'),
      detail, badgeText: str('live_media_reconnecting_short'), badgeTone: 'accent', showProgress: true, pulse: true,
      retryable: input.retryable, actionText: input.retryable ? str('live_media_retry_now') : '',
      keepVisual: input.hasVideo
    };
  }
  if (input.error !== '' && !input.joined) {
    return {
      kind: 'error', title: str('live_media_cannot_connect'),
      detail: input.retrySeconds > 0 ? str('live_media_auto_retry_in', input.retrySeconds) : str('live_media_can_reconnect'),
      badgeText: str('live_media_failed_short'), badgeTone: 'danger', showProgress: false, pulse: false,
      retryable: input.retryable, actionText: input.retryable ? str('live_media_reconnect') : '',
      keepVisual: input.hasVideo
    };
  }
  if (!input.joined && !input.joinedOnce) {
    return {
      kind: 'connecting', title: str('live_media_connecting'), detail: str('live_media_preparing'),
      badgeText: str('live_media_connecting_short'), badgeTone: 'accent', showProgress: true, pulse: true,
      retryable: false, actionText: '', keepVisual: false
    };
  }
  if (input.hasVideo) {
    if (input.mode === 'rtmp' && !input.visualReady) {
      return {
        kind: 'videoLoading', title: str('live_media_loading_video'), detail: str('live_media_syncing'),
        badgeText: str('live_media_loading_short'), badgeTone: 'accent', showProgress: true, pulse: true,
        retryable: false, actionText: '', keepVisual: false
      };
    }
    return {
      kind: 'video', title: '', detail: '', badgeText: 'LIVE', badgeTone: 'live',
      showProgress: false, pulse: true, retryable: false, actionText: '', keepVisual: true
    };
  }
  if (input.mediaPhase === LIVE_PHASE_AUDIO || input.mode === 'group') {
    return {
      kind: 'audio', title: str('live_media_audio_short'), detail: countDetail(input.participantCount),
      badgeText: 'AUDIO', badgeTone: 'audio', showProgress: false, pulse: true,
      retryable: false, actionText: '', keepVisual: false
    };
  }
  return {
    kind: 'waiting', title: str('live_media_waiting_video'), detail: str('live_media_connected_waiting'),
    badgeText: str('live_media_waiting_short'), badgeTone: 'waiting', showProgress: false, pulse: false,
    retryable: false, actionText: '', keepVisual: false
  };
}
