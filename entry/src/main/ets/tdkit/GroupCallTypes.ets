export interface GroupCallStreamInfo {
  channelId: number;
  scale: number;
  timeOffset: number;
}

export interface LiveStreamState {
  title: string;
  isActive: boolean;
  isRtmpStream: boolean;
  isJoined: boolean;
  needRejoin: boolean;
  canSendMessages: boolean;
  areMessagesAllowed: boolean;
  participantCount: number;
  streams: GroupCallStreamInfo[];
  error: string;
}

export function emptyLiveStreamState(): LiveStreamState {
  return {
    title: '',
    isActive: false, isRtmpStream: false, isJoined: false, needRejoin: false,
    canSendMessages: false, areMessagesAllowed: false,
    participantCount: 0, streams: [], error: ''
  };
}

export interface GroupCallVideoSource {
  endpointId: string;
  participantKey: string;
  name: string;
  audioSourceId: number;
  sourceGroups: string;
  isPaused: boolean;
  isScreenSharing: boolean;
  isSpeaking: boolean;
  isMuted: boolean;
}

export interface GroupCallParticipantInfo {
  key: string;
  // Changes whenever TDLib publishes a new state for this participant. ArkUI
  // uses it to rebuild the row even when the participant identity is unchanged.
  revision: number;
  audioSourceId: number;
  screenSharingAudioSourceId: number;
  senderId: number;
  senderType: string;
  name: string;
  initials: string;
  colorSeed: number;
  order: string;
  isCurrentUser: boolean;
  isSpeaking: boolean;
  isMuted: boolean;
  videoSources: GroupCallVideoSource[];
}
