import { display, router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import { GroupCallParticipantsStore } from '../../store/GroupCallParticipantsStore';
import {
  GroupCallMessageEntry, GroupCallMessageStore
} from '../../store/GroupCallMessageStore';
import {
  GroupCallParticipantInfo, GroupCallStreamInfo, GroupCallVideoSource, LiveStreamState, emptyLiveStreamState
} from '../../tdkit/GroupCallTypes';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import {
  endGroupCall, getGroupCall, leaveGroupCall, setGroupCallParticipantIsSpeaking,
  toggleGroupCallParticipantIsMuted
} from '../../tdkit/GroupCallApi';
import { TgcallsGroupSession, TgcallsJoinResult } from '../../services/TgcallsGroupSession';
import { liveStreamBackgroundTask } from '../../services/LiveStreamBackgroundTask';
import { TdObject } from '../../tdkit/TdTypes';
import { TdClient } from '../../tdkit/TdClient';
import {
  confirmAdminLeaveLiveStream, confirmLeaveLiveStream, setLiveStreamFullscreen,
  setLiveStreamKeepScreenOn
} from './LiveViewerUi';
import {
  FloatingLiveDescriptor, FloatingLiveSessionHandoff, floatingLiveWindow
} from './LiveFloatingWindow';
import {
  KEY_POWER_CALL_ANIMATIONS, powerAnimationDuration, powerFeatureEnabled
} from '../../store/AppSettings';
import {
  LIVE_PHASE_AUDIO, LIVE_PHASE_NONE, LIVE_PHASE_RECOVERING,
  LiveViewerHeaderPresentation, liveViewerHeaderPresentation
} from '../../util/liveViewerHeaderPresentation';
import {
  LiveViewerMediaPresentation, liveViewerMediaPresentation
} from '../../util/liveViewerMediaPresentation';
import {
  LiveInteractionEntry, LiveInteractionPresentation, liveInteractionLooksLikeEmojiOnly,
  liveInteractionPresentation, mergeLiveInteractions
} from '../../util/liveInteractionPresentation';
import { LiveInteractionBubble } from './LiveInteractionBubble';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logI } from '../../util/log';

const CALL_BACKGROUND: string = '#0D141B';
const CALL_PANEL: string = '#141E27';
const CALL_PANEL_ALT: string = '#101820';
const CALL_GREEN: string = '#39D98A';
const CALL_RED: string = '#D94B55';
const CALL_TEXT: string = '#F4F7F9';
const CALL_SUBTEXT: string = '#8B9BA8';
const AVATAR_COLORS: string[] = ['#4C9AFF', '#9C6ADE', '#E06C75', '#2CB67D', '#E39B3A', '#4CB8C4'];
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MEDIA_RECONNECT_GRACE_MS: number = 8000;
const MEDIA_HEALTH_INTERVAL_MS: number = 5000;
const LOCAL_VIDEO_START_TIMEOUT_MS: number = 20000;
const CALL_INTERACTION_LIMIT: number = 60;
const CALL_QUICK_REACTIONS: string[] = ['❤️', '🔥', '👏', '👍'];

function groupMessageInteraction(
  message: GroupCallMessageEntry, arrivalOrder: number
): LiveInteractionEntry {
  return {
    key: `call:${message.id}`,
    revision: `${message.revision}:${message.senderName}:${message.senderAvatarPath}`,
    source: 'call', id: message.id, senderKey: message.senderKey,
    senderName: message.senderName, senderInitials: message.senderInitials,
    senderAvatarPath: message.senderAvatarPath, colorSeed: message.colorSeed,
    date: message.date, text: message.text, photoPath: '',
    emojiOnly: CALL_QUICK_REACTIONS.indexOf(message.text.trim()) >= 0 ||
      liveInteractionLooksLikeEmojiOnly(message.text),
    isFromOwner: message.isFromOwner, sendState: 'none', arrivalOrder
  };
}

interface LiveVideoSurfaceBinding {
  surfaceId: string;
  width: number;
  height: number;
}

@Component
struct LiveVideoTile {
  @Prop source: GroupCallVideoSource;
  @Prop tileHeight: number = 180;
  @Prop fillParent: boolean = false;
  @Prop showFullscreenButton: boolean = false;
  @Prop fullscreen: boolean = false;
  @Prop pulseExpanded: boolean = false;
  onSurfaceReady: (
    endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
  ) => void = (): void => {};
  onSurfaceGone: (endpointId: string, surfaceId: string) => void = (): void => {};
  onFullscreenToggle: () => void = (): void => {};
  private controller: XComponentController = new XComponentController();
  private boundSurfaceId: string = '0';
  private boundSurfaceWidth: number = 0;
  private boundSurfaceHeight: number = 0;

  aboutToDisappear(): void {
    if (this.boundSurfaceId !== '0') {
      this.onSurfaceGone(this.source.endpointId, this.boundSurfaceId);
    }
    this.boundSurfaceId = '0';
    this.boundSurfaceWidth = 0;
    this.boundSurfaceHeight = 0;
  }

  private refreshSurfaceSize(): void {
    if (this.boundSurfaceId === '0') { return; }
    const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
    const width = Math.max(1, Math.round(rect.surfaceWidth));
    const height = Math.max(1, Math.round(rect.surfaceHeight));
    if (width === this.boundSurfaceWidth && height === this.boundSurfaceHeight) { return; }
    this.boundSurfaceWidth = width;
    this.boundSurfaceHeight = height;
    this.onSurfaceReady(this.source.endpointId, this.boundSurfaceId, width, height);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: `group_call_video_${this.source.endpointId}`,
        // TEXTURE participates in ArkUI composition, so speaking borders,
        // labels and rounded clipping can safely sit above the video. A
        // SURFACE XComponent owns a separate surface layer and can remain
        // black when it is combined with these Stack overlays.
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .onLoad((): void => {
          const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
          this.boundSurfaceId = this.controller.getXComponentSurfaceId();
          this.boundSurfaceWidth = Math.max(1, Math.round(rect.surfaceWidth));
          this.boundSurfaceHeight = Math.max(1, Math.round(rect.surfaceHeight));
          this.onSurfaceReady(
            this.source.endpointId, this.boundSurfaceId,
            this.boundSurfaceWidth, this.boundSurfaceHeight
          );
        })
        .onDestroy((): void => {
          if (this.boundSurfaceId !== '0') {
            this.onSurfaceGone(this.source.endpointId, this.boundSurfaceId);
          }
          this.boundSurfaceId = '0';
          this.boundSurfaceWidth = 0;
          this.boundSurfaceHeight = 0;
        })
        .width('100%').height('100%');

      if (this.source.isSpeaking) {
        Row()
          .width('100%').height('100%')
          .border({ width: this.pulseExpanded ? 3 : 2, color: CALL_GREEN })
          .borderRadius(8)
          .opacity(this.pulseExpanded ? 0.62 : 1);
      }

      if (this.source.isPaused) {
        Column({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.camera')).fontSize(28).fontColor([Color.White]);
          Text($r('app.string.lv_video_paused')).fontSize(12).fontColor(Color.White);
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#8A0A1117')
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 160), curve: Curve.EaseOut
        }));
      }

      Column() {
        Blank();
        Row({ space: 5 }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.source.isSpeaking) {
              Circle({ width: 20, height: 20 }).fill('#5539D98A')
                .scale({ x: this.pulseExpanded ? 1.12 : 0.82, y: this.pulseExpanded ? 1.12 : 0.82 })
                .opacity(this.pulseExpanded ? 0.32 : 0.75);
            }
            SymbolGlyph($r('sys.symbol.mic'))
              .fontSize(this.source.isSpeaking && this.pulseExpanded ? 14 : 13)
              .fontColor([this.source.isMuted ? '#A9B4BC' : Color.White]);
            if (this.source.isMuted) {
              Text('╱').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#D6DEE3');
            }
          }
          .width(20).height(20);
          Text(this.source.name !== '' ? this.source.name :
            (this.source.isScreenSharing ? $r('app.string.lv_screen_share') : $r('app.string.lv_stream_video')))
            .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .padding({ left: 8, right: 9, top: 4, bottom: 5 })
        .backgroundColor('#66000000').borderRadius(10)
        .margin({ left: 7, bottom: 7 }).alignSelf(ItemAlign.Start);
      }
      .width('100%').height('100%');

      if (this.showFullscreenButton) {
        Column() {
          Blank();
          Row() {
            Blank();
            Button({ type: ButtonType.Circle }) {
              if (this.fullscreen) {
                SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
                  .fontSize(20).fontColor([Color.White]);
              } else {
                SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                  .fontSize(20).fontColor([Color.White]);
              }
            }
            .width(40).height(40).padding(0).backgroundColor('#A617222B')
            .border({ width: 1, color: '#42FFFFFF' })
            .accessibilityText(this.fullscreen ? $r('app.string.lv_exit_fullscreen') : $r('app.string.lv_enter_fullscreen'))
            .onClick((): void => this.onFullscreenToggle());
          }.width('100%');
        }
        .width('100%').height('100%').padding({ right: 9, bottom: 9 });
      }
    }
    .width('100%').height(this.fillParent ? '100%' : `${this.tileHeight}vp`)
    .backgroundColor(Color.Black)
    .borderRadius(8).clip(true)
    .onAreaChange((_old: Area, _area: Area): void => {
      // Rotation resizes a TEXTURE XComponent after onLoad. Rebind the same
      // Surface with its new dimensions so the old canvas is not stretched.
      setTimeout((): void => this.refreshSurfaceSize(), 30);
    })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 190), curve: Curve.EaseOut
    }));
  }
}

@Component
struct LocalVideoPreviewTile {
  @Prop mode: number = 1;
  @Prop tileWidth: string = '100%';
  @Prop tileHeight: string = '190vp';
  @Prop compact: boolean = false;
  @Prop showFullscreenButton: boolean = false;
  @Prop fullscreen: boolean = false;
  onSurfaceReady: (
    surfaceId: string, surfaceWidth: number, surfaceHeight: number
  ) => void = (): void => {};
  onSurfaceGone: (surfaceId: string) => void = (): void => {};
  onFullscreenToggle: () => void = (): void => {};
  private controller: XComponentController = new XComponentController();
  private boundSurfaceId: string = '0';
  private boundSurfaceWidth: number = 0;
  private boundSurfaceHeight: number = 0;

  aboutToDisappear(): void {
    if (this.boundSurfaceId !== '0') {
      this.onSurfaceGone(this.boundSurfaceId);
      this.boundSurfaceId = '0';
    }
    this.boundSurfaceWidth = 0;
    this.boundSurfaceHeight = 0;
  }

  private refreshSurfaceSize(): void {
    if (this.boundSurfaceId === '0') { return; }
    const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
    const width = Math.max(1, Math.round(rect.surfaceWidth));
    const height = Math.max(1, Math.round(rect.surfaceHeight));
    if (width === this.boundSurfaceWidth && height === this.boundSurfaceHeight) { return; }
    this.boundSurfaceWidth = width;
    this.boundSurfaceHeight = height;
    this.onSurfaceReady(this.boundSurfaceId, width, height);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: `group_call_local_video_${this.mode}`,
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .onLoad((): void => {
          const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
          this.boundSurfaceId = this.controller.getXComponentSurfaceId();
          this.boundSurfaceWidth = Math.max(1, Math.round(rect.surfaceWidth));
          this.boundSurfaceHeight = Math.max(1, Math.round(rect.surfaceHeight));
          this.onSurfaceReady(
            this.boundSurfaceId,
            this.boundSurfaceWidth,
            this.boundSurfaceHeight
          );
        })
        .onDestroy((): void => {
          if (this.boundSurfaceId !== '0') {
            this.onSurfaceGone(this.boundSurfaceId);
            this.boundSurfaceId = '0';
          }
          this.boundSurfaceWidth = 0;
          this.boundSurfaceHeight = 0;
        })
        .width('100%').height('100%');

      Column() {
        Blank();
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 }).fill(CALL_GREEN);
          Text(this.mode === 1 ? $r('app.string.lv_you_front') : $r('app.string.lv_you_rear'))
            .fontSize(this.compact ? 10 : 12)
            .fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
        .padding({
          left: this.compact ? 7 : 9, right: this.compact ? 7 : 9,
          top: 4, bottom: 4
        })
        .backgroundColor('#8A000000').borderRadius(10)
        .margin({ left: 7, bottom: 7 }).alignSelf(ItemAlign.Start);
      }
      .width('100%').height('100%');

      if (this.showFullscreenButton) {
        Column() {
          Blank();
          Row() {
            Blank();
            Button({ type: ButtonType.Circle }) {
              if (this.fullscreen) {
                SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
                  .fontSize(20).fontColor([Color.White]);
              } else {
                SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                  .fontSize(20).fontColor([Color.White]);
              }
            }
            .width(40).height(40).padding(0).backgroundColor('#A617222B')
            .border({ width: 1, color: '#42FFFFFF' })
            .accessibilityText(this.fullscreen ? $r('app.string.lv_exit_fullscreen') : $r('app.string.lv_enter_fullscreen'))
            .onClick((): void => this.onFullscreenToggle());
          }.width('100%');
        }
        .width('100%').height('100%').padding({ right: 9, bottom: 9 });
      }
    }
    .width(this.tileWidth).height(this.tileHeight)
    .backgroundColor(Color.Black)
    .border({ width: this.compact ? 1.5 : 0, color: '#A6FFFFFF' })
    .borderRadius(this.compact ? 12 : 8).clip(true)
    .onAreaChange((_old: Area, _area: Area): void => {
      setTimeout((): void => this.refreshSurfaceSize(), 30);
    })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    }));
  }
}

@Entry
@Component
struct LiveStreamViewerPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('cutoutTopSafeHeight') cutoutTopSafe: number = 0;
  @StorageProp('cutoutLeftSafeWidth') cutoutLeftSafe: number = 0;
  @StorageProp('cutoutRightSafeWidth') cutoutRightSafe: number = 0;
  @StorageProp('appForegroundEpoch') @Watch('onAppForegroundEpoch') appForegroundEpoch: number = 0;
  @State state: LiveStreamState = emptyLiveStreamState();
  @State mediaStatus: string = str('lv_joining');
  @State mediaPhase: string = LIVE_PHASE_NONE;
  @State participants: GroupCallParticipantInfo[] = [];
  @State videoSources: GroupCallVideoSource[] = [];
  @State isMuted: boolean = true;
  @State pulseExpanded: boolean = false;
  @State microphoneScale: number = 1;
  @State videoAreaOpacity: number = 1;
  @State preferredPrimaryEndpointId: string = '';
  @State isFullscreen: boolean = false;
  @State fullscreenTransitioning: boolean = false;
  @State fullscreenTransitionLabel: string = '';
  @State fullscreenPanelOpen: boolean = false;
  @State minimizeInProgress: boolean = false;
  @State localVideoMode: number = 0;
  @State localVideoActive: boolean = false;
  @State localVideoBusy: boolean = false;
  @State screenShareActive: boolean = false;
  @State screenShareBusy: boolean = false;
  @State desiredLocalVideoMode: number = 0;
  @State screenShareDesired: boolean = false;
  @State primaryVideoAspectRatio: number = 0;
  @State canManageLive: boolean = false;
  @State endingLive: boolean = false;
  @State headerStateResolved: boolean = false;
  @State headerQueryFailed: boolean = false;
  @State recoveryUiVisible: boolean = false;
  @State retrySeconds: number = 0;
  @State connectionError: string = '';
  @State leaveDialogOpen: boolean = false;
  @State interactionMessages: LiveInteractionEntry[] = [];
  @State interactionDrawerOpen: boolean = false;
  @State interactionUnreadCount: number = 0;
  @State interactionAtBottom: boolean = true;
  @State interactionDraft: string = '';
  @State interactionSending: boolean = false;
  @State interactionSendError: string = '';
  private groupCallId: number = 0;
  private chatId: number = 0;
  private initialTitle: string = '';
  private initialParticipantCount: number = 0;
  private store: LiveStreamStore | null = null;
  private participantStore: GroupCallParticipantsStore | null = null;
  private interactionStore: GroupCallMessageStore | null = null;
  private off: (() => void) | null = null;
  private offParticipants: (() => void) | null = null;
  private offInteractionMessages: (() => void) | null = null;
  private offInteractionError: (() => void) | null = null;
  private tgcallsSession: TgcallsGroupSession | null = null;
  private requestedEndpoints: Set<string> = new Set();
  private unifiedSource: GroupCallVideoSource | null = null;
  private selfParticipantId: TdObject | null = null;
  private pulseTimer: number = -1;
  private videoSwitchSequence: number = 0;
  private pageActive: boolean = false;
  private mediaConnected: boolean = false;
  private hasJoinedOnce: boolean = false;
  private recoveryInFlight: boolean = false;
  private sessionSequence: number = 0;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private reconnectDueAt: number = 0;
  private recoveryUiTimer: number = -1;
  private recoveryCountdownTimer: number = -1;
  private healthTimer: number = -1;
  private groupCallRefreshInFlight: boolean = false;
  private surfaceBindings: Map<string, LiveVideoSurfaceBinding> = new Map();
  private leavingForFloating: boolean = false;
  private localVideoOperationSequence: number = 0;
  private screenShareOperationSequence: number = 0;
  private localPreviewSurfaceId: string = '0';
  private videoAspectRatios: Map<string, number> = new Map();
  private primaryVideoPinned: boolean = false;
  private interactionArrivalCounter: number = 0;
  private interactionArrivalOrders: Map<string, number> = new Map();
  private interactionSnapshotReady: boolean = false;
  private interactionScroller: Scroller = new Scroller();
  private interactionTouchActive: boolean = false;
  private lastFailedInteractionText: string = '';
  private fullscreenTransitionTimer: number = -1;

  @Styles
  topActionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  aboutToAppear(): void {
    this.pageActive = true;
    setLiveStreamKeepScreenOn(getContext(this) as common.UIAbilityContext, true);
    this.interactionDrawerOpen = false;
    this.interactionUnreadCount = 0;
    this.interactionAtBottom = true;
    this.interactionTouchActive = false;
    this.interactionSnapshotReady = false;
    const params = router.getParams() as Record<string, Object> | undefined;
    this.groupCallId = params !== undefined ? ((params['groupCallId'] as number | undefined) ?? 0) : 0;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    this.initialTitle = params !== undefined
      ? ((params['initialTitle'] as string | undefined) ?? '') : '';
    this.initialParticipantCount = params !== undefined
      ? ((params['initialParticipantCount'] as number | undefined) ?? 0) : 0;
    if (this.groupCallId <= 0) {
      this.setMediaStatus(str('lv_invalid_room'));
      return;
    }
    this.startPulseAnimation();
    const client = getTdClient();
    this.store = new LiveStreamStore(client, this.groupCallId);
    this.off = this.store.subscribe((value: LiveStreamState): void => this.onLiveState(value));
    this.state = this.store.getState();
    this.participantStore = new GroupCallParticipantsStore(client, this.groupCallId);
    this.offParticipants = this.participantStore.subscribe(
      (value: GroupCallParticipantInfo[]): void => this.onParticipants(value)
    );
    this.interactionStore = new GroupCallMessageStore(client, getUserStore(), this.groupCallId);
    this.offInteractionMessages = this.interactionStore.subscribe(
      (messages: GroupCallMessageEntry[]): void => this.onInteractionMessages(messages)
    );
    this.offInteractionError = this.interactionStore.subscribeError((message: string): void => {
      this.interactionSendError = message;
    });
    this.interactionStore.open();

    const context = getContext(this) as common.UIAbilityContext;
    const handoff = floatingLiveWindow.takeSeamlessSession(this.groupCallId, false);
    if (handoff !== null) {
      this.adoptSeamlessSession(handoff, client);
    }
    liveStreamBackgroundTask.start(context, !this.isMuted);
    this.startHealthMonitor();
    if (handoff === null) { this.replaceSession('首次加入'); } // i18n-exempt: diagnostic trace tag, console only
    this.refreshGroupCall('首次查询'); // i18n-exempt: diagnostic trace tag, console only
  }

  private adoptSeamlessSession(
    handoff: FloatingLiveSessionHandoff, client: TdClient
  ): void {
    const session = handoff.session;
    this.tgcallsSession = session;
    this.sessionSequence += 1;
    this.store?.setStreams(handoff.liveState.streams);
    this.state = handoff.liveState;
    this.isMuted = handoff.isMuted;
    this.mediaConnected = handoff.mediaConnected;
    this.hasJoinedOnce = handoff.hasJoinedOnce;
    this.recoveryInFlight = false;
    this.recoveryUiVisible = !handoff.mediaConnected;
    this.connectionError = '';
    this.reconnectAttempt = 0;
    this.headerStateResolved = true;
    this.headerQueryFailed = false;
    this.localVideoMode = handoff.localVideoMode;
    this.localVideoActive = handoff.localVideoActive;
    this.localVideoBusy = false;
    this.desiredLocalVideoMode = handoff.desiredLocalVideoMode;
    this.screenShareActive = handoff.screenShareActive;
    this.screenShareDesired = handoff.screenShareDesired;
    this.screenShareBusy = false;
    this.primaryVideoAspectRatio = handoff.videoAspectRatio;
    const primarySource = handoff.descriptor.primarySource;
    if (primarySource !== null) {
      this.preferredPrimaryEndpointId = primarySource.endpointId;
      this.videoSources = [primarySource];
      this.requestedEndpoints.add(primarySource.endpointId);
      if (primarySource.endpointId === 'unified') { this.unifiedSource = primarySource; }
      if (handoff.videoAspectRatio > 0) {
        this.videoAspectRatios.set(primarySource.endpointId, handoff.videoAspectRatio);
      }
    }
    session.setListeners(
      (connected: boolean): void => this.onMediaNetworkState(session, connected),
      (audioSourceId: number, speaking: boolean): void => {
        this.onRemoteAudioActivity(session, client, audioSourceId, speaking);
      },
      (): void => {},
      (): void => {},
      (mode: number, active: boolean, error: number): void => {
        this.onLocalVideoState(session, mode, active, error);
      },
      (endpointId: string, width: number, height: number): void => {
        this.onVideoGeometry(session, endpointId, width, height);
      }
    );
    if (primarySource !== null) {
      session.setVideoChannel(
        primarySource.endpointId, primarySource.audioSourceId, primarySource.sourceGroups
      );
    }
    session.resumeMedia();
    if (!handoff.mediaConnected) {
      this.setMediaStatus(str('lv_media_recovering'), LIVE_PHASE_RECOVERING);
    } else if (this.videoSources.length > 0) {
      this.setMediaStatus(str('lv_av_connected'));
    } else {
      this.setMediaStatus(str('lv_audio_connected'), LIVE_PHASE_AUDIO);
    }
    this.participantStore?.load(100).catch((caught: Error): void => {
      logE(`LiveStreamViewer.adopt load participants failed: ${caught.message}`);
    });
  }

  onPageShow(): void {
    if (this.pageActive && this.groupCallId > 0) {
      if (this.isFullscreen) {
        setLiveStreamFullscreen(
          getContext(this) as common.UIAbilityContext, true, this.primaryVideoAspectRatio
        );
      }
      this.resumeAfterForeground();
    }
  }

  private onAppForegroundEpoch(): void {
    if (this.pageActive && this.groupCallId > 0) { this.resumeAfterForeground(); }
  }

  private onLiveState(value: LiveStreamState): void {
    this.state = value;
    if (value.title !== '' || value.isActive || value.error !== '') {
      this.headerStateResolved = true;
      this.headerQueryFailed = false;
    }
    if (this.hasJoinedOnce && this.headerStateResolved && !value.isActive) {
      this.clearRecoveryTimer();
      this.clearRecoveryUi();
      this.setMediaStatus(str('lfw_ended'));
      setLiveStreamKeepScreenOn(getContext(this) as common.UIAbilityContext, false);
      return;
    }
    if (value.needRejoin) {
      this.showRecoveryUi(0);
      this.scheduleRecovery(0, 'TDLib 要求重新加入'); // i18n-exempt: diagnostic trace tag, console only
    } else if (this.hasJoinedOnce && value.isActive && !value.isJoined) {
      this.showRecoveryUi(0);
      this.scheduleRecovery(500, '直播成员状态已断开'); // i18n-exempt: diagnostic trace tag, console only
    }
  }

  private interactionArrival(key: string): number {
    const known = this.interactionArrivalOrders.get(key);
    if (known !== undefined) { return known; }
    this.interactionArrivalCounter += 1;
    this.interactionArrivalOrders.set(key, this.interactionArrivalCounter);
    return this.interactionArrivalCounter;
  }

  private onInteractionMessages(messages: GroupCallMessageEntry[]): void {
    const previous = this.interactionMessages;
    const entries: LiveInteractionEntry[] = [];
    for (const message of messages) {
      const key = `call:${message.id}`;
      entries.push(groupMessageInteraction(message, this.interactionArrival(key)));
    }
    const next = mergeLiveInteractions(entries, CALL_INTERACTION_LIMIT);
    const newCount = this.interactionSnapshotReady
      ? next.filter((candidate: LiveInteractionEntry): boolean =>
        !previous.some((entry: LiveInteractionEntry): boolean => entry.key === candidate.key)).length
      : 0;
    this.interactionMessages = next;
    this.interactionSnapshotReady = true;
    if (newCount <= 0) { return; }
    if (this.interactionDrawerOpen && this.interactionAtBottom && !this.interactionTouchActive) {
      setTimeout((): void => this.interactionScroller.scrollEdge(Edge.Bottom), 40);
    } else {
      this.interactionUnreadCount += newCount;
    }
  }

  private openInteractionDrawer(): void {
    this.interactionAtBottom = true;
    this.interactionUnreadCount = 0;
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.EaseOut
    }, (): void => { this.interactionDrawerOpen = true; });
    setTimeout((): void => this.interactionScroller.scrollEdge(Edge.Bottom), 60);
  }

  private closeInteractionDrawer(): void {
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    }, (): void => { this.interactionDrawerOpen = false; });
  }

  private closeInteractionDrawerOnSwipe(offsetY: number): void {
    if (offsetY > 54) { this.closeInteractionDrawer(); }
  }

  private refreshInteractionAtBottom(): void {
    const next = this.interactionMessages.length === 0 || this.interactionScroller.isAtEnd();
    if (this.interactionAtBottom !== next) { this.interactionAtBottom = next; }
    if (next && this.interactionUnreadCount !== 0) { this.interactionUnreadCount = 0; }
  }

  private scrollToInteractionTail(): void {
    this.interactionAtBottom = true;
    this.interactionUnreadCount = 0;
    this.interactionScroller.scrollEdge(Edge.Bottom);
  }

  private callInteractionPresentation(): LiveInteractionPresentation {
    return liveInteractionPresentation({
      valid: this.groupCallId > 0, resolved: this.headerStateResolved,
      active: this.state.isActive, joined: this.state.isJoined, joinedOnce: this.hasJoinedOnce,
      recovering: this.recoveryInFlight && this.hasJoinedOnce,
      messagesAllowed: this.state.areMessagesAllowed,
      canSendMessages: this.state.canSendMessages,
      messageCount: this.interactionMessages.length,
      channelAttached: false, channelHistoryState: 'ready', channelHistoryError: ''
    });
  }

  private shouldShowInteractionSection(): boolean {
    return this.state.areMessagesAllowed || this.state.canSendMessages || this.interactionMessages.length > 0;
  }

  private callInteractionStatusColor(): string {
    const tone = this.callInteractionPresentation().statusTone;
    if (tone === 'live') { return CALL_GREEN; }
    if (tone === 'accent') { return '#64A8FF'; }
    return CALL_SUBTEXT;
  }

  private callInteractionStatusBackground(): string {
    const tone = this.callInteractionPresentation().statusTone;
    if (tone === 'live') { return '#2539D98A'; }
    if (tone === 'accent') { return '#263390EC'; }
    return '#244A5964';
  }

  private sendInteraction(text?: string): void {
    const store = this.interactionStore;
    if (store === null || this.interactionSending ||
      !this.callInteractionPresentation().composerEnabled) { return; }
    const value = (text ?? this.interactionDraft).trim();
    if (value === '') { return; }
    this.lastFailedInteractionText = value;
    this.interactionSendError = '';
    this.interactionSending = true;
    store.send(value).then((): void => {
      if (text === undefined) { this.interactionDraft = ''; }
    }).catch((caught: Error): void => {
      this.interactionSendError = str('lv_send_failed', caught.message);
    }).finally((): void => {
      this.interactionSending = false;
    });
  }

  private retryInteractionSend(): void {
    if (this.lastFailedInteractionText !== '' && !this.interactionSending) {
      this.sendInteraction(this.lastFailedInteractionText);
    }
  }

  private replaceSession(reason: string): void {
    if (!this.pageActive || this.groupCallId <= 0) { return; }
    if (this.recoveryInFlight) {
      this.scheduleRecovery(750, reason);
      return;
    }
    this.recoveryInFlight = true;
    this.clearRecoveryTimer();
    this.mediaConnected = false;
    this.connectionError = '';
    if (this.hasJoinedOnce) { this.showRecoveryUi(0); }
    const sequence = ++this.sessionSequence;
    const previous = this.tgcallsSession;
    // Ignore synchronous capturer-stop callbacks from the session being
    // replaced, while keeping the desired camera/screen mode for recovery.
    this.tgcallsSession = null;
    if (previous !== null) {
      previous.clearVideo();
      previous.stop();
    }
    this.requestedEndpoints.clear();
    this.unifiedSource = null;
    this.videoAspectRatios.clear();
    this.primaryVideoAspectRatio = 0;
    this.onParticipants(this.participants);
    if (this.hasJoinedOnce) {
      this.setMediaStatus(str('lv_restoring_connection'), LIVE_PHASE_RECOVERING);
    } else {
      this.setMediaStatus(str('lv_joining'));
    }

    const client = getTdClient();
    const session = new TgcallsGroupSession(
      (connected: boolean): void => this.onMediaNetworkState(session, connected),
      (audioSourceId: number, speaking: boolean): void => {
        this.onRemoteAudioActivity(session, client, audioSourceId, speaking);
      },
      (): void => {},
      (): void => {},
      (mode: number, active: boolean, error: number): void => {
        this.onLocalVideoState(session, mode, active, error);
      },
      (endpointId: string, width: number, height: number): void => {
        this.onVideoGeometry(session, endpointId, width, height);
      }
    );
    this.tgcallsSession = session;
    logI(`[LiveStreamViewer] session ${sequence} start reason=${reason}`);
    session.join(client, this.groupCallId, this.isMuted).then((result: TgcallsJoinResult): void => {
      if (!this.pageActive || this.tgcallsSession !== session || sequence !== this.sessionSequence) { return; }
      this.hasJoinedOnce = true;
      this.reconnectAttempt = 0;
      this.clearRecoveryTimer();
      this.store?.setStreams(result.streams);
      this.state = {
        title: this.state.title,
        isActive: this.state.isActive,
        isRtmpStream: this.state.isRtmpStream,
        isJoined: true,
        needRejoin: false,
        canSendMessages: this.state.canSendMessages,
        areMessagesAllowed: this.state.areMessagesAllowed,
        participantCount: this.state.participantCount,
        streams: result.streams,
        error: ''
      };
      this.setMediaStatus(result.isBroadcast
        ? (result.isUnifiedBroadcast ? str('lv_rtmp_connected') : str('lv_av_connected'))
        : str('lv_connecting_media'));
      const unifiedVideoIds: number[] = [];
      const seenUnifiedVideoIds: Set<number> = new Set();
      for (const stream of result.streams) {
        if (stream.channelId !== 0 && !seenUnifiedVideoIds.has(stream.channelId)) {
          seenUnifiedVideoIds.add(stream.channelId);
          unifiedVideoIds.push(stream.channelId);
        }
      }
      if (result.isUnifiedBroadcast && unifiedVideoIds.length > 0) {
        this.unifiedSource = {
          endpointId: 'unified',
          participantKey: 'unified',
          name: this.state.title !== '' ? this.state.title : str('lv_main_video'),
          audioSourceId: 0,
          sourceGroups: `SIM=${unifiedVideoIds.join(',')}`,
          isPaused: false,
          isScreenSharing: false,
          isSpeaking: true,
          isMuted: false
        };
      }
      this.onParticipants(this.participants);
      this.participantStore?.load(100).catch((error: Error): void => {
        logE(`loadGroupCallParticipants: ${error.message}`);
      });
      this.applyVideoSources(this.videoSources);
      this.restoreSurfaceBindings();
      session.resumeMedia();
      this.restoreLocalVideo(session, result);
      if (!this.mediaConnected && !result.isBroadcast) {
        this.scheduleRecovery(MEDIA_RECONNECT_GRACE_MS, '加入后媒体连接超时'); // i18n-exempt: diagnostic trace tag, console only
      }
      this.refreshGroupCall('加入完成'); // i18n-exempt: diagnostic trace tag, console only
    }).catch((error: Error): void => {
      if (!this.pageActive || this.tgcallsSession !== session || sequence !== this.sessionSequence) { return; }
      session.stop();
      this.tgcallsSession = null;
      this.setMediaStatus(str('lv_reconnecting'), LIVE_PHASE_RECOVERING);
      this.connectionError = error.message;
      if (!this.hasJoinedOnce) { this.headerQueryFailed = true; }
      this.showRecoveryUi(0);
      this.state = {
        title: this.state.title,
        isActive: this.state.isActive,
        isRtmpStream: this.state.isRtmpStream,
        isJoined: false,
        needRejoin: this.state.needRejoin,
        canSendMessages: this.state.canSendMessages,
        areMessagesAllowed: this.state.areMessagesAllowed,
        participantCount: this.state.participantCount,
        streams: [],
        error: error.message
      };
      this.reconnectAttempt += 1;
      const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.reconnectAttempt - 1, 5)));
      this.scheduleRecovery(delay, str('lv_join_failed', error.message));
    }).finally((): void => {
      if (sequence === this.sessionSequence) { this.recoveryInFlight = false; }
    });
  }

  private onMediaNetworkState(session: TgcallsGroupSession, connected: boolean): void {
    if (!this.pageActive || this.tgcallsSession !== session) { return; }
    this.mediaConnected = connected;
    if (connected) {
      this.reconnectAttempt = 0;
      this.clearRecoveryTimer();
      this.clearRecoveryUi();
      this.connectionError = '';
      this.setMediaStatus(str('lv_av_connected'));
      session.resumeMedia();
      this.restoreSurfaceBindings();
      return;
    }
    this.setMediaStatus(str('lv_media_recovering'), LIVE_PHASE_RECOVERING);
    this.showRecoveryUi(700);
    this.scheduleRecovery(MEDIA_RECONNECT_GRACE_MS, '媒体连接超时'); // i18n-exempt: diagnostic trace tag, console only
  }

  private onRemoteAudioActivity(
    session: TgcallsGroupSession, client: TdClient,
    audioSourceId: number, speaking: boolean
  ): void {
    if (!this.pageActive || this.tgcallsSession !== session) { return; }
    logI(`[LiveStreamViewer] audio activity source=${audioSourceId} speaking=${speaking}`);
    this.participantStore?.applyAudioActivity(audioSourceId, speaking);
    setGroupCallParticipantIsSpeaking(
      client, this.groupCallId, audioSourceId, speaking
    ).then((sender: TdObject): void => {
      if (!this.pageActive || this.tgcallsSession !== session) { return; }
      this.participantStore?.applyAudioActivity(audioSourceId, speaking, sender);
    }).catch((error: Error): void => {
      logE(
        `[LiveStreamViewer] set speaking source=${audioSourceId} failed: ${error.message}`
      );
    });
  }

  private onLocalVideoState(
    session: TgcallsGroupSession, mode: number, active: boolean, error: number
  ): void {
    if (!this.pageActive || this.tgcallsSession !== session) { return; }
    logI(
      `[LiveStreamViewer] local video mode=${mode} active=${active} error=${error}`
    );
    if (mode === 3) {
      if (active) {
        this.screenShareDesired = true;
        this.screenShareActive = true;
        this.screenShareBusy = false;
        this.setMediaStatus(this.localVideoActive
          ? str('lv_camera_and_screen')
          : str('lv_sharing_screen'));
        return;
      }
      if (!this.screenShareDesired) { return; }
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.screenShareDesired = false;
      this.screenShareOperationSequence += 1;
      session.stopScreenSharing().catch((caught: Error): void => {
        logE(`[LiveStreamViewer] screen-share cleanup failed: ${caught.message}`);
      });
      this.setMediaStatus(error !== 0
        ? str('lv_screen_not_started')
        : (this.localVideoActive ? str('lv_screen_off_camera_on') : str('lv_screen_off')));
      return;
    }
    if (active) {
      // A replaced camera can report its final state after the new camera has
      // already been requested. Never let that stale callback steal the UI
      // selection from the current mode.
      if (this.desiredLocalVideoMode !== 0 && mode !== this.desiredLocalVideoMode) {
        return;
      }
      this.desiredLocalVideoMode = mode;
      this.localVideoMode = mode;
      this.localVideoActive = true;
      this.localVideoBusy = false;
      this.refreshPrimaryVideoAspect();
      this.setMediaStatus(this.screenShareActive
        ? str('lv_camera_and_screen')
        : (mode === 1 ? str('lv_front_camera_live') : str('lv_rear_camera_live')));
      return;
    }
    // Switching front/back stops the old capturer after the new one has been
    // installed. Ignore that stale stop callback.
    if (mode !== this.desiredLocalVideoMode) { return; }
    this.localVideoMode = 0;
    this.localVideoActive = false;
    this.localVideoBusy = false;
    this.desiredLocalVideoMode = 0;
    this.refreshPrimaryVideoAspect();
    this.localVideoOperationSequence += 1;
    session.stopCamera().catch((caught: Error): void => {
      logE(`[LiveStreamViewer] camera cleanup failed: ${caught.message}`);
    });
    if (error !== 0) {
      this.setMediaStatus(str('lv_camera_start_failed'));
    } else {
      this.setMediaStatus(this.screenShareActive
        ? str('lv_camera_off_screen_on')
        : str('lv_camera_off'));
    }
  }

  private onVideoGeometry(
    session: TgcallsGroupSession, endpointId: string, width: number, height: number
  ): void {
    if (!this.pageActive || this.tgcallsSession !== session ||
      endpointId === '' || width <= 0 || height <= 0) {
      return;
    }
    const aspectRatio = width / height;
    this.videoAspectRatios.set(endpointId, aspectRatio);
    const primaryEndpoint = this.videoSources.length > 0
      ? this.videoSources[0].endpointId
      : (this.isLocalCameraActive() ? '__local_camera__' : '');
    if (endpointId !== primaryEndpoint) { return; }
    if (Math.abs(this.primaryVideoAspectRatio - aspectRatio) < 0.01) { return; }
    this.primaryVideoAspectRatio = aspectRatio;
    logI(
      `[LiveStreamViewer] primary video geometry endpoint=${endpointId} ` +
      `${width}x${height} aspect=${aspectRatio}`
    );
    if (this.isFullscreen) {
      setLiveStreamFullscreen(
        getContext(this) as common.UIAbilityContext, true, this.primaryVideoAspectRatio
      );
    }
  }

  private refreshPrimaryVideoAspect(): void {
    const primaryEndpoint = this.videoSources.length > 0
      ? this.videoSources[0].endpointId
      : (this.isLocalCameraActive() ? '__local_camera__' : '');
    const aspectRatio = primaryEndpoint === ''
      ? 0
      : (this.videoAspectRatios.get(primaryEndpoint) ?? 0);
    if (Math.abs(this.primaryVideoAspectRatio - aspectRatio) < 0.01) { return; }
    this.primaryVideoAspectRatio = aspectRatio;
    if (this.isFullscreen) {
      setLiveStreamFullscreen(
        getContext(this) as common.UIAbilityContext, true, this.primaryVideoAspectRatio
      );
    }
  }

  private restoreLocalVideo(
    session: TgcallsGroupSession, result: TgcallsJoinResult
  ): void {
    const cameraMode = this.desiredLocalVideoMode;
    const restoreScreenShare = this.screenShareDesired;
    if (cameraMode === 0 && !restoreScreenShare) { return; }
    if (result.isBroadcast) {
      this.localVideoMode = 0;
      this.localVideoActive = false;
      this.localVideoBusy = false;
      this.desiredLocalVideoMode = 0;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.screenShareDesired = false;
      this.setMediaStatus(str('lv_rtmp_one_way'));
      return;
    }
    if (cameraMode === 1 || cameraMode === 2) {
      this.localVideoBusy = true;
      this.startCameraVideo(cameraMode);
    }
    if (restoreScreenShare) {
      this.screenShareBusy = true;
      this.startScreenShareVideo();
    }
  }

  private scheduleRecovery(delayMs: number, reason: string): void {
    if (!this.pageActive || this.groupCallId <= 0 ||
      (this.hasJoinedOnce && this.headerStateResolved && !this.state.isActive)) { return; }
    const dueAt = Date.now() + Math.max(0, delayMs);
    if (this.reconnectTimer !== -1 && this.reconnectDueAt <= dueAt) { return; }
    this.clearRecoveryTimer();
    this.reconnectDueAt = dueAt;
    this.startRecoveryCountdown();
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      this.reconnectDueAt = 0;
      this.stopRecoveryCountdown();
      if (!this.pageActive || (this.hasJoinedOnce && this.headerStateResolved &&
        !this.state.isActive)) { return; }
      this.replaceSession(reason);
    }, Math.max(0, delayMs));
  }

  private clearRecoveryTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
      this.reconnectDueAt = 0;
    }
    this.stopRecoveryCountdown();
  }

  private startRecoveryCountdown(): void {
    this.stopRecoveryCountdown();
    const refresh = (): void => {
      this.retrySeconds = this.reconnectDueAt > 0
        ? Math.max(0, Math.ceil((this.reconnectDueAt - Date.now()) / 1000)) : 0;
    };
    refresh();
    if (this.retrySeconds > 0) {
      this.recoveryCountdownTimer = setInterval((): void => refresh(), 250);
    }
  }

  private stopRecoveryCountdown(): void {
    if (this.recoveryCountdownTimer !== -1) {
      clearInterval(this.recoveryCountdownTimer);
      this.recoveryCountdownTimer = -1;
    }
    this.retrySeconds = 0;
  }

  private showRecoveryUi(delayMs: number): void {
    if (this.recoveryUiVisible) { return; }
    if (this.recoveryUiTimer !== -1) { clearTimeout(this.recoveryUiTimer); }
    if (delayMs <= 0) {
      this.recoveryUiTimer = -1;
      this.recoveryUiVisible = true;
      return;
    }
    this.recoveryUiTimer = setTimeout((): void => {
      this.recoveryUiTimer = -1;
      if (this.pageActive && this.hasJoinedOnce && !this.mediaConnected &&
        (!this.headerStateResolved || this.state.isActive)) {
        this.recoveryUiVisible = true;
      }
    }, delayMs);
  }

  private clearRecoveryUi(): void {
    if (this.recoveryUiTimer !== -1) {
      clearTimeout(this.recoveryUiTimer);
      this.recoveryUiTimer = -1;
    }
    this.recoveryUiVisible = false;
  }

  private startHealthMonitor(): void {
    if (this.healthTimer !== -1) { return; }
    this.healthTimer = setInterval((): void => {
      this.refreshGroupCall('定时健康检查'); // i18n-exempt: diagnostic trace tag, console only
    }, MEDIA_HEALTH_INTERVAL_MS);
  }

  private async refreshGroupCall(reason: string): Promise<void> {
    if (!this.pageActive || this.groupCallId <= 0 || this.groupCallRefreshInFlight) { return; }
    this.groupCallRefreshInFlight = true;
    try {
      const groupCall = await getGroupCall(getTdClient(), this.groupCallId);
      if (!this.pageActive) { return; }
      this.headerStateResolved = true;
      this.headerQueryFailed = false;
      const canBeManaged = (groupCall['can_be_managed'] as boolean | undefined) ?? false;
      const isOwned = (groupCall['is_owned'] as boolean | undefined) ?? false;
      this.canManageLive = canBeManaged || isOwned;
      this.selfParticipantId = (groupCall['message_sender_id'] as TdObject | undefined) ??
        this.selfParticipantId;
      const next: LiveStreamState = {
        title: (groupCall['title'] as string | undefined) ?? this.state.title,
        isActive: (groupCall['is_active'] as boolean | undefined) ?? this.state.isActive,
        isRtmpStream: (groupCall['is_rtmp_stream'] as boolean | undefined) ?? this.state.isRtmpStream,
        isJoined: (groupCall['is_joined'] as boolean | undefined) ?? this.state.isJoined,
        needRejoin: (groupCall['need_rejoin'] as boolean | undefined) ?? this.state.needRejoin,
        canSendMessages: (groupCall['can_send_messages'] as boolean | undefined) ??
          this.state.canSendMessages,
        areMessagesAllowed: (groupCall['are_messages_allowed'] as boolean | undefined) ??
          this.state.areMessagesAllowed,
        participantCount: (groupCall['participant_count'] as number | undefined) ??
          this.state.participantCount,
        streams: this.state.streams,
        error: this.state.error
      };
      if (this.store !== null) {
        this.store.applyGroupCall(groupCall);
      } else {
        this.onLiveState(next);
      }
      if (!next.isActive) { this.setMediaStatus(str('lfw_ended')); }
      logI(
        `[LiveStreamViewer] health reason=${reason} active=${next.isActive} ` +
        `joined=${next.isJoined} needRejoin=${next.needRejoin} media=${this.mediaConnected} ` +
        `admin=${this.canManageLive} canBeManaged=${canBeManaged} isOwned=${isOwned}`
      );
    } catch (caught) {
      const error = caught as Error;
      if (!this.hasJoinedOnce) { this.headerQueryFailed = true; }
      logE(`[LiveStreamViewer] health check failed reason=${reason}: ${error.message}`);
    } finally {
      this.groupCallRefreshInFlight = false;
    }
  }

  private resumeAfterForeground(): void {
    liveStreamBackgroundTask.start(
      getContext(this) as common.UIAbilityContext, !this.isMuted
    );
    const session = this.tgcallsSession;
    if (session !== null) {
      session.resumeMedia();
      this.applyVideoSources(this.videoSources);
      this.restoreSurfaceBindings();
    }
    this.refreshGroupCall('回到前台'); // i18n-exempt: diagnostic trace tag, console only
    if (this.hasJoinedOnce && !this.mediaConnected) {
      this.scheduleRecovery(3000, '前台恢复后媒体未连接'); // i18n-exempt: diagnostic trace tag, console only
    }
  }

  private onParticipants(value: GroupCallParticipantInfo[]): void {
    this.participants = value;
    const current = value.find(
      (participant: GroupCallParticipantInfo): boolean => participant.isCurrentUser
    );
    if (current !== undefined) {
      this.selfParticipantId = this.participantSender(current);
    }
    if (current !== undefined && this.hasJoinedOnce && current.isMuted !== this.isMuted) {
      this.isMuted = current.isMuted;
      this.tgcallsSession?.setMuted(this.isMuted);
      liveStreamBackgroundTask.setRecording(!this.isMuted);
    }
    const sources: GroupCallVideoSource[] = [];
    if (this.unifiedSource !== null) { sources.push(this.unifiedSource); }
    for (const participant of value) {
      for (const source of participant.videoSources) {
        // Telegram advertises the current user's camera endpoint in the
        // participant list but does not loop that media back through the SFU.
        // Rendering it as an incoming channel therefore creates a black main
        // tile and pushes the real local preview into picture-in-picture.
        // Screen sharing is a separate presentation session and can still be
        // rendered through the normal incoming path.
        if (participant.isCurrentUser && !source.isScreenSharing) { continue; }
        sources.push(source);
      }
    }
    sources.sort((a: GroupCallVideoSource, b: GroupCallVideoSource): number => {
      if (a.isScreenSharing !== b.isScreenSharing) { return a.isScreenSharing ? -1 : 1; }
      return a.endpointId.localeCompare(b.endpointId);
    });
    let preferred = sources.find(
      (source: GroupCallVideoSource): boolean =>
        source.endpointId === this.preferredPrimaryEndpointId
    );
    if (preferred === undefined) {
      this.primaryVideoPinned = false;
      preferred = sources.length > 0 ? sources[0] : undefined;
    } else if (!this.primaryVideoPinned) {
      const screen = sources.find(
        (source: GroupCallVideoSource): boolean => source.isScreenSharing
      );
      if (screen !== undefined) { preferred = screen; }
    }
    const ordered: GroupCallVideoSource[] = [];
    if (preferred !== undefined) {
      this.preferredPrimaryEndpointId = preferred.endpointId;
      ordered.push(preferred);
    } else {
      this.preferredPrimaryEndpointId = '';
    }
    for (const source of sources) {
      if (preferred === undefined || source.endpointId !== preferred.endpointId) {
        ordered.push(source);
      }
    }
    this.videoSources = ordered;
    this.refreshPrimaryVideoAspect();
    this.applyVideoSources(ordered);
  }

  private applyVideoSources(sources: GroupCallVideoSource[]): void {
    const next: Set<string> = new Set();
    for (const source of sources) {
      next.add(source.endpointId);
      this.tgcallsSession?.setVideoChannel(source.endpointId, source.audioSourceId, source.sourceGroups);
    }
    for (const old of this.requestedEndpoints) {
      if (!next.has(old)) { this.tgcallsSession?.removeVideoChannel(old); }
    }
    this.requestedEndpoints = next;
  }

  private setSurface(endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number): void {
    this.surfaceBindings.set(endpointId, {
      surfaceId,
      width: surfaceWidth,
      height: surfaceHeight
    });
    this.tgcallsSession?.setVideoSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight);
  }

  private clearSurface(endpointId: string, surfaceId: string): void {
    const current = this.surfaceBindings.get(endpointId);
    if (current !== undefined && current.surfaceId !== surfaceId) { return; }
    this.surfaceBindings.delete(endpointId);
    this.tgcallsSession?.setVideoSurface(endpointId, '0');
  }

  private isLocalCameraActive(): boolean {
    return this.localVideoActive;
  }

  private setLocalPreviewSurface(
    surfaceId: string, surfaceWidth: number, surfaceHeight: number
  ): void {
    this.localPreviewSurfaceId = surfaceId;
    this.tgcallsSession?.setLocalVideoSurface(surfaceId, surfaceWidth, surfaceHeight);
  }

  private clearLocalPreviewSurface(surfaceId: string): void {
    if (surfaceId !== this.localPreviewSurfaceId) { return; }
    this.localPreviewSurfaceId = '0';
    this.tgcallsSession?.setLocalVideoSurface('0');
  }

  private restoreSurfaceBindings(): void {
    const session = this.tgcallsSession;
    if (session === null) { return; }
    for (const entry of this.surfaceBindings.entries()) {
      const binding = entry[1];
      session.setVideoSurface(entry[0], binding.surfaceId, binding.width, binding.height);
    }
  }

  private async toggleMuted(): Promise<void> {
    this.animateMicrophoneTap();
    if (!this.isMuted) {
      if (this.tgcallsSession?.setMuted(true) ?? false) {
        this.isMuted = true;
        liveStreamBackgroundTask.setRecording(false);
        if (this.selfParticipantId !== null) {
          toggleGroupCallParticipantIsMuted(
            getTdClient(), this.groupCallId, this.selfParticipantId, true
          ).catch((error: Error): void => {
            logE(`toggleGroupCallParticipantIsMuted(true): ${error.message}`);
          });
        }
      }
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.setMediaStatus(str('lv_needs_mic'));
        return;
      }
      if (this.selfParticipantId !== null) {
        await toggleGroupCallParticipantIsMuted(
          getTdClient(), this.groupCallId, this.selfParticipantId, false
        );
      }
      if (this.tgcallsSession?.setMuted(false) ?? false) {
        this.isMuted = false;
        liveStreamBackgroundTask.setRecording(true);
      } else {
        this.setMediaStatus(str('lv_mic_start_failed'));
      }
    } catch (error) {
      this.setMediaStatus(str('lv_mic_unavailable', error));
    }
  }

  private captureSize(mode: number): number[] {
    if (mode !== 3) { return [1280, 720]; }
    try {
      const screen = display.getDefaultDisplaySync();
      const rawWidth = Math.max(2, screen.width);
      const rawHeight = Math.max(2, screen.height);
      const scale = Math.min(1, 1280 / Math.max(rawWidth, rawHeight));
      const width = Math.max(2, Math.round(rawWidth * scale / 2) * 2);
      const height = Math.max(2, Math.round(rawHeight * scale / 2) * 2);
      return [width, height];
    } catch (_) {
      return [720, 1280];
    }
  }

  private async stopCameraVideo(): Promise<void> {
    this.localVideoOperationSequence += 1;
    const session = this.tgcallsSession;
    this.desiredLocalVideoMode = 0;
    this.localVideoMode = 0;
    this.localVideoActive = false;
    this.localVideoBusy = session !== null;
    try {
      const stopped = session !== null && await session.stopCamera();
      if (!stopped) {
        this.setMediaStatus(str('lv_camera_stop_failed'));
        return;
      }
      this.setMediaStatus(this.screenShareActive
        ? str('lv_camera_off_screen_on')
        : str('lv_camera_off'));
    } catch (caught) {
      this.setMediaStatus(str('lv_camera_stop_failed_msg', caught));
    } finally {
      this.localVideoBusy = false;
    }
  }

  private async stopScreenShareVideo(): Promise<void> {
    this.screenShareOperationSequence += 1;
    const session = this.tgcallsSession;
    this.screenShareDesired = false;
    this.screenShareActive = false;
    this.screenShareBusy = session !== null;
    try {
      const stopped = session !== null && await session.stopScreenSharing();
      if (!stopped) {
        this.setMediaStatus(str('lv_screen_stop_failed'));
        return;
      }
      this.setMediaStatus(this.localVideoActive
        ? str('lv_screen_off_camera_on')
        : str('lv_screen_off'));
    } catch (caught) {
      this.setMediaStatus(str('lv_screen_stop_failed_msg', caught));
    } finally {
      this.screenShareBusy = false;
    }
  }

  private async toggleCamera(): Promise<void> {
    if (this.localVideoActive ||
      this.desiredLocalVideoMode === 1 || this.desiredLocalVideoMode === 2) {
      await this.stopCameraVideo();
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(
        context, [CAMERA_PERMISSION]
      );
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.setMediaStatus(str('lv_needs_camera'));
        return;
      }
      await this.startCameraVideo(1);
    } catch (caught) {
      this.setMediaStatus(str('lv_camera_unavailable', caught));
    }
  }

  private async switchCamera(): Promise<void> {
    if (this.desiredLocalVideoMode !== 1 && this.desiredLocalVideoMode !== 2) {
      this.setMediaStatus(str('lv_enable_camera_first'));
      return;
    }
    await this.startCameraVideo(this.desiredLocalVideoMode === 1 ? 2 : 1);
  }

  private async toggleScreenShare(): Promise<void> {
    if (this.screenShareActive || this.screenShareDesired) {
      await this.stopScreenShareVideo();
      return;
    }
    await this.startScreenShareVideo();
  }

  private async startCameraVideo(mode: number): Promise<void> {
    const session = this.tgcallsSession;
    if (session === null || !this.hasJoinedOnce || (mode !== 1 && mode !== 2)) {
      this.setMediaStatus(str('lv_wait_for_connection'));
      return;
    }
    const size = this.captureSize(mode);
    const operationSequence = ++this.localVideoOperationSequence;
    this.desiredLocalVideoMode = mode;
    this.localVideoMode = mode;
    this.localVideoActive = false;
    this.localVideoBusy = true;
    this.setMediaStatus(str('lv_starting_camera'));
    setTimeout((): void => {
      if (!this.pageActive || this.tgcallsSession !== session ||
        operationSequence !== this.localVideoOperationSequence ||
        !this.localVideoBusy || this.desiredLocalVideoMode !== mode) {
        return;
      }
      this.localVideoOperationSequence += 1;
      this.desiredLocalVideoMode = 0;
      this.localVideoMode = 0;
      this.localVideoActive = false;
      this.localVideoBusy = false;
      this.setMediaStatus(str('lv_camera_first_frame_timeout'));
      session.stopCamera().catch((caught: Error): void => {
        logE(`[LiveStreamViewer] timed-out camera cleanup failed: ${caught.message}`);
      });
    }, LOCAL_VIDEO_START_TIMEOUT_MS);
    try {
      const started = await session.startCamera(mode, size[0], size[1]);
      if (operationSequence !== this.localVideoOperationSequence) { return; }
      if (started) { return; }
      this.desiredLocalVideoMode = 0;
      this.localVideoMode = 0;
      this.localVideoBusy = false;
      this.setMediaStatus(str('lv_no_local_stream'));
    } catch (caught) {
      if (operationSequence !== this.localVideoOperationSequence) { return; }
      this.desiredLocalVideoMode = 0;
      this.localVideoMode = 0;
      this.localVideoActive = false;
      this.localVideoBusy = false;
      this.setMediaStatus(str('lv_camera_stream_failed', caught));
    }
  }

  private async startScreenShareVideo(): Promise<void> {
    const session = this.tgcallsSession;
    if (session === null || !this.hasJoinedOnce) {
      this.setMediaStatus(str('lv_wait_for_connection'));
      return;
    }
    const size = this.captureSize(3);
    const operationSequence = ++this.screenShareOperationSequence;
    this.screenShareDesired = true;
    this.screenShareActive = false;
    this.screenShareBusy = true;
    this.setMediaStatus(str('lv_requesting_screen'));
    setTimeout((): void => {
      if (!this.pageActive || this.tgcallsSession !== session ||
        operationSequence !== this.screenShareOperationSequence ||
        !this.screenShareBusy || !this.screenShareDesired) {
        return;
      }
      this.screenShareOperationSequence += 1;
      this.screenShareDesired = false;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.setMediaStatus(str('lv_screen_timeout'));
      session.stopScreenSharing().catch((caught: Error): void => {
        logE(`[LiveStreamViewer] timed-out screen-share cleanup failed: ${caught.message}`);
      });
    }, LOCAL_VIDEO_START_TIMEOUT_MS);
    try {
      const started = await session.startScreenSharing(size[0], size[1]);
      if (operationSequence !== this.screenShareOperationSequence) { return; }
      if (started) { return; }
      this.screenShareDesired = false;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.setMediaStatus(str('lv_no_screen_share'));
    } catch (caught) {
      if (operationSequence !== this.screenShareOperationSequence) { return; }
      this.screenShareDesired = false;
      this.screenShareActive = false;
      this.screenShareBusy = false;
      this.setMediaStatus(str('lv_screen_stream_failed', caught));
    }
  }

  private participantSender(participant: GroupCallParticipantInfo): TdObject | null {
    if (participant.senderId === 0) { return null; }
    if (participant.senderType === 'messageSenderUser') {
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = participant.senderId;
      return sender;
    }
    if (participant.senderType === 'messageSenderChat') {
      const sender: TdObject = { '@type': 'messageSenderChat' };
      sender['chat_id'] = participant.senderId;
      return sender;
    }
    return null;
  }

  private toggleParticipantMuted(participant: GroupCallParticipantInfo): void {
    if (!this.canManageLive || participant.isCurrentUser) { return; }
    const sender = this.participantSender(participant);
    if (sender === null) { return; }
    const nextMuted = !participant.isMuted;
    toggleGroupCallParticipantIsMuted(
      getTdClient(), this.groupCallId, sender, nextMuted
    ).then((): void => {
      this.setMediaStatus(nextMuted
        ? str('lv_muted_participant', participant.name)
        : str('lv_unmuted_participant', participant.name));
    }).catch((error: Error): void => {
      this.setMediaStatus(str('lv_participant_mic_failed', error.message));
    });
  }

  private leave(): void {
    if (this.groupCallId <= 0) {
      router.back();
      return;
    }
    if (this.leaveDialogOpen || this.minimizeInProgress || this.endingLive) { return; }
    this.leaveDialogOpen = true;
    if (this.canManageLive) {
      confirmAdminLeaveLiveStream(
        (): void => this.leaveNow(),
        (): void => this.endLiveForEveryone(),
        (): void => { this.leaveDialogOpen = false; }
      );
      return;
    }
    confirmLeaveLiveStream(
      (): void => this.leaveNow(),
      (): void => { this.leaveDialogOpen = false; }
    );
  }

  private endLiveForEveryone(): void {
    if (this.endingLive || this.groupCallId <= 0) { return; }
    this.endingLive = true;
    this.setMediaStatus(str('lv_ending'));
    endGroupCall(getTdClient(), this.groupCallId).then((): void => {
      this.setMediaStatus(str('lfw_ended'));
      this.leaveNow();
    }).catch((error: Error): void => {
      this.endingLive = false;
      this.setMediaStatus(str('lv_end_failed', error.message));
    });
  }

  private leaveNow(): void {
    if (this.isFullscreen) {
      this.isFullscreen = false;
      this.fullscreenPanelOpen = false;
      setLiveStreamFullscreen(getContext(this) as common.UIAbilityContext, false);
    }
    router.back();
  }

  private minimizeToFloating(): void {
    const session = this.tgcallsSession;
    if (session === null) {
      this.setMediaStatus(str('lv_not_ready'));
      return;
    }
    if (this.minimizeInProgress || this.leaveDialogOpen || this.endingLive ||
      this.groupCallId <= 0 || !this.headerPresentation().actionsEnabled) { return; }
    this.minimizeInProgress = true;
    const descriptor: FloatingLiveDescriptor = {
      groupCallId: this.groupCallId,
      chatId: this.chatId,
      isRtmp: false,
      title: this.displayTitle(),
      participantCount: this.displayParticipantCount(),
      primarySource: this.videoSources.length > 0 ? this.videoSources[0] : null
    };
    const handoff: FloatingLiveSessionHandoff = {
      descriptor,
      session,
      liveState: this.state,
      isMuted: this.isMuted,
      mediaConnected: this.mediaConnected,
      hasJoinedOnce: this.hasJoinedOnce,
      visualReady: this.videoSources.length === 0 || this.mediaConnected,
      videoAspectRatio: this.primaryVideoAspectRatio,
      localVideoMode: this.localVideoMode,
      localVideoActive: this.localVideoActive,
      desiredLocalVideoMode: this.desiredLocalVideoMode,
      screenShareActive: this.screenShareActive,
      screenShareDesired: this.screenShareDesired
    };
    const abilityContext = getContext(this) as common.UIAbilityContext;
    const shown = floatingLiveWindow.showSeamless(
      this.getUIContext(), abilityContext, handoff
    );
    if (!shown) {
      this.minimizeInProgress = false;
      this.setMediaStatus(str('lv_no_floating_window'));
      return;
    }
    if (this.localVideoActive) { session.setLocalVideoSurface('0'); }
    this.tgcallsSession = null;
    this.pageActive = false;
    this.sessionSequence += 1;
    this.clearRecoveryTimer();
    if (this.isFullscreen) {
      this.isFullscreen = false;
      this.fullscreenPanelOpen = false;
      setLiveStreamFullscreen(abilityContext, false);
    }
    if (this.fullscreenTransitionTimer !== -1) {
      clearTimeout(this.fullscreenTransitionTimer);
      this.fullscreenTransitionTimer = -1;
    }
    this.fullscreenTransitioning = false;
    this.interactionDrawerOpen = false;
    this.leavingForFloating = true;
    router.back();
  }

  private toggleFullscreen(): void {
    if (this.fullscreenTransitioning) { return; }
    const next = !this.isFullscreen;
    this.fullscreenPanelOpen = false;
    this.interactionDrawerOpen = false;
    this.fullscreenTransitioning = true;
    this.fullscreenTransitionLabel = next ? str('lv_entering_fullscreen') : str('lv_exiting_fullscreen');
    this.isFullscreen = next;
    setLiveStreamFullscreen(
      getContext(this) as common.UIAbilityContext, next,
      next ? this.primaryVideoAspectRatio : 0
    );
    if (this.fullscreenTransitionTimer !== -1) {
      clearTimeout(this.fullscreenTransitionTimer);
    }
    this.fullscreenTransitionTimer = setTimeout((): void => {
      this.fullscreenTransitionTimer = -1;
      if (!this.pageActive) { return; }
      this.fullscreenTransitioning = false;
      this.fullscreenTransitionLabel = '';
    }, powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 320));
  }

  private displayTitle(): string {
    if (this.state.title !== '') { return this.state.title; }
    if (this.initialTitle !== '') { return this.initialTitle; }
    return this.groupCallId > 0 ? str('lv_stream') : str('lv_cannot_open');
  }

  // Text and phase are set together and only here, so the two cannot drift
  // apart. The header classifies state from the phase; before this it matched
  // substrings of the sentence, which both misfired and would have broken
  // silently once this page was translated.
  private setMediaStatus(text: string, phase: string = LIVE_PHASE_NONE): void {
    this.mediaStatus = text;
    this.mediaPhase = phase;
  }

  private displayParticipantCount(): number {
    return this.headerStateResolved
      ? this.state.participantCount
      : Math.max(this.state.participantCount, this.initialParticipantCount);
  }

  private headerPresentation(): LiveViewerHeaderPresentation {
    return liveViewerHeaderPresentation({
      valid: this.groupCallId > 0,
      resolved: this.headerStateResolved,
      queryFailed: this.headerQueryFailed,
      active: this.state.isActive,
      joined: this.state.isJoined,
      joinedOnce: this.hasJoinedOnce,
      recovering: this.hasJoinedOnce && (this.recoveryUiVisible || this.recoveryInFlight),
      ending: this.endingLive,
      terminalError: false,
      reconnectAttempt: this.reconnectAttempt,
      retrySeconds: this.retrySeconds,
      canMinimize: this.tgcallsSession !== null,
      participantCount: this.displayParticipantCount(),
      mediaPhase: this.mediaPhase
    });
  }

  private mediaPresentation(): LiveViewerMediaPresentation {
    return liveViewerMediaPresentation({
      mode: 'group',
      valid: this.groupCallId > 0,
      resolved: this.headerStateResolved,
      active: this.state.isActive,
      joined: this.state.isJoined,
      joinedOnce: this.hasJoinedOnce,
      recovering: this.hasJoinedOnce && (this.recoveryUiVisible || this.recoveryInFlight),
      ending: this.endingLive,
      terminalError: false,
      reconnectAttempt: this.reconnectAttempt,
      retrySeconds: this.retrySeconds,
      retryable: !this.recoveryInFlight,
      hasVideo: this.videoSources.length > 0 || this.isLocalCameraActive(),
      visualReady: true,
      participantCount: Math.max(this.participants.length, this.displayParticipantCount()),
      mediaPhase: this.mediaPhase,
      error: this.connectionError !== '' ? this.connectionError : this.state.error
    });
  }

  private activeAudioSpeaker(): GroupCallParticipantInfo | null {
    const speaking = this.participants.find(
      (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
    );
    return speaking ?? null;
  }

  private audioStageName(): string {
    const speaker = this.activeAudioSpeaker();
    return speaker !== null && speaker.name !== '' ? speaker.name : this.displayTitle();
  }

  private audioStageInitials(): string {
    const speaker = this.activeAudioSpeaker();
    if (speaker !== null && speaker.initials !== '') { return speaker.initials; }
    const title = this.displayTitle().trim();
    return title !== '' ? title.substring(0, 1).toUpperCase() : 'L';
  }

  private audioStageColor(): string {
    const speaker = this.activeAudioSpeaker();
    const seed = speaker !== null ? speaker.colorSeed : this.groupCallId;
    return AVATAR_COLORS[Math.abs(seed) % AVATAR_COLORS.length];
  }

  private hiddenVideoSourceCount(): number {
    const visibleRemoteCount = this.isLocalCameraActive() ? 6 : 7;
    return Math.max(0, this.videoSources.length - visibleRemoteCount);
  }

  private headerDotColor(): string {
    const kind = this.headerPresentation().kind;
    if (kind === 'error' || kind === 'ending') { return CALL_RED; }
    if (kind === 'ended' || kind === 'invalid') { return CALL_SUBTEXT; }
    if (kind === 'connecting' || kind === 'joining' || kind === 'recovering') { return '#4C9AFF'; }
    if (kind === 'waiting') { return '#E3A23A'; }
    return CALL_GREEN;
  }

  private retryLiveConnection(): void {
    if (!this.headerPresentation().retryable && !this.mediaPresentation().retryable) { return; }
    const queryOnly = this.headerQueryFailed && this.tgcallsSession !== null &&
      this.connectionError === '' && !this.recoveryUiVisible;
    this.headerQueryFailed = false;
    this.connectionError = '';
    this.refreshGroupCall('顶部状态手动重试'); // i18n-exempt: diagnostic trace tag, console only
    if (queryOnly || this.recoveryInFlight) { return; }
    this.clearRecoveryTimer();
    this.showRecoveryUi(this.hasJoinedOnce ? 0 : 700);
    this.replaceSession('用户手动重试'); // i18n-exempt: diagnostic trace tag, console only
  }

  @Builder
  headerMoreMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.lv_minimise') })
        .enabled(this.headerPresentation().actionsEnabled && !this.minimizeInProgress)
        .onClick((): void => this.minimizeToFloating());
      MenuItem({ content: this.canManageLive ? $r('app.string.lv_manage_or_leave') : $r('app.string.lv_leave') })
        .enabled(!this.leaveDialogOpen && !this.endingLive)
        .onClick((): void => this.leave());
    }
  }

  onBackPress(): boolean {
    if (this.interactionDrawerOpen) {
      this.closeInteractionDrawer();
      return true;
    }
    if (this.fullscreenPanelOpen) {
      this.fullscreenPanelOpen = false;
      return true;
    }
    if (this.isFullscreen) {
      this.toggleFullscreen();
      return true;
    }
    this.leave();
    return true;
  }

  private selectPrimaryVideo(endpointId: string): void {
    const selected = this.videoSources.find(
      (source: GroupCallVideoSource): boolean => source.endpointId === endpointId
    );
    if (selected === undefined || this.videoSources[0]?.endpointId === endpointId) { return; }
    const sequence = ++this.videoSwitchSequence;
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
    }, (): void => {
      this.videoAreaOpacity = 0.64;
    });
    setTimeout((): void => {
      if (sequence !== this.videoSwitchSequence) { return; }
      this.primaryVideoPinned = true;
      this.preferredPrimaryEndpointId = endpointId;
      this.videoSources = [selected, ...this.videoSources.filter(
        (source: GroupCallVideoSource): boolean => source.endpointId !== endpointId
      )];
      this.refreshPrimaryVideoAspect();
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 210), curve: Curve.FastOutSlowIn
      }, (): void => {
        this.videoAreaOpacity = 1;
      });
    }, 115);
  }

  private startPulseAnimation(): void {
    if (this.pulseTimer !== -1) { return; }
    this.pulseTimer = setInterval((): void => {
      if (!powerFeatureEnabled(KEY_POWER_CALL_ANIMATIONS)) {
        this.pulseExpanded = false;
        this.microphoneScale = 1;
        return;
      }
      const hasSpeaker = this.participants.some(
        (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
      );
      if (this.isMuted && !hasSpeaker) {
        if (this.pulseExpanded) {
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 260), curve: Curve.EaseOut
          }, (): void => {
            this.pulseExpanded = false;
          });
        }
        return;
      }
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 680), curve: Curve.EaseInOut
      }, (): void => {
        this.pulseExpanded = !this.pulseExpanded;
      });
    }, 720);
  }

  private animateMicrophoneTap(): void {
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 85), curve: Curve.EaseOut
    }, (): void => {
      this.microphoneScale = 0.91;
    });
    setTimeout((): void => {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 240), curve: Curve.Friction
      }, (): void => {
        this.microphoneScale = 1;
      });
    }, 90);
  }

  aboutToDisappear(): void {
    this.interactionDrawerOpen = false;
    this.interactionSnapshotReady = false;
    if (!this.leavingForFloating) {
      setLiveStreamKeepScreenOn(getContext(this) as common.UIAbilityContext, false);
    }
    if (this.isFullscreen) {
      this.isFullscreen = false;
      this.fullscreenPanelOpen = false;
      setLiveStreamFullscreen(getContext(this) as common.UIAbilityContext, false);
    }
    if (this.fullscreenTransitionTimer !== -1) {
      clearTimeout(this.fullscreenTransitionTimer);
      this.fullscreenTransitionTimer = -1;
    }
    this.fullscreenTransitioning = false;
    this.pageActive = false;
    this.sessionSequence += 1;
    this.recoveryInFlight = false;
    this.clearRecoveryTimer();
    if (this.healthTimer !== -1) { clearInterval(this.healthTimer); this.healthTimer = -1; }
    if (!this.leavingForFloating) { liveStreamBackgroundTask.stop(); }
    if (this.pulseTimer !== -1) { clearInterval(this.pulseTimer); this.pulseTimer = -1; }
    this.videoSwitchSequence += 1;
    if (this.offInteractionMessages !== null) {
      this.offInteractionMessages();
      this.offInteractionMessages = null;
    }
    if (this.offInteractionError !== null) {
      this.offInteractionError();
      this.offInteractionError = null;
    }
    this.interactionStore?.close();
    this.interactionStore = null;
    this.interactionMessages = [];
    if (this.offParticipants !== null) { this.offParticipants(); this.offParticipants = null; }
    if (this.participantStore !== null) { this.participantStore.dispose(); this.participantStore = null; }
    if (this.tgcallsSession !== null) {
      this.tgcallsSession.clearVideo();
      this.tgcallsSession.stop();
      this.tgcallsSession = null;
    }
    this.requestedEndpoints.clear();
    this.surfaceBindings.clear();
    this.localPreviewSurfaceId = '0';
    this.unifiedSource = null;
    this.selfParticipantId = null;
    if (this.off !== null) { this.off(); this.off = null; }
    if (this.store !== null) { this.store.dispose(); this.store = null; }
    if (this.groupCallId > 0 && !this.leavingForFloating) {
      leaveGroupCall(getTdClient(), this.groupCallId).catch((error: Error): void => {
        logE(`LiveStreamViewerPage.leaveGroupCall failed: ${error.message}`);
      });
    }
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(23).fontColor([CALL_TEXT]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
      })
      .accessibilityText($r('app.string.lv_leave'))
      .onClick((): void => this.leave());
      Column({ space: 2 }) {
        Text(this.displayTitle())
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 }).fill(this.headerDotColor())
            .opacity(this.headerPresentation().pulse && this.pulseExpanded ? 1 : 0.62)
            .scale({
              x: this.headerPresentation().pulse && this.pulseExpanded ? 1.13 : 0.9,
              y: this.headerPresentation().pulse && this.pulseExpanded ? 1.13 : 0.9
            });
          Text(this.headerPresentation().statusText)
            .fontSize(12).fontColor(
              this.headerPresentation().kind === 'error' ? CALL_RED : CALL_SUBTEXT
            )
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.canManageLive) {
            Text($r('app.string.ga_admin'))
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor(CALL_GREEN)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor('#2639D98A').borderRadius(8);
          }
        }
        .onClick((): void => this.retryLiveConnection());
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row() {
        SymbolGlyph($r('sys.symbol.plus_square_on_square')).fontSize(19).fontColor([CALL_TEXT]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .backgroundColor('#26323C')
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
      })
      .enabled(this.headerPresentation().actionsEnabled && !this.minimizeInProgress &&
        !this.leaveDialogOpen)
      .accessibilityText(this.minimizeInProgress ? $r('app.string.lv_minimising') : $r('app.string.lv_minimise'))
      .onClick((): void => this.minimizeToFloating());
      Row() {
        SymbolGlyph($r('sys.symbol.more')).fontSize(22).fontColor([CALL_TEXT]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .backgroundColor('#26323C')
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
      })
      .enabled(this.groupCallId > 0 && !this.minimizeInProgress)
      .accessibilityText($r('app.string.lv_more_actions'))
      .bindMenu(this.headerMoreMenu());
    }
    .width('100%').height(64).padding({ left: 8, right: 10 })
    .alignItems(VerticalAlign.Center).backgroundColor(CALL_BACKGROUND);
  }

  @Builder
  emptyMediaStage() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 145,
          colors: [['#172832', 0], ['#0B1218', 1]]
        });
      if (this.mediaPresentation().kind === 'audio') {
        Column({ space: 7 }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.mediaPresentation().pulse) {
              Circle({ width: 82, height: 82 }).fill('#3339D98A')
                .opacity(this.pulseExpanded ? 0.22 : 0.5)
                .scale({
                  x: this.pulseExpanded ? 1.1 : 0.92,
                  y: this.pulseExpanded ? 1.1 : 0.92
                });
            }
            Circle({ width: 64, height: 64 }).fill(this.audioStageColor());
            Text(this.audioStageInitials())
              .fontSize(23).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
          .width(86).height(86);
          Text(this.audioStageName())
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.activeAudioSpeaker() !== null ? $r('app.string.lv_speaking') : this.mediaPresentation().detail)
            .fontSize(12).fontColor(CALL_SUBTEXT);
        }
      } else {
        Column({ space: 9 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 52, height: 52 }).fill('#263641');
            if (this.mediaPresentation().showProgress) {
              LoadingProgress().width(26).height(26).color('#65A9FF');
            } else if (this.mediaPresentation().kind === 'error' ||
              this.mediaPresentation().kind === 'invalid') {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(25).fontColor([CALL_RED]);
            } else {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor([Color.White]);
            }
          }
          .width(56).height(56);
          Text(this.mediaPresentation().title)
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT);
          Text(this.mediaPresentation().detail)
            .fontSize(12).fontColor(CALL_SUBTEXT).textAlign(TextAlign.Center)
            .maxLines(2);
          if (this.mediaPresentation().retryable && this.mediaPresentation().actionText !== '') {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
              Text(this.mediaPresentation().actionText)
                .fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White);
            }
            .height(32).padding({ left: 11, right: 12 })
            .backgroundColor('#C83390EC').borderRadius(16)
            .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
            .accessibilityText(this.mediaPresentation().actionText)
            .onClick((): void => this.retryLiveConnection());
          }
        }
      }
      if (this.mediaPresentation().badgeText !== '') {
        Column() {
          Row({ space: 6 }) {
            Circle({ width: 7, height: 7 }).fill(
              this.mediaPresentation().badgeTone === 'danger' ? CALL_RED :
                (this.mediaPresentation().badgeTone === 'muted' ? CALL_SUBTEXT : CALL_GREEN)
            ).opacity(this.mediaPresentation().pulse && this.pulseExpanded ? 1 : 0.65);
            Text(this.mediaPresentation().badgeText)
              .fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
          .padding({ left: 9, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#A617222B').borderRadius(12)
          .alignSelf(ItemAlign.Start).margin({ left: 12, top: 12 });
          Blank();
        }
        .width('100%').height('100%');
      }
    }
    .width('100%').height(210)
    .borderRadius(14).clip(true)
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 190), curve: Curve.EaseOut
    }));
  }

  @Builder
  mediaStage() {
    if (this.videoSources.length === 0 && !this.isLocalCameraActive()) {
      this.emptyMediaStage();
    } else {
      Stack({ alignContent: Alignment.Top }) {
        this.videoArea();
        if (this.mediaPresentation().kind === 'recovering' ||
          this.mediaPresentation().kind === 'ended') {
          Column({ space: 8 }) {
            if (this.mediaPresentation().showProgress) {
              LoadingProgress().width(25).height(25).color(Color.White);
            }
            Text(this.mediaPresentation().title)
              .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White);
            Text(this.mediaPresentation().detail)
              .fontSize(11).fontColor('#D7E0E6').textAlign(TextAlign.Center);
            if (this.mediaPresentation().retryable && this.mediaPresentation().actionText !== '') {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
                Text(this.mediaPresentation().actionText)
                  .fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White);
              }
              .height(32).padding({ left: 11, right: 12 })
              .backgroundColor('#D93390EC').borderRadius(16)
              .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
              .onClick((): void => this.retryLiveConnection());
            }
          }
          .width('100%').height(210).justifyContent(FlexAlign.Center)
          .backgroundColor(this.mediaPresentation().keepVisual ? '#66101920' : '#B0101920')
          .transition(TransitionEffect.OPACITY.animation({
            duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 170), curve: Curve.EaseOut
          }));
        }
      }
      .width('100%');
    }
  }

  @Builder
  videoArea() {
    if (this.videoSources.length === 0 && !this.isLocalCameraActive()) {
      Column() {
        SymbolGlyph($r('sys.symbol.camera')).fontSize(38).fontColor([CALL_SUBTEXT]);
        Text(this.mediaStatus).fontSize(13).fontColor(CALL_SUBTEXT).margin({ top: 10 });
      }
      .width('100%').height(210).justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Black).borderRadius(8);
    } else if (this.videoSources.length === 0) {
      LocalVideoPreviewTile({
        mode: this.localVideoMode,
        tileWidth: '100%',
        tileHeight: '210vp',
        showFullscreenButton: true,
        fullscreen: false,
        onSurfaceReady: (
          surfaceId: string, surfaceWidth: number, surfaceHeight: number
        ): void => this.setLocalPreviewSurface(surfaceId, surfaceWidth, surfaceHeight),
        onSurfaceGone: (surfaceId: string): void =>
          this.clearLocalPreviewSurface(surfaceId),
        onFullscreenToggle: (): void => this.toggleFullscreen()
      });
    } else if (this.videoSources.length === 1 && this.isLocalCameraActive()) {
      // Camera + screen share are two independent Telegram video endpoints.
      // Present them like two speakers instead of hiding the camera in PiP.
      Row({ space: 3 }) {
        Column() {
          LiveVideoTile({
            source: this.videoSources[0],
            tileHeight: 210,
            showFullscreenButton: true,
            fullscreen: false,
            pulseExpanded: this.pulseExpanded,
            onSurfaceReady: (
              endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
            ): void => this.setSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight),
            onSurfaceGone: (endpointId: string, surfaceId: string): void =>
              this.clearSurface(endpointId, surfaceId),
            onFullscreenToggle: (): void => this.toggleFullscreen()
          });
        }
        .layoutWeight(1).height(210);
        Column() {
          LocalVideoPreviewTile({
            mode: this.localVideoMode,
            tileWidth: '100%',
            tileHeight: '210vp',
            onSurfaceReady: (
              surfaceId: string, surfaceWidth: number, surfaceHeight: number
            ): void => this.setLocalPreviewSurface(surfaceId, surfaceWidth, surfaceHeight),
            onSurfaceGone: (surfaceId: string): void =>
              this.clearLocalPreviewSurface(surfaceId)
          });
        }
        .layoutWeight(1).height(210);
      }
      .width('100%').height(210);
    } else {
      LiveVideoTile({
        source: this.videoSources[0],
        tileHeight: 210,
        showFullscreenButton: true,
        fullscreen: false,
        pulseExpanded: this.pulseExpanded,
        onSurfaceReady: (
          endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
        ): void => this.setSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight),
        onSurfaceGone: (endpointId: string, surfaceId: string): void =>
          this.clearSurface(endpointId, surfaceId),
        onFullscreenToggle: (): void => this.toggleFullscreen()
      });
      if (this.videoSources.length > 1 || this.isLocalCameraActive()) {
        Grid() {
          ForEach(
            this.videoSources.slice(1, this.isLocalCameraActive() ? 6 : 7),
            (source: GroupCallVideoSource) => {
              GridItem() {
                Stack() {
                  LiveVideoTile({
                    source,
                    tileHeight: 132,
                    pulseExpanded: this.pulseExpanded,
                    onSurfaceReady: (
                      endpointId: string, surfaceId: string,
                      surfaceWidth: number, surfaceHeight: number
                    ): void => this.setSurface(
                      endpointId, surfaceId, surfaceWidth, surfaceHeight
                    ),
                    onSurfaceGone: (endpointId: string, surfaceId: string): void =>
                      this.clearSurface(endpointId, surfaceId)
                  });
                }
                .width('100%').height(132)
                .accessibilityText(str('lv_switch_to', source.name !== '' ? source.name : str('lv_this_video')))
                .onClick((): void => this.selectPrimaryVideo(source.endpointId));
              }
            },
            (source: GroupCallVideoSource): string => source.endpointId
          )
          if (this.isLocalCameraActive()) {
            GridItem() {
              LocalVideoPreviewTile({
                mode: this.localVideoMode,
                tileWidth: '100%',
                tileHeight: '132vp',
                onSurfaceReady: (
                  surfaceId: string, surfaceWidth: number, surfaceHeight: number
                ): void => this.setLocalPreviewSurface(
                  surfaceId, surfaceWidth, surfaceHeight
                ),
                onSurfaceGone: (surfaceId: string): void =>
                  this.clearLocalPreviewSurface(surfaceId)
              });
            }
          }
          if (this.hiddenVideoSourceCount() > 0) {
            GridItem() {
              Column({ space: 5 }) {
                Text(`+${this.hiddenVideoSourceCount()}`)
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White);
                Text($r('app.string.lv_more_feeds')).fontSize(11).fontColor(CALL_SUBTEXT);
              }
              .width('100%').height(132).justifyContent(FlexAlign.Center)
              .backgroundColor('#16232D').borderRadius(8);
            }
            .accessibilityText(plural('lv_more_sources', this.hiddenVideoSourceCount(), this.hiddenVideoSourceCount()));
          }
        }
        .columnsTemplate('1fr 1fr').columnsGap(3).rowsGap(3)
        .height(Math.ceil((
          Math.min(this.videoSources.length, this.isLocalCameraActive() ? 6 : 7) - 1 +
          (this.isLocalCameraActive() ? 1 : 0) +
          (this.hiddenVideoSourceCount() > 0 ? 1 : 0)
        ) / 2) * 135)
        .width('100%').margin({ top: 3 });
      }
    }
  }

  @Builder
  participantRow(participant: GroupCallParticipantInfo) {
    Row({ space: 12 }) {
      Stack() {
        if (participant.isSpeaking) {
          Circle({ width: 50, height: 50 }).fill('#4439D98A')
            .opacity(this.pulseExpanded ? 0.28 : 0.72)
            .scale({ x: this.pulseExpanded ? 1.08 : 0.92, y: this.pulseExpanded ? 1.08 : 0.92 });
        }
        Circle({ width: 42, height: 42 })
          .fill(AVATAR_COLORS[Math.abs(participant.colorSeed) % AVATAR_COLORS.length]);
        Text(participant.initials).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White);
      }
      .width(42).height(42);
      Column() {
        Text(participant.isCurrentUser ? str('lv_participant_you', participant.name) : participant.name)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(CALL_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(participant.isSpeaking ? $r('app.string.lv_speaking') :
          (participant.isMuted
            ? (this.canManageLive && !participant.isCurrentUser
              ? $r('app.string.lv_mic_off_tap_allow') : $r('app.string.lfw_mic_off'))
            : (this.canManageLive && !participant.isCurrentUser
              ? $r('app.string.lv_can_speak_tap_mute') : $r('app.string.lv_listening'))))
          .fontSize(12).fontColor(participant.isSpeaking ? CALL_GREEN : CALL_SUBTEXT).margin({ top: 3 });
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Stack({ alignContent: Alignment.Center }) {
        if (participant.isSpeaking) {
          Circle({ width: 34, height: 34 }).fill('#4939D98A')
            .opacity(this.pulseExpanded ? 0.35 : 0.78)
            .scale({ x: this.pulseExpanded ? 1.08 : 0.9, y: this.pulseExpanded ? 1.08 : 0.9 });
        }
        SymbolGlyph($r('sys.symbol.mic'))
          .fontSize(participant.isSpeaking && this.pulseExpanded ? 22 : 20)
          .fontColor([participant.isSpeaking ? CALL_GREEN :
            (participant.isMuted ? '#53616C' : CALL_SUBTEXT)]);
        if (participant.isMuted && !participant.isSpeaking) {
          Text('╱').fontSize(24).fontColor('#697782').fontWeight(FontWeight.Bold);
        }
      }
      .width(36).height(36)
      .backgroundColor(
        this.canManageLive && !participant.isCurrentUser ? '#26323C' : Color.Transparent
      )
      .borderRadius(18)
      .onClick((): void => this.toggleParticipantMuted(participant));
    }
    .width('100%').height(62).padding({ left: 12, right: 12 })
    .backgroundColor(participant.isSpeaking ? '#192A2B' : CALL_PANEL)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.EaseOut
    });
  }

  private interactionPreviewText(): string {
    if (this.interactionUnreadCount > 0) { return plural('lv_new_interactions', this.interactionUnreadCount, this.interactionUnreadCount); }
    if (this.interactionMessages.length === 0) { return this.callInteractionPresentation().subtitle; }
    const latest = this.interactionMessages[this.interactionMessages.length - 1];
    return str('lv_latest_message', latest.senderName, latest.text !== '' ? latest.text : str('lv_shared_media'));
  }

  @Builder
  interactionDock() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 36, height: 36 }).fill('#263390EC');
        SymbolGlyph($r('sys.symbol.message')).fontSize(18).fontColor(['#8FC2FF']);
        if (this.interactionUnreadCount > 0) {
          Text(this.interactionUnreadCount > 99 ? '99+' : `${this.interactionUnreadCount}`)
            .fontSize(8).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .height(16).constraintSize({ minWidth: 16 }).padding({ left: 4, right: 4 })
            .backgroundColor('#FF405C').borderRadius(8)
            .position({ x: 25, y: -3 });
        }
      }.width(38).height(38);
      Column({ space: 3 }) {
        Text($r('app.string.lv_interactions')).fontSize(14).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT);
        Text(this.interactionPreviewText())
          .fontSize(10).fontColor(this.interactionUnreadCount > 0 ? '#8FC2FF' : CALL_SUBTEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 }).fill(this.callInteractionStatusColor());
        Text(this.callInteractionPresentation().statusText)
          .fontSize(10).fontColor(this.callInteractionStatusColor());
      }
      .height(26).padding({ left: 8, right: 9 })
      .backgroundColor(this.callInteractionStatusBackground()).borderRadius(13);
      SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(13).fontColor([CALL_SUBTEXT]);
    }
    // width('100%') 不能和横向 margin 同时用：百分比宽先按父宽定值，margin 再叠在
    // 外部，总宽 = 父宽 + left + right，右端会被裁掉。宽度改用 calc 扣掉左右 margin。
    .width('calc(100% - 16vp)').height(58).padding({ left: 12, right: 12 })
    .margin({ left: 8, right: 8, top: 6, bottom: 5 })
    .backgroundColor(CALL_PANEL).borderRadius(16)
    .border({ width: 1, color: '#182F4350' })
    .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 140), curve: Curve.EaseOut
    })
    .accessibilityText(this.interactionUnreadCount > 0
      ? plural('lv_open_chat_unread', this.interactionUnreadCount, this.interactionUnreadCount) : str('lv_open_chat'))
    .onClick((): void => this.openInteractionDrawer());
  }

  @Builder
  interactionMessageList() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.interactionMessages.length === 0) {
        Column({ space: 7 }) {
          if (this.callInteractionPresentation().showProgress) {
            Progress({ value: 30, total: 100, type: ProgressType.Ring })
              .width(28).height(28).color('#64A8FF').style({ strokeWidth: 3 });
          } else {
            SymbolGlyph($r('sys.symbol.message')).fontSize(30).fontColor([CALL_SUBTEXT]);
          }
          Text(this.callInteractionPresentation().emptyTitle)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(CALL_TEXT);
          Text(this.callInteractionPresentation().emptyDetail)
            .fontSize(11).fontColor(CALL_SUBTEXT);
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else {
        List({ scroller: this.interactionScroller, space: 8 }) {
          ForEach(this.interactionMessages, (message: LiveInteractionEntry) => {
            ListItem() { LiveInteractionBubble({ message }); }
          }, (message: LiveInteractionEntry): string => message.key)
        }
        .width('100%').height('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .maintainVisibleContentPosition(true)
        .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) {
            this.interactionTouchActive = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.interactionTouchActive = false;
            this.refreshInteractionAtBottom();
          }
        })
        .onScrollIndex((): void => this.refreshInteractionAtBottom())
        .onDidScroll((): void => this.refreshInteractionAtBottom());
      }
      if (this.interactionUnreadCount > 0) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(13).fontColor([Color.White]);
          Text(plural('lv_new_interactions', this.interactionUnreadCount, this.interactionUnreadCount))
            .fontSize(11).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .height(32).padding({ left: 11, right: 12 }).margin({ bottom: 10 })
        .backgroundColor('#E63390EC').borderRadius(16)
        .shadow({ radius: 10, color: '#52000000', offsetX: 0, offsetY: 3 })
        .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
        .onClick((): void => this.scrollToInteractionTail());
      }
    }
    .width('100%').layoutWeight(1).backgroundColor(CALL_PANEL);
  }

  @Builder
  interactionComposer() {
    if (this.callInteractionPresentation().composerEnabled) {
      Column({ space: 7 }) {
        Row({ space: 8 }) {
          ForEach(CALL_QUICK_REACTIONS, (emoji: string) => {
            Text(emoji).fontSize(20).textAlign(TextAlign.Center)
              .width(36).height(32).borderRadius(16).backgroundColor('#1B2A35')
              .enabled(!this.interactionSending)
              .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
              .onClick((): void => this.sendInteraction(emoji));
          }, (emoji: string): string => emoji)
        }.width('100%');
        Row({ space: 9 }) {
          TextInput({ text: this.interactionDraft, placeholder: $r('app.string.lv_say_something') })
            .layoutWeight(1).height(42).fontSize(14).fontColor(CALL_TEXT)
            .placeholderColor(CALL_SUBTEXT).backgroundColor('#1B2A35').borderRadius(21)
            .padding({ left: 15, right: 15 }).enterKeyType(EnterKeyType.Send)
            .onChange((value: string): void => { this.interactionDraft = value; })
            .onSubmit((): void => this.sendInteraction());
          Button({ type: ButtonType.Circle }) {
            if (this.interactionSending) {
              Progress({ value: 30, total: 100, type: ProgressType.Ring })
                .width(17).height(17).color(Color.White).style({ strokeWidth: 2 });
            } else {
              SymbolGlyph($r('sys.symbol.paperplane')).fontSize(18).fontColor([Color.White]);
            }
          }
          .width(42).height(42).padding(0)
          .backgroundColor(this.interactionDraft.trim() === '' || this.interactionSending
            ? '#40505C' : '#3390EC')
          .enabled(this.interactionDraft.trim() !== '' && !this.interactionSending)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .onClick((): void => this.sendInteraction());
        }.width('100%');
        if (this.interactionSendError !== '') {
          Row({ space: 6 }) {
            Text(this.interactionSendError).fontSize(10).fontColor('#FF9AA6')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
            Text($r('app.string.settings_retry')).fontSize(10).fontColor('#64A8FF')
              .height(26).padding({ left: 6, right: 6 })
              .onClick((): void => this.retryInteractionSend());
          }.width('100%');
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 9, bottom: Math.max(12, this.bottomSafe + 6) })
      .backgroundColor(CALL_BACKGROUND);
    } else {
      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(14).fontColor([CALL_SUBTEXT]);
        Text(this.callInteractionPresentation().composerHint)
          .fontSize(11).fontColor(CALL_SUBTEXT);
      }
      .width('100%').height(48 + Math.max(0, this.bottomSafe))
      .padding({ bottom: Math.max(0, this.bottomSafe) })
      .justifyContent(FlexAlign.Center).backgroundColor(CALL_BACKGROUND);
    }
  }

  @Builder
  interactionDrawer() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%').height('100%').backgroundColor('#78000000')
        .onClick((): void => this.closeInteractionDrawer());
      Column() {
        Column({ space: 7 }) {
          Rect({ width: 38, height: 4, radius: 2 }).fill('#53616C');
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text($r('app.string.lv_interactions')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT);
              Text(str('lv_count_and_status', this.interactionMessages.length, this.callInteractionPresentation().statusText))
                .fontSize(11).fontColor(CALL_SUBTEXT);
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([CALL_TEXT]);
            }
            .width(36).height(36).padding(0).backgroundColor('#263641')
            .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
            .onClick((): void => this.closeInteractionDrawer());
          }.width('100%');
        }
        .width('100%').height(68).padding({ left: 14, right: 12, top: 8 })
        .justifyContent(FlexAlign.Center)
        .priorityGesture(
          PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 8 })
            .onActionEnd((event: GestureEvent): void =>
              this.closeInteractionDrawerOnSwipe(event.offsetY))
        );
        this.interactionMessageList();
        this.interactionComposer();
      }
      .width('100%').height('68%').constraintSize({ minHeight: 390, maxHeight: 640 })
      .backgroundColor(CALL_PANEL)
      .borderRadius({ topLeft: 24, topRight: 24 })
      .shadow({ radius: 28, color: '#90000000', offsetX: 0, offsetY: -8 })
      .transition(
        TransitionEffect.translate({ y: 80 }).combine(TransitionEffect.OPACITY).animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 220), curve: Curve.EaseOut
        })
      );
    }
    .width('100%').height('100%')
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 160), curve: Curve.EaseOut
    }));
  }

  @Builder
  roundButton(symbol: Resource, color: string, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol).fontSize(24).fontColor([Color.White]);
    }
    .width(52).height(52).backgroundColor(color).onClick(onTap);
  }

  @Builder
  localMediaButton(
    symbol: Resource, label: string, active: boolean,
    inactiveColor: string, onTap: () => void
  ) {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(symbol).fontSize(21)
          .fontColor([active ? CALL_BACKGROUND : Color.White]);
      }
      .width(46).height(46)
      .backgroundColor(active ? CALL_GREEN : inactiveColor)
      .border({ width: active ? 2 : 0, color: '#BFFFFFFF' })
      .shadow({
        radius: active ? 12 : 0,
        color: active ? '#8039D98A' : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      .onClick(onTap);
      Text(label).fontSize(10).fontColor(active ? CALL_GREEN : CALL_SUBTEXT);
    }
    .width(52).alignItems(HorizontalAlign.Center);
  }

  @Builder
  cameraMediaButton() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.camera')).fontSize(21)
          .fontColor([this.localVideoActive ? CALL_BACKGROUND : Color.White]);
      }
      .width(46).height(46)
      .backgroundColor(
        this.localVideoActive ? CALL_GREEN :
          (this.localVideoBusy ? '#3D6256' : '#34424D')
      )
      .border({ width: this.localVideoActive ? 2 : 0, color: '#BFFFFFFF' })
      .shadow({
        radius: this.localVideoActive ? 12 : 0,
        color: this.localVideoActive ? '#8039D98A' : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      .enabled(!this.localVideoBusy)
      .onClick((): void => { this.toggleCamera(); });
      Text(this.localVideoBusy ? $r('app.string.processing_short') : $r('app.string.lv_camera'))
        .fontSize(10)
        .fontColor(this.localVideoActive ? CALL_GREEN :
          (this.localVideoBusy ? '#91B7AA' : CALL_SUBTEXT));
    }
    .width(52).alignItems(HorizontalAlign.Center)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    });
  }

  @Builder
  screenShareMediaButton() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.computer')).fontSize(21)
          .fontColor([this.screenShareActive ? CALL_BACKGROUND : Color.White]);
      }
      .width(46).height(46)
      .backgroundColor(
        this.screenShareActive ? CALL_GREEN :
          (this.screenShareBusy ? '#3D6256' : '#34424D')
      )
      .border({ width: this.screenShareActive ? 2 : 0, color: '#BFFFFFFF' })
      .shadow({
        radius: this.screenShareActive ? 12 : 0,
        color: this.screenShareActive ? '#8039D98A' : Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })
      .enabled(!this.screenShareBusy)
      .onClick((): void => { this.toggleScreenShare(); });
      Text(this.screenShareBusy ? $r('app.string.processing_short') : $r('app.string.lv_share_screen'))
        .fontSize(10)
        .fontColor(this.screenShareActive ? CALL_GREEN :
          (this.screenShareBusy ? '#91B7AA' : CALL_SUBTEXT));
    }
    .width(52).alignItems(HorizontalAlign.Center)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    });
  }

  @Builder
  switchCameraButton() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        Text('↻').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White);
      }
      .width(46).height(46)
      .backgroundColor(
        this.desiredLocalVideoMode === 1 || this.desiredLocalVideoMode === 2
          ? '#465661' : '#26323C'
      )
      .enabled(
        !this.localVideoBusy &&
        (this.desiredLocalVideoMode === 1 || this.desiredLocalVideoMode === 2)
      )
      .onClick((): void => { this.switchCamera(); });
      Text(this.desiredLocalVideoMode === 2 ? $r('app.string.lv_to_front') : $r('app.string.lv_to_rear'))
        .fontSize(10).fontColor(CALL_SUBTEXT);
    }
    .width(52).alignItems(HorizontalAlign.Center);
  }

  @Builder
  controls() {
    Column() {
      Row() {
        this.cameraMediaButton();
        this.screenShareMediaButton();
        Stack({ alignContent: Alignment.Center }) {
          if (!this.isMuted) {
            Circle({ width: 96, height: 96 }).fill('#2639D98A')
              .scale({ x: this.pulseExpanded ? 1.08 : 0.86, y: this.pulseExpanded ? 1.08 : 0.86 })
              .opacity(this.pulseExpanded ? 0.12 : 0.42);
            Circle({ width: 84, height: 84 }).fill('#3439D98A')
              .scale({ x: this.pulseExpanded ? 1.03 : 0.91, y: this.pulseExpanded ? 1.03 : 0.91 })
              .opacity(this.pulseExpanded ? 0.22 : 0.52);
          } else {
            Circle({ width: 82, height: 82 }).fill('#263E38');
          }
          Circle({ width: 68, height: 68 }).fill(this.isMuted ? '#2C6652' : CALL_GREEN);
          SymbolGlyph($r('sys.symbol.mic')).fontSize(this.pulseExpanded && !this.isMuted ? 34 : 31)
            .fontColor([Color.White]);
          if (this.isMuted) {
            Text('╱').fontSize(35).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
        }
        .width(98).height(104)
        .scale({ x: this.microphoneScale, y: this.microphoneScale })
        .onClick((): void => { this.toggleMuted(); });
        this.switchCameraButton();
        this.localMediaButton(
          $r('sys.symbol.phone_fill'), this.canManageLive ? str('lv_manage_short') : str('lv_leave_short'), false, CALL_RED,
          (): void => this.leave()
        );
      }
      .width('100%').justifyContent(FlexAlign.SpaceAround).alignItems(VerticalAlign.Center);
      Text(this.localVideoBusy && this.screenShareBusy ? $r('app.string.lv_starting_both') :
        (this.localVideoBusy ? $r('app.string.lv_starting_camera') :
          (this.screenShareBusy ? $r('app.string.lv_starting_screen') :
            (this.localVideoActive && this.screenShareActive
              ? $r('app.string.lv_both_live')
              : (this.screenShareActive ? $r('app.string.lv_sharing_screen') :
                (this.localVideoActive ? $r('app.string.lv_camera_live_switchable') :
                  (this.isMuted ? $r('app.string.lv_tap_mic_to_speak') : $r('app.string.lv_mic_on_speaking'))))))))
        .fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor((!this.isMuted || this.localVideoActive || this.screenShareActive)
          ? CALL_GREEN : CALL_TEXT)
        .margin({ top: 1 }).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').height(138).padding({ left: 6, right: 6, top: 1, bottom: 5 })
    .backgroundColor(CALL_BACKGROUND);
  }

  @Builder
  fullscreenParticipantDrawer() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => { this.fullscreenPanelOpen = false; });
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text($r('app.string.lv_voice_members')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(CALL_TEXT);
            Text(str('lv_participants_live', this.participants.length))
              .fontSize(11).fontColor(CALL_SUBTEXT);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([CALL_TEXT]);
          }
          .width(36).height(36).backgroundColor('#263641')
          .onClick((): void => { this.fullscreenPanelOpen = false; });
        }
        .width('100%').height(58).padding({ left: 14, right: 12 });
        if (this.participants.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.person_2')).fontSize(32).fontColor([CALL_SUBTEXT]);
            Text($r('app.string.lv_no_members')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(CALL_TEXT);
            Text(this.headerPresentation().statusText)
              .fontSize(11).fontColor(CALL_SUBTEXT).textAlign(TextAlign.Center);
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
        } else {
          Scroll() {
            Column({ space: 1 }) {
              ForEach(this.participants, (participant: GroupCallParticipantInfo) => {
                this.participantRow(participant);
              }, (participant: GroupCallParticipantInfo): string =>
                `fullscreen:${participant.key}:${participant.revision}`)
            }.width('100%');
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off);
        }
      }
      .width('82%').height('100%').constraintSize({ maxWidth: 430 })
      .backgroundColor('#F2131D25')
      .shadow({ radius: 24, color: '#80000000', offsetX: -8, offsetY: 0 })
      .transition(
        TransitionEffect.translate({ x: 26 }).combine(TransitionEffect.OPACITY).animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 210), curve: Curve.EaseOut
        })
      );
    }
    .width('100%').height('100%')
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 150), curve: Curve.EaseOut
    }));
  }

  @Builder
  fullscreenVideo() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.videoSources.length > 0 && this.isLocalCameraActive()) {
        Flex({
          direction: this.primaryVideoAspectRatio > 1.08
            ? FlexDirection.Row : FlexDirection.Column
        }) {
          Column() {
            LiveVideoTile({
              source: this.videoSources[0],
              fillParent: true,
              pulseExpanded: this.pulseExpanded,
              onSurfaceReady: (
                endpointId: string, surfaceId: string,
                surfaceWidth: number, surfaceHeight: number
              ): void => this.setSurface(
                endpointId, surfaceId, surfaceWidth, surfaceHeight
              ),
              onSurfaceGone: (endpointId: string, surfaceId: string): void =>
                this.clearSurface(endpointId, surfaceId)
            });
          }
          .layoutWeight(1)
          .margin({
            right: this.primaryVideoAspectRatio > 1.08 ? 1.5 : 0,
            bottom: this.primaryVideoAspectRatio > 1.08 ? 0 : 1.5
          });
          Column() {
            LocalVideoPreviewTile({
              mode: this.localVideoMode,
              tileWidth: '100%',
              tileHeight: '100%',
              onSurfaceReady: (
                surfaceId: string, surfaceWidth: number, surfaceHeight: number
              ): void => this.setLocalPreviewSurface(
                surfaceId, surfaceWidth, surfaceHeight
              ),
              onSurfaceGone: (surfaceId: string): void =>
                this.clearLocalPreviewSurface(surfaceId)
            });
          }
          .layoutWeight(1)
          .margin({
            left: this.primaryVideoAspectRatio > 1.08 ? 1.5 : 0,
            top: this.primaryVideoAspectRatio > 1.08 ? 0 : 1.5
          });
        }
        .width('100%').height('100%');
      } else if (this.videoSources.length > 0) {
        LiveVideoTile({
          source: this.videoSources[0],
          fillParent: true,
          pulseExpanded: this.pulseExpanded,
          onSurfaceReady: (
            endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
          ): void => this.setSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight),
          onSurfaceGone: (endpointId: string, surfaceId: string): void =>
            this.clearSurface(endpointId, surfaceId)
        });
      } else if (this.isLocalCameraActive()) {
        LocalVideoPreviewTile({
          mode: this.localVideoMode,
          tileWidth: '100%',
          tileHeight: '100%',
          onSurfaceReady: (
            surfaceId: string, surfaceWidth: number, surfaceHeight: number
          ): void => this.setLocalPreviewSurface(surfaceId, surfaceWidth, surfaceHeight),
          onSurfaceGone: (surfaceId: string): void =>
            this.clearLocalPreviewSurface(surfaceId)
        });
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.camera')).fontSize(38).fontColor([CALL_SUBTEXT]);
          Text(this.mediaStatus).fontSize(13).fontColor(CALL_SUBTEXT);
        }
      }

      Column() {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
              .fontSize(20).fontColor([Color.White]);
          }
          .width(42).height(42).padding(0)
          .backgroundColor('#A617222B')
          .border({ width: 1, color: '#42FFFFFF' })
          .enabled(!this.fullscreenTransitioning)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText($r('app.string.lv_exit_fullscreen'))
          .onClick((): void => this.toggleFullscreen());
          Button({ type: ButtonType.Circle }) {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.mic')).fontSize(21).fontColor([Color.White]);
              if (this.isMuted) {
                Text('╱').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White);
              }
            }
          }
          .width(42).height(42).backgroundColor(this.isMuted ? '#8A40505A' : '#C539D98A')
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(this.isMuted ? $r('app.string.lv_mic_on_action') : $r('app.string.lv_mic_off_action'))
          .onClick((): void => { this.toggleMuted(); });
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.camera')).fontSize(20).fontColor([
              this.localVideoActive ? CALL_BACKGROUND : Color.White
            ]);
          }
          .width(42).height(42)
          .backgroundColor(
            this.localVideoActive ? CALL_GREEN :
              (this.localVideoBusy ? '#A63D6256' : '#A640505A')
          )
          .enabled(!this.localVideoBusy)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(this.localVideoActive ? $r('app.string.lv_camera_off_action') : $r('app.string.lv_camera_on_action'))
          .onClick((): void => { this.toggleCamera(); });
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.computer')).fontSize(20).fontColor([
              this.screenShareActive ? CALL_BACKGROUND : Color.White
            ]);
          }
          .width(42).height(42)
          .backgroundColor(
            this.screenShareActive ? CALL_GREEN :
              (this.screenShareBusy ? '#A63D6256' : '#A640505A')
          )
          .enabled(!this.screenShareBusy)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(this.screenShareActive ? $r('app.string.lv_stop_screen') : $r('app.string.lv_start_screen'))
          .onClick((): void => { this.toggleScreenShare(); });
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.phone_fill')).fontSize(21).fontColor([Color.White]);
          }
          .width(42).height(42).backgroundColor('#D9D94B55')
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(this.canManageLive ? $r('app.string.lv_manage_or_leave') : $r('app.string.lv_leave'))
          .onClick((): void => this.leave());
          Blank();
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.person_2')).fontSize(17).fontColor([Color.White]);
              Text(str('lv_members_n', this.participants.length)).fontSize(13).fontColor(Color.White);
            }
          }
          .height(40).padding({ left: 12, right: 12 })
          .backgroundColor('#A617222B').borderRadius(20)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(plural('lv_view_members', this.participants.length, this.participants.length))
          .onClick((): void => { this.fullscreenPanelOpen = true; });
        }
        .width('100%');
        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 }).fill(this.headerDotColor())
            .opacity(this.headerPresentation().pulse && this.pulseExpanded ? 1 : 0.62);
          Text(this.headerPresentation().fullscreenText)
            .fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White);
        }
        .height(32).padding({ left: 10, right: 11 })
        .margin({ top: 8 })
        .backgroundColor('#A617222B').borderRadius(16)
        .alignSelf(ItemAlign.Start)
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
        }));
        Blank();
        if (this.participants.some(
          (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
        )) {
          Row({ space: 7 }) {
            Circle({ width: 7, height: 7 }).fill(CALL_GREEN)
              .opacity(this.pulseExpanded ? 1 : 0.52);
            Text(`${this.participants.find(
              (participant: GroupCallParticipantInfo): boolean => participant.isSpeaking
            )?.name ?? $r('app.string.ng_members')} 正在发言`)
              .fontSize(12).fontColor(Color.White).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .padding({ left: 11, right: 12, top: 7, bottom: 7 })
          .backgroundColor('#B314222B').borderRadius(16).alignSelf(ItemAlign.Start);
        }
      }
      .width('100%').height('100%')
      .padding({
        left: Math.max(14, this.cutoutLeftSafe + 8),
        right: Math.max(14, this.cutoutRightSafe + 8),
        top: Math.max(this.topSafe, this.cutoutTopSafe) + 10,
        bottom: this.bottomSafe + 12
      });

      if (this.fullscreenPanelOpen) {
        this.fullscreenParticipantDrawer();
      }

      if (this.fullscreenTransitioning) {
        Column({ space: 10 }) {
          LoadingProgress().width(30).height(30).color(Color.White);
          Text(this.fullscreenTransitionLabel)
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#A6000000')
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
        }));
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black);
  }

  build() {
    Stack() {
      if (this.isFullscreen) {
        this.fullscreenVideo();
      } else {
        Column() {
          this.header();
          Scroll() {
            Column() {
              Column() {
                this.mediaStage();
              }
              .width('100%')
              .opacity(this.videoAreaOpacity);
              if (this.participants.length > 0) {
                Column({ space: 1 }) {
                  ForEach(this.participants, (participant: GroupCallParticipantInfo) => {
                    this.participantRow(participant);
                  }, (participant: GroupCallParticipantInfo): string =>
                    `${participant.key}:${participant.revision}`)
                }
                .width('100%').margin({ top: 4 });
              }
            }
            .width('100%').padding({ left: 8, right: 8, bottom: 8 });
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off);
          if (this.shouldShowInteractionSection()) {
            this.interactionDock();
          }
          this.controls();
        }
        .width('100%').height('100%');
      }
      if (this.interactionDrawerOpen && !this.isFullscreen) {
        this.interactionDrawer();
      }
      if (this.fullscreenTransitioning && !this.isFullscreen) {
        Column({ space: 10 }) {
          LoadingProgress().width(30).height(30).color(Color.White);
          Text(this.fullscreenTransitionLabel)
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#B8000000')
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
        }));
      }
    }
    .width('100%').height('100%').backgroundColor(CALL_PANEL_ALT)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({
      top: this.isFullscreen ? 0 : this.topSafe,
      bottom: this.isFullscreen ? 0 : this.bottomSafe
    });
  }
}
