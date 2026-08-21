import { common } from '@kit.AbilityKit';
import {
  ComponentContent, OverlayManager, router, UIContext
} from '@kit.ArkUI';
import { GroupCallParticipantsStore } from '../../store/GroupCallParticipantsStore';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import { liveStreamBackgroundTask } from '../../services/LiveStreamBackgroundTask';
import { TgcallsGroupSession } from '../../services/TgcallsGroupSession';
import {
  GroupCallParticipantInfo, GroupCallStreamInfo, GroupCallVideoSource, LiveStreamState
} from '../../tdkit/GroupCallTypes';
import {
  getGroupCall, leaveGroupCall, setGroupCallParticipantIsSpeaking
} from '../../tdkit/GroupCallApi';
import { getTdClient } from '../../tdkit/Globals';
import { confirmLeaveLiveStream, setLiveStreamKeepScreenOn } from './LiveViewerUi';
import {
  KEY_POWER_CALL_ANIMATIONS, powerAnimationDuration
} from '../../store/AppSettings';
import {
  FloatingDragAnchor, FloatingDragBounds, clampFloatingTranslation, dragFloatingTranslation
} from '../../util/floatingDrag';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

const FLOAT_BACKGROUND: string = '#101820';
const FLOAT_PANEL: string = '#E9142029';
const FLOAT_TEXT: string = '#F4F7F9';
const FLOAT_SUBTEXT: string = '#A7B4BE';
const FLOAT_GREEN: string = '#39D98A';
const FLOAT_RED: string = '#FF405C';
const DRAG_MARGIN: number = 8;
const HEALTH_INTERVAL_MS: number = 5000;
const RECONNECT_GRACE_MS: number = 5000;

export interface FloatingLiveDescriptor {
  groupCallId: number;
  chatId: number;
  isRtmp: boolean;
  title: string;
  participantCount: number;
  primarySource: GroupCallVideoSource | null;
}

export interface FloatingLiveState {
  visible: boolean;
  large: boolean;
  title: string;
  participantCount: number;
  status: string;
  hasVideo: boolean;
  recovering: boolean;
  isRtmp: boolean;
  sourceName: string;
  visualReady: boolean;
  ended: boolean;
  isMuted: boolean;
  actionBusy: boolean;
  error: boolean;
}

// In-memory ownership packet. It never crosses a process boundary and contains
// the same live session object, so minimizing/restoring does not join again.
export interface FloatingLiveSessionHandoff {
  descriptor: FloatingLiveDescriptor;
  session: TgcallsGroupSession;
  liveState: LiveStreamState;
  isMuted: boolean;
  mediaConnected: boolean;
  hasJoinedOnce: boolean;
  visualReady: boolean;
  videoAspectRatio: number;
  localVideoMode: number;
  localVideoActive: boolean;
  desiredLocalVideoMode: number;
  screenShareActive: boolean;
  screenShareDesired: boolean;
}

type FloatingLiveListener = (state: FloatingLiveState) => void;

interface FloatingSurfaceBinding {
  surfaceId: string;
  width: number;
  height: number;
}

class FloatingOverlayArgs {
  controller: LiveFloatingWindowController;

  constructor(controller: LiveFloatingWindowController) {
    this.controller = controller;
  }
}

function cloneSource(source: GroupCallVideoSource | null): GroupCallVideoSource | null {
  if (source === null) { return null; }
  return {
    endpointId: source.endpointId,
    participantKey: source.participantKey,
    name: source.name,
    audioSourceId: source.audioSourceId,
    sourceGroups: source.sourceGroups,
    isPaused: source.isPaused,
    isScreenSharing: source.isScreenSharing,
    isSpeaking: source.isSpeaking,
    isMuted: source.isMuted
  };
}

function copyState(state: FloatingLiveState): FloatingLiveState {
  return {
    visible: state.visible,
    large: state.large,
    title: state.title,
    participantCount: state.participantCount,
    status: state.status,
    hasVideo: state.hasVideo,
    recovering: state.recovering,
    isRtmp: state.isRtmp,
    sourceName: state.sourceName,
    visualReady: state.visualReady,
    ended: state.ended,
    isMuted: state.isMuted,
    actionBusy: state.actionBusy,
    error: state.error
  };
}

function copyLiveState(state: LiveStreamState): LiveStreamState {
  return {
    title: state.title,
    isActive: state.isActive,
    isRtmpStream: state.isRtmpStream,
    isJoined: state.isJoined,
    needRejoin: state.needRejoin,
    canSendMessages: state.canSendMessages,
    areMessagesAllowed: state.areMessagesAllowed,
    participantCount: state.participantCount,
    streams: state.streams,
    error: state.error
  };
}

function uniqueVideoChannelIds(streams: GroupCallStreamInfo[]): number[] {
  const seen: Set<number> = new Set();
  const result: number[] = [];
  for (const stream of streams) {
    if (stream.channelId !== 0 && !seen.has(stream.channelId)) {
      seen.add(stream.channelId);
      result.push(stream.channelId);
    }
  }
  return result;
}

export class LiveFloatingWindowController {
  private descriptor: FloatingLiveDescriptor | null = null;
  private state: FloatingLiveState = {
    visible: false,
    large: false,
    title: '',
    participantCount: 0,
    status: str('lfw_switching'),
    hasVideo: false,
    recovering: false,
    isRtmp: false,
    sourceName: '',
    visualReady: false,
    ended: false,
    isMuted: true,
    actionBusy: false,
    error: false
  };
  private listeners: FloatingLiveListener[] = [];
  private overlayManager: OverlayManager | null = null;
  private overlayContent: ComponentContent<FloatingOverlayArgs> | null = null;
  private abilityContext: common.UIAbilityContext | null = null;
  private session: TgcallsGroupSession | null = null;
  private liveStore: LiveStreamStore | null = null;
  private participantStore: GroupCallParticipantsStore | null = null;
  private offLive: (() => void) | null = null;
  private offParticipants: (() => void) | null = null;
  private primarySource: GroupCallVideoSource | null = null;
  private requestedEndpoint: string = '';
  private surfaceBinding: FloatingSurfaceBinding | null = null;
  private generation: number = 0;
  private hasJoinedOnce: boolean = false;
  private reconnectTimer: number = -1;
  private healthTimer: number = -1;
  private refreshInFlight: boolean = false;
  private seamlessLiveState: LiveStreamState | null = null;
  private seamlessMediaConnected: boolean = false;
  private seamlessLocalVideoMode: number = 0;
  private seamlessLocalVideoActive: boolean = false;
  private seamlessDesiredLocalVideoMode: number = 0;
  private seamlessScreenShareActive: boolean = false;
  private seamlessScreenShareDesired: boolean = false;
  private seamlessVideoAspectRatio: number = 0;

  isVisible(): boolean {
    return this.descriptor !== null && this.state.visible;
  }

  isShowing(groupCallId: number, isRtmp: boolean): boolean {
    return this.isVisible() && this.descriptor?.groupCallId === groupCallId &&
      this.descriptor?.isRtmp === isRtmp;
  }

  subscribe(listener: FloatingLiveListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(copyState(this.state));
    return (): void => {
      this.listeners = this.listeners.filter(
        (current: FloatingLiveListener): boolean => current !== listener
      );
    };
  }

  showSeamless(
    uiContext: UIContext, abilityContext: common.UIAbilityContext,
    handoff: FloatingLiveSessionHandoff
  ): boolean {
    if (this.isVisible() || handoff.descriptor.groupCallId <= 0) { return false; }
    const descriptor = handoff.descriptor;
    this.abilityContext = abilityContext;
    this.descriptor = {
      groupCallId: descriptor.groupCallId,
      chatId: descriptor.chatId,
      isRtmp: descriptor.isRtmp,
      title: descriptor.title,
      participantCount: descriptor.participantCount,
      primarySource: cloneSource(descriptor.primarySource)
    };
    this.primarySource = cloneSource(descriptor.primarySource);
    this.requestedEndpoint = descriptor.isRtmp
      ? (uniqueVideoChannelIds(handoff.liveState.streams).length > 0 ? 'unified' : '')
      : (descriptor.primarySource?.endpointId ?? '');
    this.seamlessLiveState = copyLiveState(handoff.liveState);
    this.seamlessMediaConnected = handoff.mediaConnected;
    this.seamlessLocalVideoMode = handoff.localVideoMode;
    this.seamlessLocalVideoActive = handoff.localVideoActive;
    this.seamlessDesiredLocalVideoMode = handoff.desiredLocalVideoMode;
    this.seamlessScreenShareActive = handoff.screenShareActive;
    this.seamlessScreenShareDesired = handoff.screenShareDesired;
    this.seamlessVideoAspectRatio = handoff.videoAspectRatio;
    this.hasJoinedOnce = handoff.hasJoinedOnce;
    this.state = {
      visible: true,
      large: false,
      title: descriptor.title !== '' ? descriptor.title : str('lfw_live'),
      participantCount: descriptor.participantCount,
      status: handoff.visualReady
        ? (this.requestedEndpoint !== '' ? str('lfw_playing') : str('lfw_audio_playing'))
        : str('lfw_switching'),
      hasVideo: this.requestedEndpoint !== '',
      recovering: !handoff.mediaConnected,
      isRtmp: descriptor.isRtmp,
      sourceName: descriptor.primarySource?.name ?? '',
      visualReady: handoff.visualReady,
      ended: !handoff.liveState.isActive,
      isMuted: handoff.isMuted,
      actionBusy: false,
      error: false
    };
    try {
      this.overlayManager = uiContext.getOverlayManager();
      this.overlayContent = new ComponentContent<FloatingOverlayArgs>(
        uiContext, wrapBuilder(buildFloatingLiveOverlay), new FloatingOverlayArgs(this)
      );
      this.overlayManager.addComponentContent(this.overlayContent);
    } catch (caught) {
      logE(`LiveFloating.showSeamless overlay failed: ${caught}`);
      this.removeOverlay();
      this.descriptor = null;
      this.primarySource = null;
      this.requestedEndpoint = '';
      this.seamlessLiveState = null;
      this.state.visible = false;
      return false;
    }
    this.session = handoff.session;
    this.startSeamlessRuntime();
    setLiveStreamKeepScreenOn(abilityContext, true);
    liveStreamBackgroundTask.start(abilityContext, !handoff.isMuted);
    this.emit();
    return true;
  }

  expand(): void {
    if (!this.isVisible() || this.state.large) { return; }
    this.state.large = true;
    this.emit();
  }

  collapse(): void {
    if (!this.isVisible() || !this.state.large) { return; }
    this.state.large = false;
    this.emit();
  }

  attachSurface(surfaceId: string, width: number, height: number): void {
    if (surfaceId === '') { return; }
    this.surfaceBinding = {
      surfaceId,
      width: Math.max(1, width),
      height: Math.max(1, height)
    };
    this.bindCurrentSurface();
  }

  resizeSurface(width: number, height: number): void {
    const binding = this.surfaceBinding;
    if (binding === null || width <= 0 || height <= 0) { return; }
    binding.width = Math.round(width);
    binding.height = Math.round(height);
    this.bindCurrentSurface();
  }

  detachSurface(surfaceId: string): void {
    if (this.surfaceBinding?.surfaceId !== surfaceId) { return; }
    if (this.requestedEndpoint !== '') {
      this.session?.setVideoSurface(this.requestedEndpoint, '0');
    }
    this.surfaceBinding = null;
  }

  resumeMedia(): void {
    this.session?.resumeMedia();
    if (this.primarySource !== null && !this.descriptor?.isRtmp) {
      this.session?.setVideoChannel(
        this.primarySource.endpointId,
        this.primarySource.audioSourceId,
        this.primarySource.sourceGroups
      );
    }
    this.bindCurrentSurface();
    this.refreshGroupCall();
  }

  requestClose(): void {
    if (this.state.actionBusy) { return; }
    confirmLeaveLiveStream((): void => {
      this.dismissAndLeave();
    });
  }

  async closeForAccountSwitch(): Promise<void> {
    const groupCallId = this.descriptor?.groupCallId ?? 0;
    if (this.abilityContext !== null) {
      setLiveStreamKeepScreenOn(this.abilityContext, false);
    }
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.state.visible = false;
    this.emit();
    liveStreamBackgroundTask.stop();
    if (groupCallId <= 0) { return; }
    try {
      await leaveGroupCall(getTdClient(), groupCallId);
    } catch (caught) {
      const error = caught as Error;
      logE(`LiveFloating.accountSwitch leave failed: ${error.message}`);
    }
  }

  async prepareForOpeningFullPage(): Promise<void> {
    if (this.descriptor === null) { return; }
    const groupCallId = this.descriptor.groupCallId;
    if (this.abilityContext !== null) {
      setLiveStreamKeepScreenOn(this.abilityContext, false);
    }
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.state.visible = false;
    this.emit();
    liveStreamBackgroundTask.stop();
    try {
      await leaveGroupCall(getTdClient(), groupCallId);
    } catch (caught) {
      const error = caught as Error;
      logE(`LiveFloating.prepareForOpening leave failed: ${error.message}`);
    }
  }

  async restoreFullPage(): Promise<void> {
    const descriptor = this.descriptor;
    if (descriptor === null || this.state.actionBusy) { return; }
    await this.openFullPage(descriptor);
  }

  takeSeamlessSession(
    groupCallId: number, isRtmp: boolean
  ): FloatingLiveSessionHandoff | null {
    const descriptor = this.descriptor;
    const session = this.session;
    const liveState = this.seamlessLiveState;
    if (descriptor === null || session === null || liveState === null ||
      descriptor.groupCallId !== groupCallId || descriptor.isRtmp !== isRtmp) {
      return null;
    }
    const packet: FloatingLiveSessionHandoff = {
      descriptor: {
        groupCallId: descriptor.groupCallId,
        chatId: descriptor.chatId,
        isRtmp: descriptor.isRtmp,
        title: this.state.title,
        participantCount: this.state.participantCount,
        primarySource: cloneSource(this.primarySource)
      },
      session,
      liveState: copyLiveState(liveState),
      isMuted: this.state.isMuted,
      mediaConnected: this.seamlessMediaConnected,
      hasJoinedOnce: this.hasJoinedOnce,
      visualReady: this.state.visualReady,
      videoAspectRatio: this.seamlessVideoAspectRatio,
      localVideoMode: this.seamlessLocalVideoMode,
      localVideoActive: this.seamlessLocalVideoActive,
      desiredLocalVideoMode: this.seamlessDesiredLocalVideoMode,
      screenShareActive: this.seamlessScreenShareActive,
      screenShareDesired: this.seamlessScreenShareDesired
    };
    if (this.requestedEndpoint !== '') {
      session.setVideoSurface(this.requestedEndpoint, '0');
    }
    if (!descriptor.isRtmp && this.seamlessLocalVideoActive) {
      session.setLocalVideoSurface('0');
    }
    session.setListeners();
    this.session = null;
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.primarySource = null;
    this.state.visible = false;
    this.state.actionBusy = false;
    this.emit();
    return packet;
  }

  private async openFullPage(descriptor: FloatingLiveDescriptor): Promise<void> {
    this.state.actionBusy = true;
    this.state.large = true;
    this.state.status = str('lfw_returning');
    this.emit();
    const params: Record<string, Object> = {
      'groupCallId': descriptor.groupCallId,
      'chatId': descriptor.chatId,
      'initialTitle': this.state.title,
      'initialParticipantCount': this.state.participantCount
    };
    try {
      await router.pushUrl({
        url: descriptor.isRtmp
          ? 'pages/chat/RtmpLiveStreamViewerPage' : 'pages/chat/LiveStreamViewerPage',
        params
      });
    } catch (caught) {
      if (this.descriptor?.groupCallId === descriptor.groupCallId) {
        this.state.actionBusy = false;
        this.state.status = this.state.hasVideo ? str('lfw_playing') : str('lfw_audio_playing');
        this.emit();
      }
      logE(`LiveFloating.restore failed: ${caught}`);
    }
  }

  private dismissAndLeave(): void {
    const groupCallId = this.descriptor?.groupCallId ?? 0;
    if (this.abilityContext !== null) {
      setLiveStreamKeepScreenOn(this.abilityContext, false);
    }
    this.removeOverlay();
    this.stopRuntime();
    this.descriptor = null;
    this.state.visible = false;
    this.emit();
    liveStreamBackgroundTask.stop();
    if (groupCallId > 0) {
      leaveGroupCall(getTdClient(), groupCallId).catch((caught: Error): void => {
        logE(`LiveFloating.dismiss leave failed: ${caught.message}`);
      });
    }
  }

  private startSeamlessRuntime(): void {
    const descriptor = this.descriptor;
    const session = this.session;
    if (descriptor === null || session === null || descriptor.groupCallId <= 0) { return; }
    const sequence = ++this.generation;
    const client = getTdClient();
    this.liveStore = new LiveStreamStore(client, descriptor.groupCallId);
    this.offLive = this.liveStore.subscribe(
      (state: LiveStreamState): void => this.onLiveState(state)
    );
    if (!descriptor.isRtmp) {
      this.participantStore = new GroupCallParticipantsStore(client, descriptor.groupCallId);
      this.offParticipants = this.participantStore.subscribe(
        (participants: GroupCallParticipantInfo[]): void => this.onParticipants(participants)
      );
    }
    session.setListeners(
      (connected: boolean): void => this.onNetworkState(session, sequence, connected),
      (audioSourceId: number, speaking: boolean): void => {
        if (this.isCurrent(session, sequence)) {
          this.onFloatingAudioActivity(session, audioSourceId, speaking);
        }
      },
      (streams: GroupCallStreamInfo[], unified: boolean): void => {
        if (this.isCurrent(session, sequence) && descriptor.isRtmp && unified) {
          this.configureRtmpStreams(streams);
        }
      },
      (received: boolean): void => {
        if (!this.isCurrent(session, sequence) || !descriptor.isRtmp) { return; }
        if (received && this.state.hasVideo) { this.state.visualReady = true; }
        this.setPlaybackState(
          received ? (this.state.hasVideo ? str('lfw_playing') : str('lfw_audio_playing')) : str('lfw_buffering'),
          this.state.hasVideo,
          !received
        );
      },
      (mode: number, active: boolean, _error: number): void => {
        if (!this.isCurrent(session, sequence)) { return; }
        if (mode === 3) {
          this.seamlessScreenShareActive = active;
          this.seamlessScreenShareDesired = active;
          return;
        }
        this.seamlessLocalVideoMode = mode;
        this.seamlessLocalVideoActive = active;
        if (active) {
          this.seamlessDesiredLocalVideoMode = mode;
        } else if (mode === this.seamlessDesiredLocalVideoMode) {
          this.seamlessDesiredLocalVideoMode = 0;
        }
      },
      (_endpointId: string, width: number, height: number): void => {
        if (!this.isCurrent(session, sequence) || width <= 0 || height <= 0) { return; }
        this.seamlessVideoAspectRatio = width / height;
        this.state.visualReady = true;
        this.emit();
      }
    );
    this.healthTimer = setInterval((): void => {
      this.session?.resumeMedia();
      this.bindCurrentSurface();
      this.refreshGroupCall();
    }, HEALTH_INTERVAL_MS);
    if (descriptor.isRtmp) {
      this.configureRtmpStreams(this.seamlessLiveState?.streams ?? []);
    } else {
      if (this.primarySource !== null) { this.configurePrimarySource(this.primarySource); }
      this.participantStore?.load(100).catch((caught: Error): void => {
        logE(`LiveFloating.loadParticipants failed: ${caught.message}`);
      });
    }
    session.resumeMedia();
    this.bindCurrentSurface();
    this.refreshGroupCall();
  }

  private stopRuntime(): void {
    this.generation += 1;
    this.clearReconnectTimer();
    if (this.healthTimer !== -1) {
      clearInterval(this.healthTimer);
      this.healthTimer = -1;
    }
    if (this.offParticipants !== null) {
      this.offParticipants();
      this.offParticipants = null;
    }
    this.participantStore?.dispose();
    this.participantStore = null;
    if (this.offLive !== null) {
      this.offLive();
      this.offLive = null;
    }
    this.liveStore?.dispose();
    this.liveStore = null;
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
      this.session = null;
    }
    this.requestedEndpoint = '';
    this.surfaceBinding = null;
    this.hasJoinedOnce = false;
    this.refreshInFlight = false;
    this.seamlessLiveState = null;
    this.seamlessMediaConnected = false;
    this.seamlessLocalVideoMode = 0;
    this.seamlessLocalVideoActive = false;
    this.seamlessDesiredLocalVideoMode = 0;
    this.seamlessScreenShareActive = false;
    this.seamlessScreenShareDesired = false;
    this.seamlessVideoAspectRatio = 0;
  }

  private isCurrent(session: TgcallsGroupSession, sequence: number): boolean {
    return this.descriptor !== null && this.session === session && this.generation === sequence;
  }

  private onNetworkState(
    session: TgcallsGroupSession, sequence: number, connected: boolean
  ): void {
    if (!this.isCurrent(session, sequence)) { return; }
    this.seamlessMediaConnected = connected;
    if (connected) {
      this.clearReconnectTimer();
      this.state.error = false;
      session.resumeMedia();
      this.bindCurrentSurface();
      this.setPlaybackState(
        this.state.hasVideo ? str('lfw_playing') : str('lfw_audio_playing'),
        this.state.hasVideo,
        false
      );
      return;
    }
    if (this.hasJoinedOnce) {
      this.setPlaybackState(str('lfw_recovering'), this.state.hasVideo, true);
      this.scheduleReconnect(RECONNECT_GRACE_MS);
    }
  }

  private onLiveState(state: LiveStreamState): void {
    if (this.descriptor === null) { return; }
    const next = copyLiveState(state);
    if (next.streams.length === 0 && this.seamlessLiveState !== null &&
      this.seamlessLiveState.streams.length > 0) {
      next.streams = this.seamlessLiveState.streams;
    }
    this.seamlessLiveState = next;
    this.state.title = state.title !== '' ? state.title : this.state.title;
    this.state.participantCount = state.participantCount;
    if (!state.isActive && this.hasJoinedOnce) {
      this.clearReconnectTimer();
      if (this.abilityContext !== null) {
        setLiveStreamKeepScreenOn(this.abilityContext, false);
      }
      this.state.ended = true;
      this.state.error = false;
      this.setPlaybackState(str('lfw_ended'), this.state.hasVideo, false);
    } else if (state.needRejoin || (this.hasJoinedOnce && !state.isJoined)) {
      this.state.ended = false;
      this.setPlaybackState(str('lfw_rejoining'), this.state.hasVideo, true);
      this.scheduleReconnect(500);
    } else {
      this.state.ended = false;
      this.emit();
    }
  }

  private onParticipants(participants: GroupCallParticipantInfo[]): void {
    const current = participants.find(
      (participant: GroupCallParticipantInfo): boolean => participant.isCurrentUser
    );
    if (current !== undefined && current.isMuted !== this.state.isMuted) {
      this.state.isMuted = current.isMuted;
      this.session?.setMuted(current.isMuted);
      liveStreamBackgroundTask.setRecording(!current.isMuted);
    }
    const sources: GroupCallVideoSource[] = [];
    for (const participant of participants) {
      for (const source of participant.videoSources) { sources.push(source); }
    }
    if (sources.length === 0) {
      // A freshly-created participant store emits an empty snapshot before
      // TDLib has delivered the loaded participants. Keep the handed-off
      // source alive through that gap so minimizing cannot blank the video.
      if (this.primarySource === null) {
        this.setPlaybackState(str('lfw_audio_playing'), false, this.state.recovering);
      }
      return;
    }
    sources.sort((left: GroupCallVideoSource, right: GroupCallVideoSource): number => {
      if (left.isScreenSharing !== right.isScreenSharing) {
        return left.isScreenSharing ? -1 : 1;
      }
      if (left.isSpeaking !== right.isSpeaking) { return left.isSpeaking ? -1 : 1; }
      return left.endpointId.localeCompare(right.endpointId);
    });
    const previousEndpoint = this.primarySource?.endpointId ?? '';
    const retained = sources.find(
      (source: GroupCallVideoSource): boolean => source.endpointId === previousEndpoint
    );
    this.configurePrimarySource(retained ?? sources[0]);
  }

  private onFloatingAudioActivity(
    session: TgcallsGroupSession, audioSourceId: number, speaking: boolean
  ): void {
    if (this.session !== session || audioSourceId === 0) { return; }
    this.participantStore?.applyAudioActivity(audioSourceId, speaking);
    const descriptor = this.descriptor;
    if (descriptor === null || descriptor.isRtmp) { return; }
    setGroupCallParticipantIsSpeaking(
      getTdClient(), descriptor.groupCallId, audioSourceId, speaking
    ).then((sender): void => {
      if (this.session === session) {
        this.participantStore?.applyAudioActivity(audioSourceId, speaking, sender);
      }
    }).catch((caught: Error): void => {
      logE(`LiveFloating.set speaking failed: ${caught.message}`);
    });
  }

  private configurePrimarySource(source: GroupCallVideoSource): void {
    const session = this.session;
    if (session === null) {
      this.primarySource = cloneSource(source);
      return;
    }
    if (this.requestedEndpoint !== '' && this.requestedEndpoint !== source.endpointId) {
      session.setVideoSurface(this.requestedEndpoint, '0');
      session.removeVideoChannel(this.requestedEndpoint);
    }
    this.primarySource = cloneSource(source);
    this.requestedEndpoint = source.endpointId;
    session.setVideoChannel(source.endpointId, source.audioSourceId, source.sourceGroups);
    this.state.hasVideo = true;
    this.state.sourceName = source.name;
    this.bindCurrentSurface();
    this.emit();
  }

  private configureRtmpStreams(streams: GroupCallStreamInfo[]): void {
    if (this.seamlessLiveState !== null) {
      const next = copyLiveState(this.seamlessLiveState);
      next.streams = streams;
      this.seamlessLiveState = next;
    }
    const ids = uniqueVideoChannelIds(streams);
    if (ids.length === 0) {
      this.requestedEndpoint = '';
      this.state.visualReady = false;
      this.setPlaybackState(str('lfw_waiting_host'), false, this.state.recovering);
      return;
    }
    this.requestedEndpoint = 'unified';
    this.session?.setVideoChannel('unified', 0, `SIM=${ids.join(',')}`);
    this.state.hasVideo = true;
    this.state.sourceName = this.state.title;
    this.bindCurrentSurface();
    this.emit();
  }

  private bindCurrentSurface(): void {
    const binding = this.surfaceBinding;
    if (binding === null || this.requestedEndpoint === '') { return; }
    this.session?.setVideoSurface(
      this.requestedEndpoint, binding.surfaceId, binding.width, binding.height
    );
  }

  private scheduleReconnect(delayMs: number): void {
    if (this.descriptor === null || this.state.ended || this.reconnectTimer !== -1) { return; }
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      if (this.descriptor === null || this.state.ended) { return; }
      // The floating window always owns the exact Session handed off by the
      // full viewer. Keep it alive; hard rejoin belongs to the full page where
      // camera and screen-share recovery context is available.
      this.session?.resumeMedia();
      this.bindCurrentSurface();
      this.refreshGroupCall();
      this.state.error = true;
      this.setPlaybackState(str('lfw_still_down'), this.state.hasVideo, true);
    }, Math.max(0, delayMs));
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private async refreshGroupCall(): Promise<void> {
    const descriptor = this.descriptor;
    if (descriptor === null || this.refreshInFlight) { return; }
    this.refreshInFlight = true;
    try {
      const groupCall = await getGroupCall(getTdClient(), descriptor.groupCallId);
      if (this.descriptor?.groupCallId === descriptor.groupCallId) {
        this.liveStore?.applyGroupCall(groupCall);
      }
    } catch (caught) {
      const error = caught as Error;
      logE(`LiveFloating.refresh failed: ${error.message}`);
    } finally {
      this.refreshInFlight = false;
    }
  }

  private setPlaybackState(status: string, hasVideo: boolean, recovering: boolean): void {
    this.state.status = status;
    this.state.hasVideo = hasVideo;
    this.state.recovering = recovering;
    this.emit();
  }

  private emit(): void {
    const snapshot = copyState(this.state);
    for (const listener of this.listeners) { listener(snapshot); }
  }

  private removeOverlay(): void {
    const content = this.overlayContent;
    if (content !== null) {
      try {
        this.overlayManager?.removeComponentContent(content);
      } catch (caught) {
        logE(`LiveFloating.removeOverlay failed: ${caught}`);
      }
      content.dispose();
    }
    this.overlayContent = null;
    this.overlayManager = null;
  }
}

export const floatingLiveWindow: LiveFloatingWindowController =
  new LiveFloatingWindowController();

@Component
struct FloatingLiveOverlay {
  controller: LiveFloatingWindowController = floatingLiveWindow;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('appForegroundEpoch') @Watch('onForegroundEpoch') foregroundEpoch: number = 0;
  @State state: FloatingLiveState = {
    visible: false,
    large: false,
    title: '',
    participantCount: 0,
    status: '',
    hasVideo: false,
    recovering: false,
    isRtmp: false,
    sourceName: '',
    visualReady: false,
    ended: false,
    isMuted: true,
    actionBusy: false,
    error: false
  };
  private off: (() => void) | null = null;
  private surfaceController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  @State controlsVisible: boolean = true;
  @State dragX: number = 0;
  @State dragY: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private rootOriginX: number = 0;
  private rootOriginY: number = 0;
  private dragBounds: FloatingDragBounds | null = null;
  private dragAnchor: FloatingDragAnchor | null = null;

  aboutToAppear(): void {
    this.off = this.controller.subscribe((state: FloatingLiveState): void => {
      this.state = state;
    });
  }

  aboutToDisappear(): void {
    if (this.surfaceId !== '') {
      this.controller.detachSurface(this.surfaceId);
      this.surfaceId = '';
    }
    if (this.off !== null) {
      this.off();
      this.off = null;
    }
  }

  private onForegroundEpoch(): void {
    this.controller.resumeMedia();
  }

  private refreshSurfaceSize(): void {
    if (this.surfaceId === '') { return; }
    const rect: SurfaceRect = this.surfaceController.getXComponentSurfaceRect();
    this.controller.resizeSurface(
      Math.max(1, Math.round(rect.surfaceWidth)),
      Math.max(1, Math.round(rect.surfaceHeight))
    );
  }

  private onPlayerTap(): void {
    if (!this.state.large) {
      this.controlsVisible = true;
      this.controller.expand();
      return;
    }
    this.controlsVisible = !this.controlsVisible;
  }

  private collapsePlayer(): void {
    this.controlsVisible = true;
    this.controller.collapse();
  }

  private onRootArea(area: Area): void {
    this.rootOriginX = Number(area.globalPosition.x ?? 0);
    this.rootOriginY = Number(area.globalPosition.y ?? 0);
    this.dragBounds = {
      width: Number(area.width),
      height: Number(area.height),
      margin: DRAG_MARGIN
    };
    this.reclampDrag();
  }

  // onAreaChange reports the layout position, which the drag translation does
  // not move, so this anchor stays the fixed reference the clamp math needs.
  private onPlayerArea(area: Area): void {
    this.dragAnchor = {
      x: Number(area.globalPosition.x ?? 0) - this.rootOriginX,
      y: Number(area.globalPosition.y ?? 0) - this.rootOriginY,
      width: Number(area.width),
      height: Number(area.height)
    };
    this.reclampDrag();
  }

  private reclampDrag(): void {
    if (this.dragAnchor === null || this.dragBounds === null) { return; }
    const held = clampFloatingTranslation(
      this.dragX, this.dragY, this.dragAnchor, this.dragBounds
    );
    this.dragX = held.x;
    this.dragY = held.y;
  }

  private onPanUpdate(event: GestureEvent): void {
    if (this.dragAnchor === null || this.dragBounds === null) { return; }
    const next = dragFloatingTranslation(
      this.panStartX, this.panStartY,
      event.offsetX, event.offsetY,
      this.dragAnchor, this.dragBounds
    );
    this.dragX = next.x;
    this.dragY = next.y;
  }

  build() {
    Column() {
      // Layout-only spacers must not become full-screen touch targets. The
      // overlay root is global, so a default-hit-test Blank here would swallow
      // taps before the chat page underneath ever sees them.
      Blank().hitTestBehavior(HitTestMode.None);
      Row() {
        Blank().hitTestBehavior(HitTestMode.None);
        Stack({ alignContent: Alignment.Center }) {
          XComponent({
            id: 'floating_live_primary_video',
            type: XComponentType.TEXTURE,
            controller: this.surfaceController
          })
            .onLoad((): void => {
              const rect: SurfaceRect = this.surfaceController.getXComponentSurfaceRect();
              this.surfaceId = this.surfaceController.getXComponentSurfaceId();
              this.controller.attachSurface(
                this.surfaceId,
                Math.max(1, Math.round(rect.surfaceWidth)),
                Math.max(1, Math.round(rect.surfaceHeight))
              );
            })
            .onDestroy((): void => {
              if (this.surfaceId !== '') {
                this.controller.detachSurface(this.surfaceId);
                this.surfaceId = '';
              }
            })
            .width('100%').height('100%')
            .onClick((): void => this.onPlayerTap());

          if ((!this.state.hasVideo || !this.state.visualReady || this.state.recovering ||
            this.state.ended) &&
            (!this.state.large || this.controlsVisible)) {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle({ width: 34, height: 34 }).fill(
                  this.state.error ? '#6B3039' : '#384B59'
                );
                SymbolGlyph(this.state.error
                  ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.play_fill'))
                  .fontSize(16).fontColor([Color.White]);
              }.width(38).height(38);
              Text(this.state.status).fontSize(11).fontColor(FLOAT_SUBTEXT)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .onClick((): void => this.onPlayerTap());
          }

          if (!this.state.large || this.controlsVisible) {
            Column() {
              Row({ space: 6 }) {
                if (this.state.large) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
                      .fontSize(14).fontColor([Color.White]);
                  }
                  .width(29).height(29)
                  .backgroundColor('#B02A3540')
                  .onClick((): void => this.collapsePlayer());
                }
                Circle({ width: 6, height: 6 }).fill(
                  this.state.ended ? '#7C8992' :
                    (this.state.error ? FLOAT_RED :
                      (this.state.recovering ? '#F5A623' : FLOAT_RED))
                );
                Text(this.state.ended ? $r('app.string.lfw_end') : (this.state.hasVideo ? 'LIVE' : 'AUDIO'))
                  .fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White);
                Text(this.state.title).fontSize(11).fontColor(FLOAT_TEXT)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1);
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(13).fontColor([Color.White]);
                }
                .width(27).height(27).backgroundColor('#A62B3540')
                .onClick((): void => this.controller.requestClose());
              }
              .width('100%')
              .padding({ left: 8, right: 7, top: 6, bottom: 5 })
              .backgroundColor('#A6121B22');
              Blank()
                .onClick((): void => this.onPlayerTap());
              Row({ space: 7 }) {
                Text(this.state.isMuted ? $r('app.string.lfw_mic_off') : $r('app.string.lfw_mic_on'))
                  .fontSize(10).fontColor(this.state.isMuted ? FLOAT_SUBTEXT : FLOAT_GREEN)
                  .layoutWeight(1);
                Button() {
                  Row({ space: 5 }) {
                    if (this.state.actionBusy) {
                      LoadingProgress().width(14).height(14).color(Color.White);
                    } else {
                      SymbolGlyph($r('sys.symbol.plus_square_on_square'))
                        .fontSize(14).fontColor([Color.White]);
                    }
                    Text(this.state.actionBusy ? $r('app.string.lfw_returning_short') : $r('app.string.lfw_return'))
                      .fontSize(11).fontColor(Color.White);
                  }
                }
                .height(30).padding({ left: 9, right: 9 })
                .backgroundColor('#C93390EC').borderRadius(15)
                .enabled(!this.state.actionBusy)
                .onClick((): void => { this.controller.restoreFullPage(); });
              }
              .width('100%')
              .padding({ left: 9, right: 7, top: 5, bottom: 6 })
              .backgroundColor('#B6121B22');
            }
            .width('100%').height('100%')
            .transition(
              TransitionEffect.OPACITY.animation({
                duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 160),
                curve: Curve.EaseOut
              })
            );
          }
        }
        .width(this.state.large ? 320 : 196)
        .height(this.state.large ? 180 : 112)
        .backgroundColor(FLOAT_BACKGROUND)
        .borderRadius(13).clip(true)
        .border({ width: 1, color: '#3DFFFFFF' })
        .shadow({ radius: 22, color: '#78000000', offsetX: 0, offsetY: 8 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 240), curve: Curve.Friction
        })
        // Written after .animation() on purpose: dragging must track the finger
        // immediately instead of chasing it through the size-change animation.
        .translate({ x: this.dragX, y: this.dragY })
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
            .onActionStart((): void => {
              this.panStartX = this.dragX;
              this.panStartY = this.dragY;
            })
            .onActionUpdate((event: GestureEvent): void => this.onPanUpdate(event))
        )
        .onAreaChange((_old: Area, area: Area): void => {
          this.onPlayerArea(area);
          setTimeout((): void => this.refreshSurfaceSize(), 30);
        })
        .transition(
          TransitionEffect.scale({ x: 0.9, y: 0.9 })
            .combine(TransitionEffect.OPACITY)
            .animation({
              duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.Friction
            })
        );
      }
      .width('100%')
      // The Row spans the screen to right-align the player; only its Stack
      // child should consume input.
      .hitTestBehavior(HitTestMode.None);
    }
    .width('100%').height('100%')
    .padding({ right: 12, bottom: this.bottomSafe + 82, top: this.topSafe + 8 })
    .onAreaChange((_old: Area, area: Area): void => this.onRootArea(area))
    // OverlayManager delivers events to the WrappedBuilder content first and
    // does NOT forward them to the page underneath by default. Transparent (not
    // None) is the documented mode that lets the hit test continue past this
    // full-screen root, so the player stays interactive while everything
    // outside its bounds reaches the current app page.
    .hitTestBehavior(HitTestMode.Transparent);
  }
}

@Builder
function buildFloatingLiveOverlay(args: FloatingOverlayArgs) {
  // The builder root must be a plain container: a custom-component root makes
  // ArkUI insert a BuilderProxyNode that cannot carry attributes and swallows
  // hit tests, blocking every tap on the page beneath the overlay. Transparent
  // on this real root is what lets touches fall through to the page.
  Stack() {
    FloatingLiveOverlay({ controller: args.controller });
  }
  .width('100%').height('100%')
  .hitTestBehavior(HitTestMode.Transparent);
}
