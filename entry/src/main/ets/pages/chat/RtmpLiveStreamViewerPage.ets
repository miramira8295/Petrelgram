import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { LiveStreamStore } from '../../store/LiveStreamStore';
import {
  GroupCallMessageEntry, GroupCallMessageStore
} from '../../store/GroupCallMessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import {
  GroupCallStreamInfo, LiveStreamState, emptyLiveStreamState
} from '../../tdkit/GroupCallTypes';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { endGroupCall, getGroupCall, leaveGroupCall } from '../../tdkit/GroupCallApi';
import { TgcallsGroupSession, TgcallsJoinResult } from '../../services/TgcallsGroupSession';
import { liveStreamBackgroundTask } from '../../services/LiveStreamBackgroundTask';
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
  LIVE_PHASE_AUDIO, LIVE_PHASE_NONE, LIVE_PHASE_RECOVERING, LIVE_PHASE_WAITING,
  LiveViewerHeaderPresentation, liveViewerHeaderPresentation
} from '../../util/liveViewerHeaderPresentation';
import {
  LiveViewerMediaPresentation, liveViewerMediaPresentation
} from '../../util/liveViewerMediaPresentation';
import {
  LiveInteractionEntry, LiveInteractionPresentation, isSupportedLiveChannelMessage,
  liveInteractionLooksLikeEmojiOnly, liveInteractionPresentation, mergeLiveInteractions,
  sameLiveInteraction
} from '../../util/liveInteractionPresentation';
import { LiveInteractionBubble } from './LiveInteractionBubble';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logI } from '../../util/log';

const LIVE_BACKGROUND: string = '#0A1117';
const LIVE_PANEL: string = '#101A23';
const LIVE_PANEL_ALT: string = '#16232D';
const LIVE_TEXT: string = '#F3F7F9';
const LIVE_SUBTEXT: string = '#8FA0AD';
const LIVE_RED: string = '#FF405C';
const LIVE_GREEN: string = '#39D98A';
const LIVE_ACCENT: string = '#4C9AFF';
const STREAM_RECONNECT_GRACE_MS: number = 8000;
const STREAM_STALL_MS: number = 15000;
const HEALTH_INTERVAL_MS: number = 4000;
const MAX_INTERACTIONS: number = 100;
const QUICK_REACTIONS: string[] = ['❤️', '🔥', '👏', '👍'];

interface RtmpSurfaceBinding {
  surfaceId: string;
  width: number;
  height: number;
}

function isQuickReaction(text: string): boolean {
  return QUICK_REACTIONS.indexOf(text.trim()) >= 0;
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

function groupCallInteraction(message: GroupCallMessageEntry, arrivalOrder: number): LiveInteractionEntry {
  return {
    key: `call:${message.id}`,
    revision: `${message.revision}:${message.senderName}:${message.senderAvatarPath}`,
    source: 'call',
    id: message.id,
    senderKey: message.senderKey,
    senderName: message.senderName,
    senderInitials: message.senderInitials,
    senderAvatarPath: message.senderAvatarPath,
    colorSeed: message.colorSeed,
    date: message.date,
    text: message.text,
    photoPath: '',
    emojiOnly: isQuickReaction(message.text) || liveInteractionLooksLikeEmojiOnly(message.text),
    isFromOwner: message.isFromOwner,
    sendState: 'none',
    arrivalOrder
  };
}

function chatInteraction(
  message: MessageEntry, chatId: number, arrivalOrder: number
): LiveInteractionEntry | null {
  if (!isSupportedLiveChannelMessage(message.contentType, message.isAnimation)) { return null; }
  const name = message.senderName !== '' ? message.senderName : (message.isOutgoing ? str('lv_me') : str('gn_channel'));
  let text = message.text.trim() !== '' ? message.text : message.placeholderLabel;
  if (text === '' && message.contentType === 'sticker') { text = str('sticker_tab'); }
  if (text === '' && message.contentType === 'video' && message.isAnimation) { text = 'GIF'; }
  const emojiOnly = isQuickReaction(text) || liveInteractionLooksLikeEmojiOnly(text);
  let photoPath = emojiOnly ? '' : message.photoPath;
  if (photoPath === '' && message.contentType === 'sticker' && message.stickerFormat === 'webp') {
    photoPath = message.stickerPath;
  }
  const senderKey = message.senderIsUser
    ? `messageSenderUser:${message.senderId}` : `messageSenderChat:${message.senderId}`;
  return {
    key: `chat:${message.id}`,
    revision: `${message.sendState}:${name}:${message.senderAvatarPath}:${photoPath}:${text}`,
    source: 'chat',
    id: message.id,
    senderKey,
    senderName: name,
    senderInitials: name !== '' ? name.substring(0, 1).toUpperCase() : '?',
    senderAvatarPath: message.senderAvatarPath,
    colorSeed: message.senderId !== 0 ? message.senderId : message.id,
    date: message.date,
    text,
    photoPath,
    emojiOnly,
    isFromOwner: !message.senderIsUser && message.senderId !== 0 && message.senderId === chatId,
    sendState: message.sendState,
    arrivalOrder
  };
}

@Component
struct RtmpVideoStage {
  @Prop presentation: LiveViewerMediaPresentation;
  @Prop channelTitle: string;
  @Prop hasVideo: boolean;
  @Prop recovering: boolean;
  @Prop fullscreen: boolean = false;
  @Prop fullscreenAvailable: boolean = false;
  @Prop pulseExpanded: boolean;
  onSurfaceReady: (surfaceId: string, width: number, height: number) => void = (): void => {};
  onSurfaceGone: (surfaceId: string) => void = (): void => {};
  onFullscreenToggle: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  private controller: XComponentController = new XComponentController();
  private surfaceId: string = '0';

  private refreshSurfaceSize(): void {
    if (this.surfaceId === '0') { return; }
    const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
    this.onSurfaceReady(
      this.surfaceId,
      Math.max(1, Math.round(rect.surfaceWidth)),
      Math.max(1, Math.round(rect.surfaceHeight))
    );
  }

  private releaseSurface(): void {
    const surfaceId = this.surfaceId;
    if (surfaceId === '0') { return; }
    this.surfaceId = '0';
    this.onSurfaceGone(surfaceId);
  }

  private badgeColor(): string {
    if (this.presentation.badgeTone === 'live') { return '#D9FF405C'; }
    if (this.presentation.badgeTone === 'danger') { return '#C8D94B55'; }
    if (this.presentation.badgeTone === 'waiting') { return '#C88D692D'; }
    if (this.presentation.badgeTone === 'audio') { return '#C839D98A'; }
    if (this.presentation.badgeTone === 'muted') { return '#B84A5964'; }
    return '#C8336FA8';
  }

  private badgeDotColor(): string {
    if (this.presentation.badgeTone === 'live' || this.presentation.badgeTone === 'danger') {
      return LIVE_RED;
    }
    if (this.presentation.badgeTone === 'audio') { return LIVE_GREEN; }
    if (this.presentation.badgeTone === 'waiting') { return '#E3A23A'; }
    if (this.presentation.badgeTone === 'muted') { return LIVE_SUBTEXT; }
    return LIVE_ACCENT;
  }

  private channelInitial(): string {
    const value = this.channelTitle.trim();
    return value !== '' ? value.substring(0, 1).toUpperCase() : 'L';
  }

  aboutToDisappear(): void {
    this.releaseSurface();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: 'rtmp_live_unified_video',
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .onLoad((): void => {
          this.surfaceId = this.controller.getXComponentSurfaceId();
          const rect: SurfaceRect = this.controller.getXComponentSurfaceRect();
          this.onSurfaceReady(
            this.surfaceId,
            Math.max(1, Math.round(rect.surfaceWidth)),
            Math.max(1, Math.round(rect.surfaceHeight))
          );
        })
        .onDestroy((): void => this.releaseSurface())
        .width('100%').height('100%');

      if (this.presentation.kind !== 'video') {
        Column()
          .width('100%').height('100%')
          .backgroundColor(this.hasVideo ? '#66101920' : '#F00B1218');
        Column({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: this.presentation.kind === 'audio' ? 68 : 52,
              height: this.presentation.kind === 'audio' ? 68 : 52 })
              .fill(this.presentation.kind === 'audio' ? LIVE_ACCENT : '#283B49')
              .opacity(this.presentation.pulse && this.pulseExpanded ? 0.62 : 1)
              .scale({
                x: this.presentation.pulse && this.pulseExpanded ? 1.06 : 0.96,
                y: this.presentation.pulse && this.pulseExpanded ? 1.06 : 0.96
              });
            if (this.presentation.kind === 'audio') {
              Text(this.channelInitial())
                .fontSize(23).fontWeight(FontWeight.Bold).fontColor(Color.White);
            } else if (this.presentation.showProgress) {
              LoadingProgress().width(27).height(27).color('#65A9FF');
            } else if (this.presentation.kind === 'error' ||
              this.presentation.kind === 'invalid') {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(25).fontColor([LIVE_RED]);
            } else {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor([Color.White]);
            }
          }
          .width(74).height(74);
          Text(this.presentation.kind === 'audio' && this.channelTitle !== ''
            ? this.channelTitle : this.presentation.title)
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.presentation.detail)
            .fontSize(12).fontColor(LIVE_SUBTEXT).textAlign(TextAlign.Center)
            .maxLines(2);
          if (this.presentation.retryable && this.presentation.actionText !== '') {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
              Text(this.presentation.actionText)
                .fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White);
            }
            .height(32).padding({ left: 11, right: 12 })
            .backgroundColor('#C83390EC').borderRadius(16)
            .accessibilityText(this.presentation.actionText)
            .onClick((): void => this.onRetry());
          }
        }
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
        }));
      }

      Column() {
        if (this.presentation.badgeText !== '') {
          Row({ space: 6 }) {
            Circle({ width: 7, height: 7 }).fill(this.badgeDotColor())
              .opacity(this.presentation.pulse && this.pulseExpanded ? 1 : 0.62)
              .scale({
                x: this.presentation.pulse && this.pulseExpanded ? 1.14 : 0.9,
                y: this.presentation.pulse && this.pulseExpanded ? 1.14 : 0.9
              });
            Text(this.presentation.badgeText)
              .fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
          .padding({ left: 9, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.badgeColor()).borderRadius(12)
          .alignSelf(ItemAlign.Start).margin({ left: 12, top: 12 });
        }
        Blank();
        if (this.presentation.kind === 'recovering') {
          Text(this.presentation.detail)
            .fontSize(12).fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor('#A61C2730').borderRadius(12)
            .alignSelf(ItemAlign.Center).margin({ bottom: 12 });
        }
      }
      .width('100%').height('100%');

      if (!this.fullscreen && this.fullscreenAvailable) {
        Column() {
          Blank();
          Row() {
            Blank();
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                .fontSize(20).fontColor([Color.White]);
            }
            .width(40).height(40).backgroundColor('#A617222B')
            .border({ width: 1, color: '#42FFFFFF' })
            .stateEffect(true).accessibilityText($r('app.string.lv_enter_fullscreen'))
            .onClick((): void => this.onFullscreenToggle());
          }.width('100%');
        }
        .width('100%').height('100%').padding({ right: 10, bottom: 10 });
      }
    }
    .width('100%').height(this.fullscreen ? '100%' : '220vp')
    .backgroundColor(Color.Black)
    .borderRadius(this.fullscreen ? 0 : 14)
    .clip(true)
    .onAreaChange((_old: Area, _area: Area): void => {
      setTimeout((): void => this.refreshSurfaceSize(), 30);
    });
  }
}

@Entry
@Component
struct RtmpLiveStreamViewerPage {
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
  @State recovering: boolean = false;
  @State hasVideo: boolean = false;
  @State messages: LiveInteractionEntry[] = [];
  @State draft: string = '';
  @State sending: boolean = false;
  @State pulseExpanded: boolean = false;
  @State isFullscreen: boolean = false;
  @State fullscreenTransitioning: boolean = false;
  @State fullscreenTransitionLabel: string = '';
  @State fullscreenPanelOpen: boolean = false;
  @State fullscreenMessagePreview: string = '';
  @State minimizeInProgress: boolean = false;
  @State canManageLive: boolean = false;
  @State endingLive: boolean = false;
  @State visualMediaReady: boolean = false;
  @State headerStateResolved: boolean = false;
  @State headerQueryFailed: boolean = false;
  @State recoveryUiVisible: boolean = false;
  @State retrySeconds: number = 0;
  @State connectionError: string = '';
  @State terminalError: boolean = false;
  @State hadVisualMedia: boolean = false;
  @State leaveDialogOpen: boolean = false;
  @State interactionAtBottom: boolean = true;
  @State interactionUnreadCount: number = 0;
  @State interactionSendError: string = '';
  @State channelCanSendMessages: boolean = false;
  @State channelHistoryState: string = 'ready';
  @State channelHistoryError: string = '';
  @State videoAspectRatio: number = 0;
  private groupCallId: number = 0;
  private chatId: number = 0;
  private initialTitle: string = '';
  private initialParticipantCount: number = 0;
  private pageActive: boolean = false;
  private hasJoinedOnce: boolean = false;
  private sessionSequence: number = 0;
  private recoveryInFlight: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private reconnectDueAt: number = 0;
  private recoveryUiTimer: number = -1;
  private recoveryCountdownTimer: number = -1;
  private healthTimer: number = -1;
  private pulseTimer: number = -1;
  private fullscreenPreviewTimer: number = -1;
  private groupCallRefreshInFlight: boolean = false;
  private joinedAt: number = 0;
  private lastPartAt: number = 0;
  private streamSignature: string = '';
  private surfaceBinding: RtmpSurfaceBinding | null = null;
  private liveStore: LiveStreamStore | null = null;
  private messageStore: GroupCallMessageStore | null = null;
  private channelMessageStore: MessageStore | null = null;
  private groupCallMessages: GroupCallMessageEntry[] = [];
  private channelMessages: MessageEntry[] = [];
  private session: TgcallsGroupSession | null = null;
  private offLive: (() => void) | null = null;
  private offMessages: (() => void) | null = null;
  private offMessageError: (() => void) | null = null;
  private offChannelMessages: (() => void) | null = null;
  private commentScroller: Scroller = new Scroller();
  private leavingForFloating: boolean = false;
  private interactionTouchActive: boolean = false;
  private interactionSnapshotReady: boolean = false;
  private interactionArrivalCounter: number = 0;
  private interactionArrivalOrders: Map<string, number> = new Map();
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
    this.interactionUnreadCount = 0;
    this.interactionSnapshotReady = false;
    const params = router.getParams() as Record<string, Object> | undefined;
    this.groupCallId = params !== undefined
      ? ((params['groupCallId'] as number | undefined) ?? 0) : 0;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    this.initialTitle = params !== undefined
      ? ((params['initialTitle'] as string | undefined) ?? '') : '';
    this.initialParticipantCount = params !== undefined
      ? ((params['initialParticipantCount'] as number | undefined) ?? 0) : 0;
    if (this.groupCallId <= 0) {
      this.setMediaStatus(str('lv_invalid_room'));
      return;
    }
    const client = getTdClient();
    this.liveStore = new LiveStreamStore(client, this.groupCallId);
    this.offLive = this.liveStore.subscribe(
      (state: LiveStreamState): void => this.onLiveState(state)
    );
    this.messageStore = new GroupCallMessageStore(client, getUserStore(), this.groupCallId);
    this.offMessages = this.messageStore.subscribe(
      (messages: GroupCallMessageEntry[]): void => this.onMessages(messages)
    );
    this.offMessageError = this.messageStore.subscribeError((message: string): void => {
      this.interactionSendError = message;
    });
    this.messageStore.open();
    if (this.chatId !== 0) {
      this.channelHistoryState = 'loading';
      this.channelMessageStore = new MessageStore(
        client, getUserStore(), this.chatId, 0, MAX_INTERACTIONS
      );
      this.offChannelMessages = this.channelMessageStore.subscribe(
        (messages: MessageEntry[]): void => this.onChannelMessages(messages)
      );
      this.channelMessageStore.open(undefined, true);
      this.resolveChannelSendPermission();
    }
    this.startPulse();
    this.startHealthMonitor();
    const handoff = floatingLiveWindow.takeSeamlessSession(this.groupCallId, true);
    if (handoff !== null) { this.adoptSeamlessSession(handoff); }
    liveStreamBackgroundTask.start(getContext(this) as common.UIAbilityContext, false);
    if (handoff === null) { this.replaceSession('首次加入'); } // i18n-exempt: diagnostic trace tag, console only
    this.refreshGroupCall('首次查询'); // i18n-exempt: diagnostic trace tag, console only
  }

  private adoptSeamlessSession(handoff: FloatingLiveSessionHandoff): void {
    const session = handoff.session;
    const sequence = ++this.sessionSequence;
    this.session = session;
    this.liveStore?.setStreams(handoff.liveState.streams);
    this.state = handoff.liveState;
    this.hasJoinedOnce = handoff.hasJoinedOnce;
    this.recoveryInFlight = false;
    this.reconnectAttempt = 0;
    this.headerStateResolved = true;
    this.headerQueryFailed = false;
    this.hasVideo = uniqueVideoChannelIds(handoff.liveState.streams).length > 0;
    this.visualMediaReady = handoff.visualReady;
    this.hadVisualMedia = handoff.visualReady;
    this.videoAspectRatio = handoff.videoAspectRatio;
    this.streamSignature = uniqueVideoChannelIds(handoff.liveState.streams).join(',');
    this.joinedAt = Date.now();
    this.lastPartAt = handoff.visualReady ? Date.now() : 0;
    this.recovering = !handoff.mediaConnected;
    this.recoveryUiVisible = !handoff.mediaConnected;
    this.connectionError = '';
    this.terminalError = false;
    session.setListeners(
      (connected: boolean): void => this.onNetworkState(session, connected),
      (): void => {},
      (streams: GroupCallStreamInfo[], unified: boolean): void => {
        if (this.isCurrent(session, sequence) && unified) {
          this.onBroadcastStreams(session, streams);
        }
      },
      (received: boolean): void => {
        if (this.isCurrent(session, sequence)) { this.onBroadcastActivity(received); }
      },
      (): void => {},
      (endpointId: string, width: number, height: number): void =>
        this.onVideoGeometry(session, endpointId, width, height)
    );
    if (this.hasVideo) {
      session.setVideoChannel('unified', 0, `SIM=${this.streamSignature}`);
    }
    session.resumeMedia();
    if (this.recovering) {
      this.setMediaStatus(str('lv_resuming'), LIVE_PHASE_RECOVERING);
    } else if (this.hasVideo) {
      this.setMediaStatus(str('lfw_playing'));
    } else {
      this.setMediaStatus(str('lfw_audio_playing'), LIVE_PHASE_AUDIO);
    }
  }

  onPageShow(): void {
    if (this.pageActive && this.groupCallId > 0) {
      if (this.isFullscreen) {
        setLiveStreamFullscreen(
          getContext(this) as common.UIAbilityContext, true, this.videoAspectRatio
        );
      }
      this.resumeAfterForeground();
    }
  }

  private onAppForegroundEpoch(): void {
    if (this.pageActive && this.groupCallId > 0) { this.resumeAfterForeground(); }
  }

  private onLiveState(next: LiveStreamState): void {
    this.state = next;
    if (next.title !== '' || next.isActive || next.error !== '') {
      this.headerStateResolved = true;
      this.headerQueryFailed = false;
    }
    if (next.needRejoin) {
      this.recovering = true;
      this.scheduleRecovery(0, 'TDLib 要求重新加入'); // i18n-exempt: diagnostic trace tag, console only
    } else if (this.hasJoinedOnce && next.isActive && !next.isJoined) {
      this.recovering = true;
      this.scheduleRecovery(500, '直播成员状态已断开'); // i18n-exempt: diagnostic trace tag, console only
    }
    if (this.hasJoinedOnce && !next.isActive) {
      this.setMediaStatus(str('lfw_ended'));
      this.recovering = false;
      this.clearRecoveryTimer();
      this.clearRecoveryUi();
      setLiveStreamKeepScreenOn(getContext(this) as common.UIAbilityContext, false);
    }
  }

  private onMessages(next: GroupCallMessageEntry[]): void {
    this.groupCallMessages = next;
    this.rebuildInteractions();
  }

  private onChannelMessages(next: MessageEntry[]): void {
    const previousState = this.channelHistoryState;
    const store = this.channelMessageStore;
    if (store !== null) {
      this.channelHistoryState = store.getInitialHistoryState();
      this.channelHistoryError = store.getInitialHistoryError();
    }
    this.channelMessages = next.filter(
      (message: MessageEntry): boolean =>
        isSupportedLiveChannelMessage(message.contentType, message.isAnimation)
    ).slice(-MAX_INTERACTIONS);
    this.rebuildInteractions(previousState === 'loading' && this.channelHistoryState !== 'loading');
  }

  private interactionArrival(key: string): number {
    const known = this.interactionArrivalOrders.get(key);
    if (known !== undefined) { return known; }
    this.interactionArrivalCounter += 1;
    this.interactionArrivalOrders.set(key, this.interactionArrivalCounter);
    return this.interactionArrivalCounter;
  }

  private rebuildInteractions(suppressNew: boolean = false): void {
    const previous = this.messages;
    const firstPopulatedSnapshot = previous.length === 0;
    const wasAtBottom = this.interactionAtBottom;
    const combined: LiveInteractionEntry[] = [];
    for (const message of this.channelMessages) {
      const key = `chat:${message.id}`;
      const entry = chatInteraction(message, this.chatId, this.interactionArrival(key));
      if (entry !== null) { combined.push(entry); }
    }
    for (const message of this.groupCallMessages) {
      const key = `call:${message.id}`;
      combined.push(groupCallInteraction(message, this.interactionArrival(key)));
    }
    const next = mergeLiveInteractions(combined, MAX_INTERACTIONS);
    const newEntries = !suppressNew && this.interactionSnapshotReady
      ? next.filter((candidate: LiveInteractionEntry): boolean =>
        !previous.some((entry: LiveInteractionEntry): boolean => sameLiveInteraction(entry, candidate)))
      : [];
    this.messages = next;
    this.interactionSnapshotReady = true;
    if (firstPopulatedSnapshot && next.length > 0 &&
      (!this.isFullscreen || this.fullscreenPanelOpen)) {
      this.interactionAtBottom = true;
      this.interactionUnreadCount = 0;
      // The List is laid out after the state assignment. A second pass covers
      // history arriving in the same frame as the live-message snapshot.
      setTimeout((): void => this.commentScroller.scrollEdge(Edge.Bottom), 20);
      setTimeout((): void => this.commentScroller.scrollEdge(Edge.Bottom), 90);
    }
    if (newEntries.length > 0) {
      const interactionVisible = !this.isFullscreen || this.fullscreenPanelOpen;
      if (interactionVisible && wasAtBottom && !this.interactionTouchActive) {
        this.interactionAtBottom = true;
        setTimeout((): void => this.commentScroller.scrollEdge(Edge.Bottom), 40);
      } else {
        this.interactionAtBottom = false;
        this.interactionUnreadCount += newEntries.length;
      }
      if (this.isFullscreen && !this.fullscreenPanelOpen) {
        const latest = newEntries[newEntries.length - 1];
        this.fullscreenMessagePreview = `${latest.senderName}：${latest.text}`;
        if (this.fullscreenPreviewTimer !== -1) { clearTimeout(this.fullscreenPreviewTimer); }
        this.fullscreenPreviewTimer = setTimeout((): void => {
          this.fullscreenPreviewTimer = -1;
          this.fullscreenMessagePreview = '';
        }, 3200);
      }
    }
  }

  private refreshInteractionAtBottom(): void {
    const next = this.messages.length === 0 || this.commentScroller.isAtEnd();
    if (this.interactionAtBottom !== next) { this.interactionAtBottom = next; }
    if (next && this.interactionUnreadCount !== 0) { this.interactionUnreadCount = 0; }
  }

  private scrollToInteractionTail(): void {
    this.interactionAtBottom = true;
    this.interactionUnreadCount = 0;
    this.commentScroller.scrollEdge(Edge.Bottom);
  }

  private retryChannelHistory(): void {
    const store = this.channelMessageStore;
    if (store === null || store.getInitialHistoryState() !== 'error') { return; }
    this.channelHistoryState = 'loading';
    this.channelHistoryError = '';
    store.retryInitialHistory();
  }

  private permissionAllowsText(permissions: TdObject | undefined, fallback: boolean): boolean {
    if (permissions === undefined) { return fallback; }
    const modern = permissions['can_send_basic_messages'] as boolean | undefined;
    if (modern !== undefined) { return modern; }
    const legacy = permissions['can_send_messages'] as boolean | undefined;
    return legacy !== undefined ? legacy : fallback;
  }

  private memberStatusAllowsChannelSend(
    status: TdObject | undefined, isChannel: boolean, defaultPermission: boolean
  ): boolean {
    const type = (status?.['@type'] as string | undefined) ?? '';
    if (type === 'chatMemberStatusCreator') { return true; }
    if (type === 'chatMemberStatusAdministrator') {
      if (!isChannel) { return true; }
      const rights = status?.['rights'] as TdObject | undefined;
      return (rights?.['can_post_messages'] as boolean | undefined) ?? false;
    }
    if (type === 'chatMemberStatusMember') {
      return !isChannel && defaultPermission;
    }
    if (type === 'chatMemberStatusRestricted') {
      const isMember = (status?.['is_member'] as boolean | undefined) ?? false;
      const restrictedPermissions = status?.['permissions'] as TdObject | undefined;
      return !isChannel && isMember &&
        this.permissionAllowsText(restrictedPermissions, defaultPermission);
    }
    return false;
  }

  private resolveChannelSendPermission(): void {
    const chatId = this.chatId;
    if (chatId === 0) { return; }
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = chatId;
    getTdClient().send(request).then((chat: TdObject): void => {
      if (!this.pageActive || this.chatId !== chatId) { return; }
      const type = chat['type'] as TdObject | undefined;
      const typeName = (type?.['@type'] as string | undefined) ?? '';
      const defaultPermission = this.permissionAllowsText(
        chat['permissions'] as TdObject | undefined, true
      );
      if (typeName === 'chatTypeSupergroup') {
        const supergroupId = (type?.['supergroup_id'] as number | undefined) ?? 0;
        const isChannel = (type?.['is_channel'] as boolean | undefined) ?? false;
        if (supergroupId === 0) { return; }
        const groupRequest: TdRequest = { '@type': 'getSupergroup' };
        groupRequest['supergroup_id'] = supergroupId;
        getTdClient().send(groupRequest).then((group: TdObject): void => {
          if (!this.pageActive || this.chatId !== chatId) { return; }
          this.channelCanSendMessages = this.memberStatusAllowsChannelSend(
            group['status'] as TdObject | undefined, isChannel, defaultPermission
          );
        }).catch((error: TdError): void => {
          logE(`RtmpLiveStream getSupergroup permission failed: ${error.message}`);
        });
        return;
      }
      if (typeName === 'chatTypeBasicGroup') {
        const basicGroupId = (type?.['basic_group_id'] as number | undefined) ?? 0;
        if (basicGroupId === 0) { return; }
        const groupRequest: TdRequest = { '@type': 'getBasicGroup' };
        groupRequest['basic_group_id'] = basicGroupId;
        getTdClient().send(groupRequest).then((group: TdObject): void => {
          if (!this.pageActive || this.chatId !== chatId) { return; }
          this.channelCanSendMessages = this.memberStatusAllowsChannelSend(
            group['status'] as TdObject | undefined, false, defaultPermission
          );
        }).catch((error: TdError): void => {
          logE(`RtmpLiveStream getBasicGroup permission failed: ${error.message}`);
        });
        return;
      }
      this.channelCanSendMessages = defaultPermission;
    }).catch((error: TdError): void => {
      logE(`RtmpLiveStream getChat permission failed: ${error.message}`);
    });
  }

  private replaceSession(reason: string): void {
    if (!this.pageActive || this.groupCallId <= 0 || this.terminalError) { return; }
    if (this.recoveryInFlight) {
      this.scheduleRecovery(750, reason);
      return;
    }
    this.recoveryInFlight = true;
    this.clearRecoveryTimer();
    this.recovering = this.hasJoinedOnce;
    this.connectionError = '';
    if (this.hasJoinedOnce) { this.showRecoveryUi(0); }
    if (this.hasJoinedOnce) {
      this.setMediaStatus(str('lv_recovering'), LIVE_PHASE_RECOVERING);
    } else {
      this.setMediaStatus(str('lv_joining'));
    }
    const sequence = ++this.sessionSequence;
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
    }
    this.session = null;
    this.hadVisualMedia = this.hadVisualMedia || this.visualMediaReady;
    this.streamSignature = '';
    this.hasVideo = false;
    this.visualMediaReady = false;
    this.lastPartAt = 0;

    const client = getTdClient();
    const session = new TgcallsGroupSession(
      (connected: boolean): void => this.onNetworkState(session, connected),
      (): void => {},
      (streams: GroupCallStreamInfo[], unified: boolean): void => {
        if (this.isCurrent(session, sequence) && unified) {
          this.onBroadcastStreams(session, streams);
        }
      },
      (received: boolean): void => {
        if (this.isCurrent(session, sequence)) { this.onBroadcastActivity(received); }
      },
      (): void => {},
      (endpointId: string, width: number, height: number): void =>
        this.onVideoGeometry(session, endpointId, width, height)
    );
    this.session = session;
    logI(`[RtmpLiveStream] session ${sequence} start reason=${reason}`);
    session.join(client, this.groupCallId, true).then((result: TgcallsJoinResult): void => {
      if (!this.isCurrent(session, sequence)) { return; }
      if (!result.isBroadcast || !result.isUnifiedBroadcast) {
        this.setMediaStatus(str('lv_mode_changed'));
        this.recovering = false;
        this.terminalError = true;
        this.connectionError = str('lv_type_changed');
        this.clearRecoveryTimer();
        this.clearRecoveryUi();
        this.state = {
          title: this.state.title, isActive: this.state.isActive,
          isRtmpStream: this.state.isRtmpStream, isJoined: false,
          needRejoin: false, canSendMessages: this.state.canSendMessages,
          areMessagesAllowed: this.state.areMessagesAllowed,
          participantCount: this.state.participantCount, streams: this.state.streams,
          error: str('lv_type_changed')
        };
        session.stop();
        this.session = null;
        return;
      }
      this.hasJoinedOnce = true;
      this.terminalError = false;
      this.connectionError = '';
      this.reconnectAttempt = 0;
      this.joinedAt = Date.now();
      this.lastPartAt = Date.now();
      const joinedState = this.state;
      this.liveStore?.setStreams(result.streams);
      this.state = {
        title: joinedState.title,
        isActive: joinedState.isActive,
        isRtmpStream: true,
        isJoined: true,
        needRejoin: false,
        canSendMessages: joinedState.canSendMessages,
        areMessagesAllowed: joinedState.areMessagesAllowed,
        participantCount: joinedState.participantCount,
        streams: result.streams,
        error: ''
      };
      this.onBroadcastStreams(session, result.streams);
      this.restoreSurface();
      session.resumeMedia();
      this.recovering = false;
      this.clearRecoveryUi();
      if (result.streams.length > 0) {
        this.setMediaStatus(str('lfw_playing'));
      } else {
        this.setMediaStatus(str('lv_waiting_host_stream'), LIVE_PHASE_WAITING);
      }
      this.refreshGroupCall('加入完成'); // i18n-exempt: diagnostic trace tag, console only
    }).catch((caught: Error): void => {
      if (!this.isCurrent(session, sequence)) { return; }
      session.stop();
      this.session = null;
      this.recovering = true;
      this.setMediaStatus(str('lv_reconnecting'), LIVE_PHASE_RECOVERING);
      this.connectionError = caught.message;
      this.state = {
        title: this.state.title, isActive: this.state.isActive,
        isRtmpStream: true, isJoined: false, needRejoin: this.state.needRejoin,
        canSendMessages: this.state.canSendMessages,
        areMessagesAllowed: this.state.areMessagesAllowed,
        participantCount: this.state.participantCount, streams: this.state.streams,
        error: caught.message
      };
      this.showRecoveryUi(0);
      this.reconnectAttempt += 1;
      const delay = Math.min(30000, 1000 * Math.pow(2, Math.min(this.reconnectAttempt - 1, 5)));
      this.scheduleRecovery(delay, str('lv_join_failed', caught.message));
    }).finally((): void => {
      if (sequence === this.sessionSequence) { this.recoveryInFlight = false; }
    });
  }

  private isCurrent(session: TgcallsGroupSession, sequence: number): boolean {
    return this.pageActive && this.session === session && this.sessionSequence === sequence;
  }

  private onBroadcastStreams(session: TgcallsGroupSession, streams: GroupCallStreamInfo[]): void {
    if (this.session !== session) { return; }
    const streamState = this.state;
    this.liveStore?.setStreams(streams);
    this.state = {
      title: streamState.title,
      isActive: streamState.isActive,
      isRtmpStream: true,
      isJoined: true,
      needRejoin: false,
      canSendMessages: streamState.canSendMessages,
      areMessagesAllowed: streamState.areMessagesAllowed,
      participantCount: streamState.participantCount,
      streams,
      error: streamState.error
    };
    const videoChannelIds = uniqueVideoChannelIds(streams);
    this.hasVideo = videoChannelIds.length > 0;
    if (!this.hasVideo) {
      this.streamSignature = '';
      this.visualMediaReady = false;
      if (!this.recovering) { this.setMediaStatus(str('lv_waiting_host_stream'), LIVE_PHASE_WAITING); }
      return;
    }
    const signature = videoChannelIds.join(',');
    if (signature === this.streamSignature) { return; }
    this.streamSignature = signature;
    this.visualMediaReady = false;
    const groups = `SIM=${videoChannelIds.join(',')}`;
    session.setVideoChannel('unified', 0, groups);
    if (this.recovering) {
      this.setMediaStatus(str('lv_recovering'), LIVE_PHASE_RECOVERING);
    } else {
      this.setMediaStatus(str('lfw_playing'));
    }
  }

  private onBroadcastActivity(received: boolean): void {
    if (received) {
      this.lastPartAt = Date.now();
      if (this.hasVideo) {
        this.visualMediaReady = true;
        this.hadVisualMedia = true;
      }
      if (this.recovering) {
        this.recovering = false;
        this.clearRecoveryTimer();
        this.clearRecoveryUi();
        this.connectionError = '';
      }
      if (this.hasVideo) {
        this.setMediaStatus(str('lfw_playing'));
      } else {
        this.setMediaStatus(str('lfw_audio_playing'), LIVE_PHASE_AUDIO);
      }
      return;
    }
    if (this.state.streams.length > 0 && Date.now() - this.lastPartAt >= STREAM_STALL_MS) {
      this.recovering = true;
      this.setMediaStatus(str('lv_buffering'), LIVE_PHASE_RECOVERING);
      this.showRecoveryUi(0);
    }
  }

  private onNetworkState(session: TgcallsGroupSession, connected: boolean): void {
    if (this.session !== session) { return; }
    if (connected) {
      session.resumeMedia();
      this.restoreSurface();
      this.applyCurrentVideoChannel(true);
      return;
    }
    if (this.hasJoinedOnce) {
      this.recovering = true;
      this.setMediaStatus(str('lv_resuming'), LIVE_PHASE_RECOVERING);
      this.showRecoveryUi(700);
      this.scheduleRecovery(STREAM_RECONNECT_GRACE_MS, '媒体网络断开'); // i18n-exempt: diagnostic trace tag, console only
    }
  }

  private applyCurrentVideoChannel(force: boolean): void {
    const session = this.session;
    if (session === null) { return; }
    const streams = this.state.streams;
    const previous = this.streamSignature;
    if (force) { this.streamSignature = ''; }
    this.onBroadcastStreams(session, streams);
    if (!force) { this.streamSignature = this.streamSignature !== '' ? this.streamSignature : previous; }
  }

  private setSurface(surfaceId: string, width: number, height: number): void {
    this.surfaceBinding = { surfaceId, width, height };
    this.session?.setVideoSurface('unified', surfaceId, width, height);
  }

  private clearSurface(surfaceId: string): void {
    if (this.surfaceBinding === null || this.surfaceBinding.surfaceId !== surfaceId) { return; }
    this.surfaceBinding = null;
    this.session?.setVideoSurface('unified', '0');
  }

  private onVideoGeometry(
    session: TgcallsGroupSession, _endpointId: string, width: number, height: number
  ): void {
    if (!this.pageActive || this.session !== session || width <= 0 || height <= 0) { return; }
    const aspectRatio = width / height;
    if (Math.abs(this.videoAspectRatio - aspectRatio) < 0.01) { return; }
    this.videoAspectRatio = aspectRatio;
    if (this.isFullscreen) {
      setLiveStreamFullscreen(
        getContext(this) as common.UIAbilityContext, true, this.videoAspectRatio
      );
    }
  }

  private restoreSurface(): void {
    const binding = this.surfaceBinding;
    if (binding !== null) {
      this.session?.setVideoSurface('unified', binding.surfaceId, binding.width, binding.height);
    }
  }

  private scheduleRecovery(delayMs: number, reason: string): void {
    if (!this.pageActive || this.groupCallId <= 0 || this.terminalError ||
      (!this.state.isActive && this.hasJoinedOnce)) { return; }
    const dueAt = Date.now() + Math.max(0, delayMs);
    if (this.reconnectTimer !== -1 && this.reconnectDueAt <= dueAt) { return; }
    this.clearRecoveryTimer();
    this.reconnectDueAt = dueAt;
    this.startRecoveryCountdown();
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      this.reconnectDueAt = 0;
      this.stopRecoveryCountdown();
      if (!this.pageActive || this.terminalError ||
        (!this.state.isActive && this.hasJoinedOnce)) { return; }
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
      if (this.pageActive && this.recovering && !this.terminalError &&
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
      if (!this.hasJoinedOnce || this.state.streams.length === 0) { return; }
      const reference = this.lastPartAt > 0 ? this.lastPartAt : this.joinedAt;
      if (reference > 0 && Date.now() - reference >= STREAM_STALL_MS) {
        this.recovering = true;
        this.setMediaStatus(str('lv_resyncing'), LIVE_PHASE_RECOVERING);
        this.showRecoveryUi(0);
        this.session?.resumeMedia();
        this.restoreSurface();
        this.applyCurrentVideoChannel(true);
        this.scheduleRecovery(3000, '直播分片长时间无数据'); // i18n-exempt: diagnostic trace tag, console only
      }
    }, HEALTH_INTERVAL_MS);
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
      const next: LiveStreamState = {
        title: (groupCall['title'] as string | undefined) ?? this.state.title,
        isActive: (groupCall['is_active'] as boolean | undefined) ?? this.state.isActive,
        isRtmpStream: (groupCall['is_rtmp_stream'] as boolean | undefined) ?? true,
        isJoined: (groupCall['is_joined'] as boolean | undefined) ?? this.state.isJoined,
        needRejoin: (groupCall['need_rejoin'] as boolean | undefined) ?? this.state.needRejoin,
        canSendMessages: (groupCall['can_send_messages'] as boolean | undefined) ?? false,
        areMessagesAllowed: (groupCall['are_messages_allowed'] as boolean | undefined) ?? false,
        participantCount: (groupCall['participant_count'] as number | undefined) ??
          this.state.participantCount,
        streams: this.state.streams,
        error: this.state.error
      };
      if (this.liveStore !== null) {
        this.liveStore.applyGroupCall(groupCall);
      } else {
        this.onLiveState(next);
      }
      logI(
        `[RtmpLiveStream] health reason=${reason} active=${next.isActive} joined=${next.isJoined} ` +
        `needRejoin=${next.needRejoin} admin=${this.canManageLive} ` +
        `canBeManaged=${canBeManaged} isOwned=${isOwned} ` +
        `lastPartAgo=${this.lastPartAt > 0 ? Date.now() - this.lastPartAt : -1}`
      );
    } catch (caught) {
      const error = caught as Error;
      if (!this.hasJoinedOnce) { this.headerQueryFailed = true; }
      logE(`[RtmpLiveStream] health check failed reason=${reason}: ${error.message}`);
    } finally {
      this.groupCallRefreshInFlight = false;
    }
  }

  private resumeAfterForeground(): void {
    liveStreamBackgroundTask.start(getContext(this) as common.UIAbilityContext, false);
    this.session?.resumeMedia();
    this.restoreSurface();
    this.applyCurrentVideoChannel(true);
    this.refreshGroupCall('回到前台'); // i18n-exempt: diagnostic trace tag, console only
    if (this.hasJoinedOnce && this.state.streams.length > 0 &&
      Date.now() - this.lastPartAt >= STREAM_STALL_MS) {
      this.recovering = true;
      this.showRecoveryUi(0);
      this.scheduleRecovery(2500, '前台恢复后直播流未恢复'); // i18n-exempt: diagnostic trace tag, console only
    }
  }

  private startPulse(): void {
    this.pulseTimer = setInterval((): void => {
      if (!powerFeatureEnabled(KEY_POWER_CALL_ANIMATIONS)) {
        this.pulseExpanded = false;
        return;
      }
      this.pulseExpanded = !this.pulseExpanded;
    }, 780);
  }

  private sendMessage(text?: string): void {
    if (this.sending || !this.interactionPresentation().composerEnabled) { return; }
    const value = (text ?? this.draft).trim();
    if (value === '') { return; }
    this.lastFailedInteractionText = value;
    this.interactionSendError = '';
    this.sending = true;
    this.sendInteractionMessage(value).then((): void => {
      if (text === undefined) { this.draft = ''; }
    }).catch((caught: Error): void => {
      this.interactionSendError = str('lv_send_failed', caught.message);
    }).finally((): void => {
      this.sending = false;
    });
  }

  private sendInteractionMessage(value: string): Promise<void> {
    const callStore = this.messageStore;
    const channelStore = this.channelMessageStore;
    const callCanSend = this.state.areMessagesAllowed && this.state.canSendMessages &&
      callStore !== null;
    if (callCanSend && callStore !== null) {
      return callStore.send(value).catch((error: Error): Promise<void> => {
        if (this.channelCanSendMessages && channelStore !== null) {
          return channelStore.sendAsync(value);
        }
        return Promise.reject(error);
      });
    }
    if (this.channelCanSendMessages && channelStore !== null) {
      return channelStore.sendAsync(value);
    }
    return Promise.reject(new Error(str('lv_no_message_channel')));
  }

  private retryInteractionSend(): void {
    if (this.lastFailedInteractionText === '' || this.sending) { return; }
    this.sendMessage(this.lastFailedInteractionText);
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
    const session = this.session;
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
      isRtmp: true,
      title: this.displayTitle(),
      participantCount: this.displayParticipantCount(),
      primarySource: null
    };
    const handoff: FloatingLiveSessionHandoff = {
      descriptor,
      session,
      liveState: this.state,
      isMuted: true,
      mediaConnected: !this.recovering,
      hasJoinedOnce: this.hasJoinedOnce,
      visualReady: this.visualMediaReady,
      videoAspectRatio: this.videoAspectRatio,
      localVideoMode: 0,
      localVideoActive: false,
      desiredLocalVideoMode: 0,
      screenShareActive: false,
      screenShareDesired: false
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
    this.session = null;
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
    this.leavingForFloating = true;
    router.back();
  }

  private toggleFullscreen(): void {
    if (this.fullscreenTransitioning) { return; }
    const next = !this.isFullscreen;
    if (next && !this.canEnterFullscreen()) { return; }
    this.fullscreenPanelOpen = false;
    this.fullscreenMessagePreview = '';
    this.fullscreenTransitioning = true;
    this.fullscreenTransitionLabel = next ? str('lv_entering_fullscreen') : str('lv_exiting_fullscreen');
    this.isFullscreen = next;
    setLiveStreamFullscreen(
      getContext(this) as common.UIAbilityContext, next,
      next ? this.videoAspectRatio : 0
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

  private canEnterFullscreen(): boolean {
    return this.groupCallId > 0 && this.displayHasVideo() &&
      (this.visualMediaReady || (this.hasJoinedOnce && this.recovering));
  }

  private displayHasVideo(): boolean {
    return this.hasVideo || (this.recovering && this.hadVisualMedia);
  }

  private displayTitle(): string {
    if (this.state.title !== '') { return this.state.title; }
    if (this.initialTitle !== '') { return this.initialTitle; }
    return this.groupCallId > 0 ? str('lv_channel_stream') : str('lv_cannot_open');
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
      recovering: this.recoveryUiVisible || this.recoveryInFlight,
      ending: this.endingLive,
      terminalError: this.terminalError,
      reconnectAttempt: this.reconnectAttempt,
      retrySeconds: this.retrySeconds,
      canMinimize: this.session !== null && !this.terminalError,
      participantCount: this.displayParticipantCount(),
      mediaPhase: this.mediaPhase
    });
  }

  private mediaPresentation(): LiveViewerMediaPresentation {
    return liveViewerMediaPresentation({
      mode: 'rtmp',
      valid: this.groupCallId > 0,
      resolved: this.headerStateResolved,
      active: this.state.isActive,
      joined: this.state.isJoined,
      joinedOnce: this.hasJoinedOnce,
      recovering: this.recoveryUiVisible || this.recoveryInFlight,
      ending: this.endingLive,
      terminalError: this.terminalError,
      reconnectAttempt: this.reconnectAttempt,
      retrySeconds: this.retrySeconds,
      retryable: !this.recoveryInFlight && !this.terminalError,
      hasVideo: this.displayHasVideo(),
      visualReady: this.visualMediaReady || (this.recovering && this.hadVisualMedia),
      participantCount: this.displayParticipantCount(),
      mediaPhase: this.mediaPhase,
      error: this.connectionError !== '' ? this.connectionError : this.state.error
    });
  }

  private interactionPresentation(): LiveInteractionPresentation {
    const callCanSend = this.state.areMessagesAllowed && this.state.canSendMessages;
    return liveInteractionPresentation({
      valid: this.groupCallId > 0,
      resolved: this.headerStateResolved,
      active: this.state.isActive,
      joined: this.state.isJoined,
      joinedOnce: this.hasJoinedOnce,
      recovering: this.recovering,
      messagesAllowed: this.state.areMessagesAllowed || this.channelCanSendMessages,
      canSendMessages: callCanSend || this.channelCanSendMessages,
      messageCount: this.messages.length,
      channelAttached: this.channelMessageStore !== null,
      channelHistoryState: this.channelHistoryState,
      channelHistoryError: this.channelHistoryError
    });
  }

  private interactionStatusColor(): string {
    const tone = this.interactionPresentation().statusTone;
    if (tone === 'live') { return LIVE_GREEN; }
    if (tone === 'accent') { return LIVE_ACCENT; }
    return LIVE_SUBTEXT;
  }

  private interactionStatusBackground(): string {
    const tone = this.interactionPresentation().statusTone;
    if (tone === 'live') { return '#2539D98A'; }
    if (tone === 'accent') { return '#263390EC'; }
    return '#244A5964';
  }

  private headerDotColor(): string {
    const kind = this.headerPresentation().kind;
    if (kind === 'error' || kind === 'ending') { return LIVE_RED; }
    if (kind === 'ended' || kind === 'invalid') { return LIVE_SUBTEXT; }
    if (kind === 'connecting' || kind === 'joining' || kind === 'recovering') { return LIVE_ACCENT; }
    if (kind === 'waiting') { return '#E3A23A'; }
    if (kind === 'audio') { return LIVE_GREEN; }
    return LIVE_RED;
  }

  private fullscreenStatusBackground(): string {
    const kind = this.headerPresentation().kind;
    if (kind === 'live') { return '#C9FF405C'; }
    if (kind === 'error' || kind === 'ending') { return '#B8D94B55'; }
    if (kind === 'ended' || kind === 'invalid') { return '#B84A5964'; }
    if (kind === 'waiting') { return '#B88D692D'; }
    return '#B8336FA8';
  }

  private retryLiveConnection(): void {
    if (!this.headerPresentation().retryable && !this.mediaPresentation().retryable) { return; }
    const queryOnly = this.headerQueryFailed && this.session !== null &&
      this.connectionError === '' && !this.recoveryUiVisible;
    this.headerQueryFailed = false;
    this.connectionError = '';
    this.refreshGroupCall('顶部状态手动重试'); // i18n-exempt: diagnostic trace tag, console only
    if (queryOnly || this.recoveryInFlight || this.terminalError) { return; }
    this.clearRecoveryTimer();
    this.recovering = this.hasJoinedOnce;
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

  aboutToDisappear(): void {
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
    this.clearRecoveryTimer();
    if (this.healthTimer !== -1) { clearInterval(this.healthTimer); this.healthTimer = -1; }
    if (this.pulseTimer !== -1) { clearInterval(this.pulseTimer); this.pulseTimer = -1; }
    if (this.fullscreenPreviewTimer !== -1) {
      clearTimeout(this.fullscreenPreviewTimer);
      this.fullscreenPreviewTimer = -1;
    }
    if (this.offLive !== null) { this.offLive(); this.offLive = null; }
    if (this.offMessages !== null) { this.offMessages(); this.offMessages = null; }
    if (this.offMessageError !== null) { this.offMessageError(); this.offMessageError = null; }
    if (this.offChannelMessages !== null) { this.offChannelMessages(); this.offChannelMessages = null; }
    this.liveStore?.dispose();
    this.liveStore = null;
    this.messageStore?.close();
    this.messageStore = null;
    this.channelMessageStore?.close();
    this.channelMessageStore = null;
    this.groupCallMessages = [];
    this.channelMessages = [];
    if (this.session !== null) {
      this.session.clearVideo();
      this.session.stop();
      this.session = null;
    }
    this.surfaceBinding = null;
    if (!this.leavingForFloating) { liveStreamBackgroundTask.stop(); }
    if (this.groupCallId > 0 && !this.leavingForFloating) {
      leaveGroupCall(getTdClient(), this.groupCallId).catch((error: Error): void => {
        logE(`RtmpLiveStream.leaveGroupCall failed: ${error.message}`);
      });
    }
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(23).fontColor([LIVE_TEXT]);
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
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT)
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
              this.headerPresentation().kind === 'error' ? LIVE_RED : LIVE_SUBTEXT
            )
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.canManageLive) {
            Text($r('app.string.ga_admin'))
              .fontSize(10).fontWeight(FontWeight.Medium).fontColor(LIVE_GREEN)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor('#2639D98A').borderRadius(8);
          }
        }
        .onClick((): void => this.retryLiveConnection());
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row() {
        SymbolGlyph($r('sys.symbol.plus_square_on_square')).fontSize(18).fontColor([LIVE_TEXT]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .backgroundColor(LIVE_PANEL_ALT)
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
      })
      .enabled(this.headerPresentation().actionsEnabled && !this.minimizeInProgress &&
        !this.leaveDialogOpen)
      .accessibilityText(this.minimizeInProgress ? $r('app.string.lv_minimising') : $r('app.string.lv_minimise'))
      .onClick((): void => this.minimizeToFloating());
      Row() {
        SymbolGlyph($r('sys.symbol.more')).fontSize(22).fontColor([LIVE_TEXT]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .backgroundColor(LIVE_PANEL_ALT)
      .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 110), curve: Curve.EaseOut
      })
      .enabled(this.groupCallId > 0 && !this.minimizeInProgress)
      .accessibilityText($r('app.string.lv_more_actions'))
      .bindMenu(this.headerMoreMenu());
    }
    .width('100%').height(64).padding({ left: 8, right: 10 })
    .alignItems(VerticalAlign.Center).backgroundColor(LIVE_BACKGROUND);
  }

  @Builder
  interactionHeader() {
    Row() {
      Column({ space: 2 }) {
        Text($r('app.string.lv_interactions')).fontSize(15).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT);
        Text(this.interactionPresentation().subtitle)
          .fontSize(11).fontColor(LIVE_SUBTEXT).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 }).fill(this.interactionStatusColor())
          .opacity(this.interactionPresentation().statusTone === 'accent' && this.pulseExpanded ? 1 : 0.62);
        Text(this.interactionPresentation().statusText)
          .fontSize(11).fontColor(this.interactionStatusColor());
      }
      .padding({ left: 8, right: 9, top: 5, bottom: 5 })
      .backgroundColor(this.interactionStatusBackground()).borderRadius(12)
      .animation({
        duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 160), curve: Curve.EaseOut
      });
    }
    .width('100%').height(50).padding({ left: 14, right: 14 })
    .backgroundColor(LIVE_PANEL);
  }

  @Builder
  comments() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.messages.length === 0) {
        Column({ space: 7 }) {
          if (this.interactionPresentation().showProgress) {
            Progress({ value: 30, total: 100, type: ProgressType.Ring })
              .width(28).height(28).color(LIVE_ACCENT).style({ strokeWidth: 3 });
          } else {
            SymbolGlyph($r('sys.symbol.message')).fontSize(30).fontColor([LIVE_SUBTEXT]);
          }
          Text(this.interactionPresentation().emptyTitle)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(LIVE_TEXT);
          Text(this.interactionPresentation().emptyDetail)
            .fontSize(11).fontColor(LIVE_SUBTEXT);
          if (this.interactionPresentation().showHistoryRetry) {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([LIVE_ACCENT]);
              Text($r('app.string.lv_retry_history')).fontSize(11).fontColor(LIVE_ACCENT);
            }
            .height(32).padding({ left: 10, right: 10 }).borderRadius(16)
            .backgroundColor('#1F3390EC')
            .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
            .onClick((): void => this.retryChannelHistory());
          }
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center);
      }
      List({ scroller: this.commentScroller, space: 8 }) {
        if (this.messages.length > 0 && this.interactionPresentation().showHistoryRetry) {
          ListItem() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(13).fontColor(['#FFB56B']);
              Text($r('app.string.lv_history_failed'))
                .fontSize(10).fontColor('#D7A56E').layoutWeight(1);
              Text($r('app.string.settings_retry')).fontSize(10).fontWeight(FontWeight.Medium).fontColor(LIVE_ACCENT);
            }
            .width('100%').height(34).padding({ left: 10, right: 10 })
            .backgroundColor('#1F8D692D').borderRadius(10)
            .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
            .onClick((): void => this.retryChannelHistory());
          }
        }
        ForEach(this.messages, (message: LiveInteractionEntry) => {
          ListItem() {
            LiveInteractionBubble({ message });
          }
        }, (message: LiveInteractionEntry): string => message.key)
      }
      .width('100%').height('100%')
      .padding({ left: 12, right: 14, top: 9, bottom: 10 })
      .maintainVisibleContentPosition(true)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
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
        .onClick((): void => this.scrollToInteractionTail())
        .transition(
          TransitionEffect.translate({ y: 8 }).combine(TransitionEffect.OPACITY).animation({
            duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 160), curve: Curve.EaseOut
          })
        );
      }
    }
    .width('100%').layoutWeight(1).backgroundColor(LIVE_PANEL);
  }

  @Builder
  composer() {
    if (this.interactionPresentation().composerEnabled) {
      Column({ space: 7 }) {
        Row({ space: 10 }) {
          ForEach(QUICK_REACTIONS, (emoji: string) => {
            Text(emoji).fontSize(21).textAlign(TextAlign.Center)
              .width(38).height(32).backgroundColor(LIVE_PANEL_ALT).borderRadius(16)
              .enabled(!this.sending)
              .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 100), curve: Curve.EaseOut
              })
              .onClick((): void => this.sendMessage(emoji));
          }, (emoji: string): string => emoji)
        }
        .width('100%').padding({ left: 2 });
        Row({ space: 9 }) {
          TextInput({ text: this.draft, placeholder: $r('app.string.lv_say_something') })
            .layoutWeight(1).height(42)
            .fontSize(15).fontColor(LIVE_TEXT).placeholderColor(LIVE_SUBTEXT)
            .backgroundColor(LIVE_PANEL_ALT).borderRadius(21)
            .padding({ left: 15, right: 15 })
            .enterKeyType(EnterKeyType.Send)
            .onChange((value: string): void => { this.draft = value; })
            .onSubmit((): void => this.sendMessage());
          Button() {
            if (this.sending) {
              Progress({ value: 30, total: 100, type: ProgressType.Ring })
                .width(18).height(18).color(Color.White).style({ strokeWidth: 2 });
            } else {
              SymbolGlyph($r('sys.symbol.paperplane')).fontSize(19).fontColor([Color.White]);
            }
          }
          .width(42).height(42).borderRadius(21)
          .backgroundColor(this.draft.trim() === '' || this.sending ? '#40505C' : LIVE_RED)
          .enabled(this.draft.trim() !== '' && !this.sending)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .onClick((): void => this.sendMessage());
        }.width('100%');
        if (this.interactionSendError !== '') {
          Row({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(13).fontColor(['#FF8190']);
            Text(this.interactionSendError).fontSize(10).fontColor('#FF9AA6')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
            Text($r('app.string.settings_retry')).fontSize(11).fontWeight(FontWeight.Medium).fontColor(LIVE_ACCENT)
              .height(28).padding({ left: 7, right: 7 })
              .onClick((): void => this.retryInteractionSend());
          }.width('100%');
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: Math.max(9, this.bottomSafe) })
      .backgroundColor(LIVE_BACKGROUND);
    } else {
      Row({ space: 8 }) {
        if (this.interactionPresentation().showProgress) {
          Progress({ value: 30, total: 100, type: ProgressType.Ring })
            .width(16).height(16).color(LIVE_ACCENT).style({ strokeWidth: 2 });
        } else {
          SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(15).fontColor([LIVE_SUBTEXT]);
        }
        Text(this.interactionPresentation().composerHint)
          .fontSize(12).fontColor(LIVE_SUBTEXT);
      }
      .width('100%').height(48 + Math.max(0, this.bottomSafe))
      .padding({ left: 16, right: 16, bottom: Math.max(0, this.bottomSafe) })
      .justifyContent(FlexAlign.Center).backgroundColor(LIVE_BACKGROUND);
    }
  }

  @Builder
  fullscreenInteractionDrawer() {
    Row() {
      Blank()
        .layoutWeight(1)
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => { this.fullscreenPanelOpen = false; });
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text($r('app.string.lv_interactions')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(LIVE_TEXT);
            Text(str('lv_recent_and_status', this.messages.length, this.interactionPresentation().statusText))
              .fontSize(11).fontColor(LIVE_SUBTEXT);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([LIVE_TEXT]);
          }
          .width(36).height(36).backgroundColor(LIVE_PANEL_ALT)
          .onClick((): void => { this.fullscreenPanelOpen = false; });
        }
        .width('100%').height(58).padding({ left: 14, right: 12 })
        .backgroundColor(LIVE_PANEL);
        this.comments();
        this.composer();
      }
      .width('84%').height('100%').constraintSize({ maxWidth: 460 })
      .backgroundColor(LIVE_PANEL)
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
      RtmpVideoStage({
        presentation: this.mediaPresentation(),
        channelTitle: this.displayTitle(),
        hasVideo: this.displayHasVideo(),
        recovering: this.recovering,
        fullscreen: true,
        fullscreenAvailable: true,
        pulseExpanded: this.pulseExpanded,
        onSurfaceReady: (surfaceId: string, width: number, height: number): void =>
          this.setSurface(surfaceId, width, height),
        onSurfaceGone: (surfaceId: string): void => this.clearSurface(surfaceId),
        onFullscreenToggle: (): void => this.toggleFullscreen(),
        onRetry: (): void => this.retryLiveConnection()
      });

      Column() {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
              .fontSize(20).fontColor([Color.White]);
          }
          .width(44).height(44).backgroundColor('#A617222B')
          .stateEffect(true)
          .enabled(!this.fullscreenTransitioning)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText($r('app.string.lv_exit_fullscreen'))
          .onClick((): void => this.toggleFullscreen());
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus_square_on_square')).fontSize(18).fontColor([Color.White]);
          }
          .width(44).height(44).backgroundColor('#B63390EC')
          .enabled(this.headerPresentation().actionsEnabled && !this.minimizeInProgress &&
            !this.leaveDialogOpen && !this.fullscreenTransitioning)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(this.minimizeInProgress ? $r('app.string.lv_minimising') : $r('app.string.lv_minimise'))
          .onClick((): void => this.minimizeToFloating());
          Row({ space: 6 }) {
            Circle({ width: 7, height: 7 }).fill(this.headerDotColor())
              .opacity(this.headerPresentation().pulse && this.pulseExpanded ? 1 : 0.62);
            Text(this.headerPresentation().fullscreenText)
              .fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White);
          }
          .height(34).padding({ left: 10, right: 11 })
          .backgroundColor(this.fullscreenStatusBackground()).borderRadius(17);
          Blank();
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.message')).fontSize(17).fontColor([Color.White]);
              Text(str('lv_interactions_n', this.messages.length)).fontSize(13).fontColor(Color.White);
            }
          }
          .height(40).padding({ left: 12, right: 12 })
          .backgroundColor('#A617222B').borderRadius(20)
          .stateStyles({ normal: this.topActionNormalStyle, pressed: this.topActionPressedStyle })
          .accessibilityText(str('lv_open_interactions', this.messages.length))
          .onClick((): void => {
            this.fullscreenMessagePreview = '';
            this.fullscreenPanelOpen = true;
            if (this.interactionAtBottom) {
              setTimeout((): void => this.commentScroller.scrollEdge(Edge.Bottom), 80);
            }
          });
        }.width('100%');
        Blank();
        if (this.fullscreenMessagePreview !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.message')).fontSize(16).fontColor([LIVE_ACCENT]);
            Text(this.fullscreenMessagePreview)
              .fontSize(13).fontColor(Color.White).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .constraintSize({ maxWidth: 360 })
          .padding({ left: 12, right: 13, top: 8, bottom: 8 })
          .backgroundColor('#C914222B').borderRadius(18).alignSelf(ItemAlign.Start)
          .transition(TransitionEffect.OPACITY.animation({
            duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
          }));
        }
      }
      .width('100%').height('100%')
      .padding({
        left: Math.max(14, this.cutoutLeftSafe + 8),
        right: Math.max(14, this.cutoutRightSafe + 8),
        top: Math.max(this.topSafe, this.cutoutTopSafe) + 10,
        bottom: this.bottomSafe + 14
      });

      if (this.fullscreenPanelOpen) {
        this.fullscreenInteractionDrawer();
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
          RtmpVideoStage({
            presentation: this.mediaPresentation(),
            channelTitle: this.displayTitle(),
            hasVideo: this.displayHasVideo(),
            recovering: this.recovering,
            fullscreen: false,
            fullscreenAvailable: this.canEnterFullscreen(),
            pulseExpanded: this.pulseExpanded,
            onSurfaceReady: (surfaceId: string, width: number, height: number): void =>
              this.setSurface(surfaceId, width, height),
            onSurfaceGone: (surfaceId: string): void => this.clearSurface(surfaceId),
            onFullscreenToggle: (): void => this.toggleFullscreen(),
            onRetry: (): void => this.retryLiveConnection()
          });
          this.interactionHeader();
          this.comments();
          this.composer();
        }
        .width('100%').height('100%');
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
    .width('100%').height('100%').backgroundColor(LIVE_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.isFullscreen ? 0 : this.topSafe });
  }
}
