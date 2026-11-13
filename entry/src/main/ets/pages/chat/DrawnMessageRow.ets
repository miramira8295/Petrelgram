import { DrawnMediaAnchorPool, DrawnCanvasAttributes } from './DrawnNativeAttributes';
import { drawnPainterReserve } from './DrawnPainterReserve';
import { DrawnRowLayoutEngine, takeDrawnWarmLayout } from './DrawnLayoutWarmCache';
import { DrawnLayoutRetention, takeDrawnRecycledLayout } from './DrawnRecycledLayouts';
import { DrawnRouteReason, DrawnRouteTracker } from '../../util/drawnRouteMetrics';
import { DrawnInvalidation, DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { DrawnMediaFrame, DrawnMediaFrames } from './DrawnMediaFrames';
import { DrawnMediaSlot, DrawnMediaSlots } from '../../util/drawnMediaSlot';
import { DrawnInlineEmojiLayer } from './DrawnInlineEmojiLayer';
import { DrawnBusyLink } from './DrawnBusyLink';
import { BubbleInlineKeyboard } from './BubbleInlineKeyboard';
import { MessageBubbleContext } from './MessageBubbleShell';
import { drawnAnimationPlaying } from '../../util/drawnAnimationPolicy';
import { DrawnSingleMediaVideo } from './DrawnSingleMediaVideo';
import { DrawnSingleMediaLayouts } from './DrawnSingleMediaLayout';
import { LegacySingleMediaBubble } from './LegacySingleMediaBubble';
import { drawnSingleMediaEligible } from '../../util/drawnSingleMediaPolicy';
import { SenderAnimatedLayer } from './SenderAnimatedLayer';
import { DrawnAlbumVideo } from './DrawnAlbumVideo';
import { DrawnChromeIslands } from './DrawnChromeIslands';
import { DrawnReactionChip } from './DrawnReactionLayout';
import { drawnLiveSurface } from '../../util/drawnContentPolicy';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { LegacyTextRow } from './LegacyTextRow';
import { DrawnTextLayouts } from './DrawnTextLayout';
import { drawnTextRowEligible } from '../../util/drawnTextRowPolicy';
import { MessageDragGesture } from '../../util/messageDragGesture';
import { configureMessageDrag } from '../../services/MessageDragSource';
import { messageDragType } from '../../util/messageDrag';
import { tableScrollTouched } from '../../util/tableTouchChannel';
import { LegacyAlbumMessageBubble } from './LegacyAlbumMessageBubble';
import { DrawnAlbumLayouts } from './DrawnAlbumLayout';
import { DrawnBubblePlan, DrawnBubbleTile } from './DrawnBubblePlan';
import { DrawnBubblePainter, DrawnBubbleForeground, DrawnBubbleAvatar } from './DrawnBubblePainter';
import { DrawnImageSlot, DrawnMediaController } from './DrawnMediaController';
import { DrawnBubbleController } from './DrawnBubbleController';
import { DrawnBubbleMenu } from './DrawnBubbleMenu';
import { DRAWN_BUBBLE_PRESS, DRAWN_BUBBLE_PRESS_NONE } from './DrawnBubblePress';
import { drawnAlbumEligible, albumRectContains } from '../../util/drawnAlbumPolicy';
import { DrawnRichHit } from '../../util/drawnRichTextPolicy';
import { drawnTextUsesRtlLayout } from './DrawnPlainTextLayout';
import { drawnChromeTextSupported, drawnTailGutter } from '../../util/drawnPlainTextPolicy';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { chatEnv } from '../../util/chatEnvMirror';
import { a11yRuntimeState } from '../../util/a11yState';
import { TranslationStatus, translationStatusFor } from '../../util/translationChannel';
import { sendStateFor } from '../../util/sendStateChannel';
import { viewCountLabelFor } from '../../util/viewCountChannel';
import { senderRoleFor, senderRoleKey } from '../../util/senderRoleChannel';
import { pinForTranslationGrowth } from '../../util/translationGrowthPin';
import { senderHasAnimatedPhoto } from '../../services/PhotoAnimationFetch';
import { animationDurationFor, scrollActiveNow, scrollPlaceholderState } from '../../util/scrollEffects';
import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { AlbumCornerRadiiCache } from '../../util/albumCornerRadii';
import { ShatterDeleteOverlay } from '../common/ShatterDeleteOverlay';
import { DrawnRowLeaveCapture } from './DrawnRowLeaveCapture';
import { LiveProgressRing } from './LiveProgressRing';
import { MessageMenuTransitions } from '../../util/messageMenuTransitions';
import { menuPreviewCompact } from '../../util/menuPreview';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { messageGesturePolicy } from '../../util/messageGestures';
import { isEdgeSwipeStart, SWIPE_REPLY_MAX, SWIPE_REPLY_TRIGGER, SWIPE_SELECT_MAX,
  SWIPE_SELECT_TRIGGER } from '../../util/swipeReplyGesture';
import { firstFinger } from '../../util/firstFinger';
import { JUMP_FOCUS_SCALE, JUMP_FOCUS_BRIGHTNESS } from '../../util/bubbleFocusChannel';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { logW } from '../../util/log';

const EMPTY_DRAWN_NATIVE_TILES: DrawnBubbleTile[] = [];

@ComponentV2
export struct DrawnMessageRow {
  @Param kind: 'album' | 'text' | 'single' = 'album';
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  // V2 resets these initializers after the current @Param values and before
  // @Computed plan. Read fixed-count channel snapshots here so reuse does not
  // lay out blank metadata first and repeat layout after attach(). No listeners
  // or IO here; attach still subscribes and catches changes since this snapshot.
  @Local private sendState: string = sendStateFor(this.group.head.rowId) || this.group.head.sendState;
  @Local private views: string = viewCountLabelFor(this.data.chatId, this.group.head.id);
  @Local private role: string = this.group.head.senderTag ||
    (this.data.isGroup && !this.group.head.isOutgoing && this.group.showSenderName
      ? senderRoleFor(senderRoleKey(this.data.chatId, this.group.head.senderId)) : '');
  @Local private translation: TranslationStatus | null = translationStatusFor(this.group.head.id);
  @Local private avatarAnimated: boolean = senderHasAnimatedPhoto(this.group.head.senderId, this.group.head.senderIsUser);
  @Local private avatarStateRevision: number = 0;
  @Local private menuShown: boolean = false;
  @Local private swipeX: number = 0;
  @Local private capturedDeleteKey: string = '';
  private leaveCapture: DrawnRowLeaveCapture = new DrawnRowLeaveCapture((key: string): void => {
    if (this.capturedDeleteKey !== key) { this.capturedDeleteKey = key; }
  });
  private env = chatEnv;
  private a11y = a11yRuntimeState;
  private scroll = scrollPlaceholderState;
  private albumLayouts: DrawnRowLayoutEngine | null = null;
  private singleLayouts: DrawnRowLayoutEngine | null = null;
  private textLayouts: DrawnRowLayoutEngine | null = null;
  private layoutRetention: DrawnLayoutRetention = new DrawnLayoutRetention();
  private nativeAnchors: DrawnMediaAnchorPool = new DrawnMediaAnchorPool();
  private canvasAttributes: DrawnCanvasAttributes = new DrawnCanvasAttributes();
  private painter: DrawnBubblePainter = drawnPainterReserve.takeBackground();
  private avatarPainter: DrawnBubbleAvatar = drawnPainterReserve.takeAvatar();
  private foreground: DrawnBubbleForeground = drawnPainterReserve.takeForeground();
  private media: DrawnMediaController = new DrawnMediaController(
    (): void => { this.avatarStateRevision++; }, (): void => {
      drawnStageMetrics.invalidated(DrawnInvalidation.AvatarImage); this.avatarPainter.invalidate();
      const m = this.group.head;
      const animated = senderHasAnimatedPhoto(m.senderId, m.senderIsUser);
      if (this.avatarAnimated !== animated) { this.avatarAnimated = animated; }
    });
  private channels: DrawnBubbleController = new DrawnBubbleController({
    send: (value: string): void => { if (this.sendState !== value) { this.sendState = value; } },
    views: (value: string): void => { if (this.views !== value) { this.views = value; } },
    role: (value: string): void => { if (this.role !== value) { this.role = value; } },
    translation: (value: TranslationStatus | null): void => {
      if (this.translation !== value) { this.translation = value; pinForTranslationGrowth(this.data.chatId); }
    }
  });
  private gridCorners: AlbumCornerRadiiCache = new AlbumCornerRadiiCache();
  private menuFx: MessageMenuTransitions = new MessageMenuTransitions();
  private active: boolean = false;
  private dragGesture: MessageDragGesture = new MessageDragGesture();
  private draggingMessage: boolean = false;
  private touchOnBody: boolean = false;
  private claimed: boolean = false;
  private edge: boolean = false;
  private menuOffset: number = 0;
  private touchPlan: DrawnBubblePlan | null = null;
  private touchLink: DrawnRichHit | null = null;
  private touchReaction: DrawnReactionChip | null = null;
  @Local private allowBodyDrag: boolean = true;
  private attachedGroup: AlbumGroup | null = null;
  private attachedData: MessageBubbleRenderData | null = null;
  private attachedEnvironment: string = '';
  private inputIdentity: string = '';
  private touchX: number = 0;
  private touchY: number = 0;
  private touchRowId: number = 0;
  private touchChatId: number = 0;
  private failureLogged: boolean = false;
  private routeTracker: DrawnRouteTracker | undefined = undefined;
  private recordRoute(reason: DrawnRouteReason): void {
    if (this.routeTracker === undefined) { this.routeTracker = new DrawnRouteTracker(); }
    this.routeTracker.record(this.data.chatId, this.group.head.rowId, reason);
  }
  private rejectRoute(reason: DrawnRouteReason): null { this.recordRoute(reason); return null; }
  private keyboardContext: MessageBubbleContext | null = null;
  private keyboardState(): MessageBubbleContext {
    if (this.keyboardContext === null) { this.keyboardContext = new MessageBubbleContext(); }
    return this.keyboardContext;
  }
  private keyboardGutter(): number { return this.kind === 'text' ? drawnTailGutter(this.group.showAvatar) : 7; }
  private keyboardWidth(): number {
    const p = this.plan;
    return p !== null ? p.width - p.bubbleX - this.keyboardGutter() : 0;
  }

  // This getter owns bounded, non-observed layout caches. Lazy initialization
  // avoids allocating unused text/media engines; prepare reuses body paragraphs.
  // It never publishes component state, subscribes channels or performs IO.
  // Route telemetry is a fixed-size non-observed counter, deduplicated per owner.
  // It counts evaluations that ENTER/change a route (including predictive reuse).
  @Computed
  private get plan(): DrawnBubblePlan | null {
    const environment = `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
    const textEnvironment = `${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
    const eligible = this.kind === 'text' ? drawnTextRowEligible(this.group, this.data, this.env.bubbleMaterialOn, this.a11y.active)
      : this.kind === 'single' ? drawnSingleMediaEligible(this.group, this.env.bubbleMaterialOn, this.a11y.active)
      : drawnAlbumEligible(this.group, this.data, this.env.bubbleMaterialOn, this.a11y.active);
    if (this.env.drawnEnabled === false) { return this.rejectRoute(DrawnRouteReason.Disabled); }
    if (this.kind === 'text' ? this.env.drawnText === false : this.kind === 'single' ? this.env.drawnSingle === false : this.env.drawnAlbum === false) { return this.rejectRoute(DrawnRouteReason.Disabled); }
    // Match the former caption gate without building a paragraph just to discard
    // it. Empty media rows remain eligible when a body renderer is disabled.
    const bodyText = this.kind === 'album' ? this.group.caption : this.group.head.text;
    if (bodyText !== '' && (this.data.lightweightPlainText ? this.env.drawnPlain === false : this.env.drawnRich === false)) { return this.rejectRoute(DrawnRouteReason.BodyDisabled); }
    if (this.env.bubbleMaterialOn) { return this.rejectRoute(DrawnRouteReason.Material); }
    if (this.a11y.active) { return this.rejectRoute(DrawnRouteReason.Accessibility); }
    if (!eligible) { return this.rejectRoute(DrawnRouteReason.Policy); }
    if (this.translation !== null) { return this.rejectRoute(DrawnRouteReason.Translation); }
    if (drawnTextUsesRtlLayout(textEnvironment)) { return this.rejectRoute(DrawnRouteReason.Rtl); }
    const m = this.group.head;
    // Match the actual header/quote/forward branches in both layout engines.
    // Hidden metadata must not reject a drawable row or scan unused strings.
    if (m.forwardFrom !== '' && !drawnChromeTextSupported(m.forwardFrom)) {
      return this.rejectRoute(DrawnRouteReason.ChromeForward);
    }
    const shownName = this.data.isGroup && !m.isOutgoing && this.group.showSenderName && m.senderName !== '';
    if (shownName) {
      if (!drawnChromeTextSupported(m.senderName)) { return this.rejectRoute(DrawnRouteReason.ChromeSender); }
      if (!drawnChromeTextSupported(m.senderTag || this.role)) { return this.rejectRoute(DrawnRouteReason.ChromeRole); }
    }
    if (m.replyToMessageId !== 0) {
      if (!drawnChromeTextSupported(m.replySenderName)) { return this.rejectRoute(DrawnRouteReason.ChromeReplySender); }
      if (!drawnChromeTextSupported(m.replyText)) { return this.rejectRoute(DrawnRouteReason.ChromeReplyText); }
    }
    const traced = drawnStageMetrics.begin(DrawnStage.Layout);
    try {
      const ui = this.getUIContext();
      if (this.kind === 'text' && this.textLayouts === null) {
        this.textLayouts = takeDrawnRecycledLayout(this.data.chatId, m.rowId, 'text') ??
          takeDrawnWarmLayout(this.data.chatId, m.id, 'text') ?? new DrawnTextLayouts();
      }
      if (this.kind === 'album' && this.albumLayouts === null) {
        this.albumLayouts = takeDrawnRecycledLayout(this.data.chatId, m.rowId, 'album') ??
          takeDrawnWarmLayout(this.data.chatId, m.id, 'album') ?? new DrawnAlbumLayouts();
      }
      if (this.kind === 'single' && this.singleLayouts === null) {
        this.singleLayouts = takeDrawnRecycledLayout(this.data.chatId, m.rowId, 'single') ??
          takeDrawnWarmLayout(this.data.chatId, m.id, 'single') ?? new DrawnSingleMediaLayouts();
      }
      const layouts = this.kind === 'text' ? this.textLayouts : this.kind === 'single' ? this.singleLayouts : this.albumLayouts;
      if (layouts !== null) { this.layoutRetention.remember(this.group, this.data, this.kind, layouts); }
      const p = layouts?.prepare(ui, this.group, this.data, {
        radius: this.env.bubbleRadius, fontSize: this.env.msgTextSize, environment, textEnvironment,
        role: m.senderTag || this.role, views: this.views
      }) ?? null;
      this.recordRoute(p === null ? (layouts?.failureReason === undefined || layouts.failureReason === DrawnRouteReason.Drawn
        ? DrawnRouteReason.LayoutNull : layouts.failureReason) : DrawnRouteReason.Drawn);
      return p;
    } catch (error) {
      if (!this.failureLogged) {
        this.failureLogged = true;
        logW(`DrawnMessageRow: layout unavailable, using legacy: ${(error as Error)?.message ?? String(error)}`);
      }
      return this.rejectRoute(DrawnRouteReason.Exception);
    } finally { drawnStageMetrics.end(traced); }
  }

  private attach(): void {
    if (!this.active) { return; }
    this.syncMediaVisibility();
    const environment = this.roleEnvironment;
    if (this.attachedGroup === this.group && this.attachedData === this.data &&
      this.attachedEnvironment === environment) {
      drawnStageMetrics.skip(DrawnStage.Attach); return;
    }
    // A failed A → B bind must not leave an A cache hit over partial B state.
    this.attachedGroup = null; this.attachedData = null;
    const traced = drawnStageMetrics.begin(DrawnStage.Attach);
    try {
      const m = this.group.head;
      const identity = `${this.data.chatId}:${m.rowId}`;
      if (identity !== this.inputIdentity) {
        this.inputIdentity = identity; this.touchPlan = null; this.touchReaction = null; this.touchLink = null;
        this.touchRowId = 0; this.touchChatId = 0; this.foreground.press(null);
      }
      // The same sender can gain/lose an animated photo; identity-only memoization
      // would miss store updates. This is one O(1) lookup, with no network request.
      this.avatarAnimated = senderHasAnimatedPhoto(m.senderId, m.senderIsUser);
      this.channels.attach(this.data.chatId, m, this.data.isGroup && !m.isOutgoing && this.group.showSenderName);
      // Commit only after successful attachment. Channels deliver later status,
      // translation and avatar changes independently of these input snapshots.
      this.attachedGroup = this.group; this.attachedData = this.data;
      this.attachedEnvironment = environment;
    } finally { drawnStageMetrics.end(traced); }
  }
  private syncMedia(): void {
    if (!this.active) { return; }
    const p = this.plan;
    if (p === null) { this.media.recycle(); }
    else { this.media.prepare(this.getUIContext(), p, this.group, this.kind === 'album'); }
  }
  @Computed
  private get roleEnvironment(): string { return `${this.env.langEpoch}:${this.env.bubbleMaterialOn}`; }
  @Monitor('roleEnvironment')
  private roleEnvironmentChanged(): void { this.attach(); }
  @Monitor('group', 'data')
  private inputChanged(): void {
    this.attach();
    // Cached geometry may retain identity across sender/path updates. Unchanged
    // tile arrays skip image binding entirely; avatar refresh is constant time.
    this.syncMedia();
  }
  @Computed
  private get deleteNodeKey(): string { return `dissolve-delete-message-${this.data.chatId}-${this.group.head.rowId}`; }
  @Computed
  private get deleteCaptureSupported(): boolean { return !drawnLiveSurface(this.group, this.data); }
  @Monitor('deleteNodeKey', 'leaving', 'deleteCaptureSupported', 'actions')
  private syncDeleteCapture(): void {
    if (!this.active || this.plan === null) { this.leaveCapture.reset(); return; }
    this.leaveCapture.bind(this.deleteNodeKey, this.group.head.rowId, this.leaving,
      this.deleteCaptureSupported, this.actions.rowLeave);
  }
  @Monitor('plan')
  private layoutChanged(): void { this.syncMedia(); this.syncDeleteCapture(); }
  aboutToAppear(): void { this.active = true; this.attach(); this.syncMedia(); this.syncDeleteCapture(); }
  aboutToRecycle(): void {
    this.layoutRetention.release();
    this.textLayouts = null; this.albumLayouts = null; this.singleLayouts = null;
    this.mediaVisibilityEpoch++; this.mediaVisibilityKey = '';
    this.routeTracker?.reset();
    this.attachedGroup = null; this.attachedData = null; this.attachedEnvironment = '';
    this.inputIdentity = '';
    this.leaveCapture.reset();
    this.allowBodyDrag = true;
    this.dragGesture.reset(); this.draggingMessage = false; this.touchOnBody = false;
    this.active = false; this.channels.detach(); this.media.recycle();
    this.touchRowId = 0; this.touchChatId = 0; this.menuShown = false; this.swipeX = 0;
    this.claimed = false; this.touchLink = null; this.touchPlan = null; this.foreground.press(null);
    this.touchReaction = null;
  }
  aboutToReuse(): void {
    this.allowBodyDrag = true;
    this.dragGesture.reset(); this.draggingMessage = false; this.touchOnBody = false;
    this.touchRowId = 0; this.touchChatId = 0; this.touchPlan = null; this.touchLink = null;
    this.touchReaction = null;
    this.claimed = false; this.edge = false; this.menuOffset = 0; this.menuShown = false; this.swipeX = 0;
    this.active = true; this.attach(); this.syncMedia(); this.syncDeleteCapture();
  }
  aboutToDisappear(): void { this.aboutToRecycle(); this.media.dispose(); }

  private linkAt(x: number, y: number): DrawnRichHit | null {
    const p = this.plan;
    return p?.caption?.hitIndex.find(x - p.captionX, y - p.captionY) ?? null;
  }
  private reactionAt(x: number, y: number): DrawnReactionChip | null {
    const c = this.plan?.chrome;
    return c?.reactions?.hit(x - c.reactionsX, y - c.reactionsY) ?? null;
  }
  private click(event: ClickEvent): void {
    const p = this.plan;
    if (this.claimed || p === null || (event.source === SourceType.TouchScreen &&
      (this.touchRowId !== this.group.head.rowId || this.touchChatId !== this.data.chatId))) { return; }
    const m = this.group.head;
    if (p.avatar.width > 0 && albumRectContains(p.avatar, event.x, event.y)) {
      if (m.senderIsUser && m.senderId > 0) { this.actions.onAvatarTap(m.senderId); }
      return;
    }
    for (const tile of p.tiles) {
      if (albumRectContains(tile, event.x, event.y)) {
        if (this.data.selectionActive) { this.actions.onToggleSelectedMessage(tile.cell.messageId); }
        else if (tile.cell.failed && (this.kind === 'single' ? m.photoPath === ''
          : this.imageSlot(tile.cell.idx)?.path === '') && tile.cell.thumbFileId !== 0) {
          this.actions.onSpecialPhotoRetry(tile.cell.messageId);
        } else if (this.kind === 'single' && m.isAnimation) {
          if (drawnAnimationPlaying(m, this.data, this.env, true)) { this.openMenu(event.x); }
          else { this.actions.onAnimationTap(m.id, false); }
        } else { this.actions.onMediaTap(tile.cell.messageId, event.windowX, event.windowY); }
        return;
      }
    }
    if (this.data.selectionActive) { return; }
    const chrome = p.chrome;
    const reaction = this.reactionAt(event.x, event.y);
    if (reaction !== null) {
      if (event.source === SourceType.TouchScreen && (this.touchPlan !== p || this.touchReaction !== reaction)) { return; }
      this.foreground.press(null);
      if (reaction.reaction === null) {
        this.actions.onShowReactorsList(m.id, `reactors_anchor_${this.data.chatId}_${m.id}`);
      } else { this.actions.onSetReaction(m.id, reaction.key, reaction.reaction.isChosen); }
      return;
    }
    if (chrome !== null && chrome.content.forward !== null && albumRectContains(chrome.forwardRect, event.x, event.y)) {
      if (event.source === SourceType.TouchScreen && this.touchPlan !== p) { return; }
      if (m.forwardOriginChatId !== 0 || m.forwardOriginUserId !== 0) {
        this.actions.onForwardTap(m.forwardOriginChatId, m.forwardOriginMsgId, m.forwardOriginUserId);
      }
      return;
    }
    if (chrome !== null && chrome.content.comments !== null && albumRectContains(chrome.commentsRect, event.x, event.y)) {
      if (event.source !== SourceType.TouchScreen || this.touchPlan === p) { this.actions.onCommentTap(m.id); }
      return;
    }
    if (p.quote !== null && albumRectContains(p.quoteRect, event.x, event.y)) {
      this.actions.onReplyTap(m.replyToMessageId, m.id); return;
    }
    const link = this.linkAt(event.x, event.y);
    if (link !== null) {
      if (event.source !== SourceType.TouchScreen || (this.touchPlan === p && this.touchLink === link)) {
        this.foreground.press(null); this.actions.onLinkTap(link.link.url, link.link.hidesUrl);
      }
      return;
    }
    if (messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) { this.openMenu(event.x); }
  }
  private openMenu(x: number): void {
    this.menuOffset = x - (this.plan?.width ?? 0) / 2; this.menuShown = true;
  }
  private longPress(event: GestureEvent): void {
    if (this.claimed || this.draggingMessage || tableScrollTouched()) { return; }
    const f = firstFinger(event.fingerList), p = this.plan;
    const x = this.rowToCanvasX(f?.localX ?? 0, Number(event.target.area.width));
    const y = (f?.localY ?? 0) - (this.group.showSenderName ? 3 : 1);
    const reaction = this.reactionAt(x, y);
    if (!this.data.selectionActive && reaction !== null && reaction.reaction !== null &&
      this.touchPlan === p && this.touchReaction === reaction) {
      this.claimed = true; this.foreground.press(null);
      this.actions.onShowReactors(this.group.head.id, reaction.key); return;
    }
    if (f !== undefined && p !== null && p.avatar.width > 0 && albumRectContains(p.avatar, x, y)) {
      this.claimed = true; this.foreground.press(null);
      const m = this.group.head;
      if (m.senderIsUser && m.senderId > 0) { this.actions.onAvatarLongPress(m.senderId, m.senderName); }
      return;
    }
    if (this.canDragMessage() && this.touchOnBody) { return; }
    this.invokeLongPress(x);
  }
  private invokeLongPress(x: number): void {
    if (this.claimed || this.draggingMessage || tableScrollTouched()) { return; }
    this.claimed = true; this.foreground.press(null);
    const policy = messageGesturePolicy(this.env.gestureScheme);
    if (this.data.selectionActive || policy.longPressSelects) { this.actions.onSelectMessages(this.group.memberIds); }
    else if (policy.longPressOpensMenu) { this.openMenu(x); }
  }
  private rowToCanvasX(x: number, rowWidth: number): number {
    return x - (this.group.head.isOutgoing ? rowWidth - 4 - (this.plan?.width ?? 0) : 4);
  }
  private rowTouch(event: TouchEvent): void {
    const t = event.changedTouches[0] ?? event.touches[0];
    if (event.type === TouchType.Down && t !== undefined) {
      this.claimed = false; this.draggingMessage = false;
      this.touchRowId = this.group.head.rowId; this.touchChatId = this.data.chatId;
      this.edge = isEdgeSwipeStart(t.windowX, this.env.screenWidthVp);
    }
    if (event.type === TouchType.Cancel || event.touches.length > 1) {
      this.claimed = true; this.touchLink = null; this.foreground.press(null);
      this.touchReaction = null;
    }
  }
  private touch(event: TouchEvent): void {
    this.dragTouch(event);
    const t = event.changedTouches[0] ?? event.touches[0];
    if (event.type === TouchType.Down && t !== undefined) {
      this.claimed = false; this.edge = isEdgeSwipeStart(t.windowX, this.env.screenWidthVp);
      this.touchPlan = this.plan; this.touchX = t.x; this.touchY = t.y;
      this.touchLink = this.linkAt(t.x, t.y);
      this.touchReaction = this.reactionAt(t.x, t.y);
      this.foreground.setPress(this.touchLink, this.plan?.density ?? 1);
      if (!this.data.selectionActive) { this.foreground.pressReaction(this.touchReaction); }
    } else if (event.type === TouchType.Cancel || event.touches.length > 1 || this.touchPlan !== this.plan) {
      this.touchLink = null; this.foreground.press(null);
      this.touchReaction = null;
    } else if (event.type === TouchType.Move || event.type === TouchType.Up) {
      if (t === undefined || this.linkAt(t.x, t.y) !== this.touchLink) { this.touchLink = null; }
      if (t === undefined || this.reactionAt(t.x, t.y) !== this.touchReaction) { this.touchReaction = null; this.foreground.pressReaction(null); }
      if (event.type === TouchType.Up || t === undefined || Math.hypot(t.x - this.touchX, t.y - this.touchY) > 8) {
        this.foreground.press(null);
      }
    }
  }
  private swipe(offset: number): void {
    if (this.edge || this.data.editingActive || this.draggingMessage ||
      (this.touchOnBody && this.canDragMessage() && this.dragGesture.prefersDrag(Date.now()))) { return; }
    this.swipeX = Math.max(this.data.canReply ? SWIPE_REPLY_MAX : 0, Math.min(SWIPE_SELECT_MAX, offset));
    if (this.swipeX !== 0) { this.claimed = true; this.foreground.press(null); }
  }
  private endSwipe(): void {
    const usable = !this.edge && !this.data.editingActive && !this.draggingMessage &&
      !(this.touchOnBody && this.canDragMessage() && this.dragGesture.prefersDrag(Date.now()));
    const reply = usable && this.data.canReply && this.swipeX <= SWIPE_REPLY_TRIGGER;
    const select = usable && this.swipeX >= SWIPE_SELECT_TRIGGER;
    this.getUIContext().animateTo({ duration: this.env.powerSaving || this.env.reduceAnim ? 0 : 180,
      curve: Curve.EaseOut }, (): void => { this.swipeX = 0; });
    if (reply) { this.actions.onReplyTo(this.group.head.id); }
    else if (select) { this.actions.onSelectMessages(this.group.memberIds); }
  }

  private canDragMessage(): boolean {
    return this.kind === 'text' && !this.data.selectionActive && !this.data.editingActive &&
      this.group.memberIds.length === 1 && this.group.head.id > 0;
  }
  private dragTouch(event: TouchEvent): void {
    const t = event.touches[0] ?? event.changedTouches[0], p = this.plan;
    if (event.type === TouchType.Down) {
      this.dragGesture.reset();
      this.touchOnBody = t !== undefined && p !== null && t.x >= p.bubbleX && this.reactionAt(t.x, t.y) === null;
      this.allowBodyDrag = this.touchOnBody;
      if (this.canDragMessage() && this.touchOnBody && t !== undefined) {
        this.dragGesture.begin(t.windowX, t.windowY, Date.now());
      }
      return;
    }
    if (!this.canDragMessage() || !this.touchOnBody) { return; }
    const now = Date.now();
    if (t !== undefined) { this.dragGesture.move(t.windowX, t.windowY, now); }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.touches.length > 1) {
      const stale = this.touchRowId !== this.group.head.rowId || this.touchChatId !== this.data.chatId;
      if (this.dragGesture.end(now, event.type !== TouchType.Up || stale || this.claimed)) {
        this.invokeLongPress(t?.x ?? this.touchX);
      }
    }
  }

  @Builder
  menu() {
    DrawnBubbleMenu({ msg: this.group.head, group: this.group, data: this.data,
      actions: this.actions, nowSec: this.nowSec });
  }

  private gridRadii(): BorderRadiuses {
    const m = this.group.head;
    const pure = this.group.caption === '' && m.text === '' && m.replyToMessageId === 0 &&
      m.reactions.length === 0 && m.forwardFrom === '' && !(this.data.isChannel && m.commentCount > 0) &&
      !(this.data.isGroup && !m.isOutgoing && this.group.showSenderName && m.senderName !== '');
    return this.gridCorners.prepare(pure, this.env.bubbleRadius, m.isOutgoing, this.group.showSenderName, this.group.showAvatar);
  }

  // Track only this physical slot. Ordinary bitmap upgrades invalidate its
  // modifier directly; placeholder/fallback changes publish this slot's revision.
  private imageSlot(index: number): DrawnImageSlot | undefined {
    const slot = this.media.slots[index];
    return this.readImageSlot(slot, slot?.state.revision ?? 0);
  }
  private readImageSlot(slot: DrawnImageSlot | undefined, _revision: number): DrawnImageSlot | undefined { return slot; }
  private mediaActivated(index: number): boolean {
    return this.kind !== 'album' || this.imageSlot(index)?.activated === true;
  }
  private mediaVisibilityEpoch: number = 0;
  private mediaVisibilityKey: string = '';
  private syncMediaVisibility(): number {
    const key = `${this.data.chatId}:${this.group.head.rowId}`;
    if (key !== this.mediaVisibilityKey) { this.mediaVisibilityKey = key; this.mediaVisibilityEpoch++; }
    return this.mediaVisibilityEpoch;
  }
  private mediaVisibility(): (visible: boolean, ratio: number) => void {
    const generation = this.syncMediaVisibility();
    const chatId = this.data.chatId, rowId = this.group.head.rowId;
    return (_visible: boolean, ratio: number): void => {
      if (this.active && generation === this.mediaVisibilityEpoch && this.data.chatId === chatId && this.group.head.rowId === rowId) {
        this.media.setVisible(ratio > 0);
      }
    };
  }
  private mediaOverlay(index: number): boolean {
    const slot = this.imageSlot(index);
    // ForEach owns tile existence. A queued old callback can still run after
    // shrink/fallback, even while the controller holds its old image slots.
    return this.nativeTiles[index] !== undefined && slot !== undefined &&
      (this.mediaActivated(index) || (slot.pixels !== undefined && !slot.receiver.canDraw(slot.pixels, ImageFit.Cover))) &&
      (this.sendState === 'sending' || slot.path === '' || slot.pixels === undefined ||
        !slot.receiver.canDraw(slot.pixels, ImageFit.Cover));
  }
  private nativeAvatar(_revision: number): boolean {
    return this.media.avatarPixels !== undefined && !this.media.avatar.canDraw(this.media.avatarPixels, ImageFit.Cover);
  }

  // The plan may retain identity for same-size footer edits. Keep paint content
  // as a separate dependency, so only the foreground observer is replayed.
  @Computed
  private get footerPaintKey(): string { return `${this.views}:${this.group.head.date}:${this.group.head.editDate}`; }

  // Computed publishes only when the grid snapshot changes. Footer, caption
  // placement and shell style can invalidate plan without touching tile nodes.
  @Computed
  private get nativeTiles(): DrawnBubbleTile[] { return this.plan?.nativeTiles ?? EMPTY_DRAWN_NATIVE_TILES; }
  @Computed
  private get mediaChatId(): number { return this.data.chatId; }
  private mediaFrameCache: DrawnMediaFrames = new DrawnMediaFrames();
  @Computed
  private get mediaFrames(): DrawnMediaFrame[] {
    return this.mediaFrameCache.prepare(this.nativeTiles, this.mediaChatId, this.kind === 'single');
  }
  private mediaSlotCache: DrawnMediaSlots = new DrawnMediaSlots();
  @Computed
  private get mediaSlots(): DrawnMediaSlot[] { return this.mediaSlotCache.prepare(this.nativeTiles.length); }

  // slot is immutable. Every scheduled attribute/branch reads the latest grid,
  // including when an old callback runs after a shrink, rotation or fallback.
  @Builder
  mediaTile(slot: DrawnMediaSlot) {
    Stack() {
      // Ready static images have no placeholder/progress subtree. Pending
      // images still allow a mini/native fallback and progress at the same time.
      if (this.mediaOverlay(slot.index)) {
        if (this.imageSlot(slot.index)?.pixels !== undefined &&
          !this.imageSlot(slot.index)?.receiver.canDraw(this.imageSlot(slot.index)?.pixels, ImageFit.Cover)) {
          Image(this.imageSlot(slot.index)?.pixels).width((this.nativeTiles[slot.index]?.width ?? 0)).height((this.nativeTiles[slot.index]?.height ?? 0))
            .draggable(false).objectFit(ImageFit.Cover);
        } else if (this.imageSlot(slot.index)?.showMini(this.scroll.active)) {
          Image(this.imageSlot(slot.index)?.mini ?? '').width((this.nativeTiles[slot.index]?.width ?? 0)).height((this.nativeTiles[slot.index]?.height ?? 0))
            .draggable(false).objectFit(ImageFit.Cover).blur(MINI_PLACEHOLDER_BLUR);
        }
        if (this.sendState === 'sending') {
          LiveProgressRing({ fileId: (this.nativeTiles[slot.index]?.cell.isVideo ?? false) ? this.kind === 'single' ? this.group.head.videoFileId : (this.nativeTiles[slot.index]?.cell.videoFileId ?? 0)
            : (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0), initialPercent: 0, ringSize: Math.min(44, Math.min((this.nativeTiles[slot.index]?.width ?? 0), (this.nativeTiles[slot.index]?.height ?? 0)) * .3) });
        } else if (this.imageSlot(slot.index)?.path === '') {
          if (!(this.nativeTiles[slot.index]?.cell.isVideo ?? false) && ((this.nativeTiles[slot.index]?.cell.failed ?? false) || (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) === 0)) {
            Column({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor([Color.White]);
              Text($r('app.string.settings_retry')).fontSize(11).fontColor(Color.White);
            }.padding(7).backgroundColor('#80000000').borderRadius(18);
          } else if ((this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) !== 0 && !(this.nativeTiles[slot.index]?.cell.failed ?? false)) {
            LiveProgressRing({ fileId: (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0), initialPercent: this.kind === 'single' ? this.group.head.photoProgress : (this.nativeTiles[slot.index]?.cell.progress ?? 0),
              ringSize: Math.min(34, Math.min((this.nativeTiles[slot.index]?.width ?? 0), (this.nativeTiles[slot.index]?.height ?? 0)) * .4) });
          }
        }
      }
      if (this.kind === 'single' && (this.nativeTiles[slot.index]?.cell.isVideo ?? false)) {
        DrawnSingleMediaVideo({ msg: this.group.head, data: this.data, actions: this.actions,
          slot: this.media.slots[0], sendState: this.sendState, mediaWidth: (this.nativeTiles[slot.index]?.width ?? 0), mediaHeight: (this.nativeTiles[slot.index]?.height ?? 0),
          thumbReady: ((this.imageSlot(0)?.path ?? '') !== '' ||
            (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) === 0 || (this.nativeTiles[slot.index]?.cell.failed ?? false)) });
      } else if (((this.nativeTiles[slot.index]?.cell.isVideo ?? false) || (this.nativeTiles[slot.index]?.cell.isLive ?? false)) && this.mediaActivated(slot.index)) {
        DrawnAlbumVideo({ cell: this.media.slots[slot.index]?.content.cell, actions: this.actions, sendState: this.sendState,
          mediaWidth: this.nativeTiles[slot.index]?.width ?? 0, mediaHeight: this.nativeTiles[slot.index]?.height ?? 0,
          thumbReady: ((this.imageSlot(slot.index)?.path ?? '') !== '' ||
            (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) === 0 || (this.nativeTiles[slot.index]?.cell.failed ?? false)) });
      }
    }
    .attributeModifier(this.nativeAnchors.bind(slot.index, this.mediaFrames[slot.index]))
    .drawModifier(this.media.slots[slot.index]?.receiver);
  }

  @Builder
  canvasContent() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.kind !== 'text') {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.mediaSlots, (slot: DrawnMediaSlot) => {
            this.mediaTile(slot);
          }, (slot: DrawnMediaSlot): string => slot.key);
        }.width(this.plan?.grid.width ?? 0).height(this.plan?.grid.height ?? 0)
        .position({ x: this.plan?.grid.x ?? 0, y: this.plan?.grid.y ?? 0 })
        .borderRadius(this.gridRadii()).clip(true).hitTestBehavior(HitTestMode.None);
      }
      if ((this.plan?.caption?.source.links.length ?? 0) > 0 && this.plan?.caption?.source.targets.has(this.env.linkNavBusy)) {
        DrawnBusyLink({ plan: this.plan?.caption ?? null, url: this.env.linkNavBusy })
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 });
      }
      Row().width(this.plan?.width ?? 0).height(this.plan?.height ?? 0)
        .drawModifier(this.foreground.bind(this.plan, this.sendState, this.footerPaintKey))
        .hitTestBehavior(HitTestMode.None);
      if ((this.plan?.caption?.emojis.length ?? 0) > 0) {
        DrawnInlineEmojiLayer({ plan: this.plan?.caption ?? null, msg: this.group.captionMessage ?? this.group.head })
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 });
      }
      if ((this.plan?.quote?.mediaWidthPx ?? 0) > 0 || (this.plan?.chrome?.content.avatarCount ?? 0) > 0 ||
        (this.plan?.chrome?.reactions?.images.length ?? 0) > 0 || this.plan?.chrome?.reactions?.arrow) {
        DrawnChromeIslands({ plan: this.plan, msg: this.group.head, chatId: this.data.chatId,
          themeBubbleOut: this.data.themeBubbleOut });
      }
    }
    .attributeModifier(this.canvasAttributes.bind(this.plan?.width ?? 0, this.plan?.height ?? 0,
      1 + this.jumpFocus * JUMP_FOCUS_SCALE,
      this.group.head.isOutgoing ? '100%' : (this.plan?.bubbleX ?? 0),
      1 + this.jumpFocus * JUMP_FOCUS_BRIGHTNESS, this.canDragMessage() && this.allowBodyDrag))
    .drawModifier(this.painter.bind(this.plan, !this.env.scrollActive))
    .onTouch((e: TouchEvent): void => { this.touch(e); })
    .onClick((e: ClickEvent): void => { this.click(e); })
    .onDragStart((event: DragEvent): DragItemInfo => {
      // Reaction holds are handled before the system's 500ms drag recognizer.
      // Never export the message when the initial target was a reaction chip.
      if (!this.touchOnBody || this.claimed) { return {}; }
      this.dragGesture.claim(); this.draggingMessage = true; this.claimed = true;
      this.menuShown = false; this.foreground.press(null);
      return configureMessageDrag(event, this.data.chatId, this.group.head.id, messageDragType(this.group.head.contentType));
    })
    .onDragEnd((): void => { this.draggingMessage = false; })
    .bindContextMenu(this.menuShown, this.menu(), {
      offset: { x: this.menuOffset, y: 0 },
      preview: drawnLiveSurface(this.group, this.data) || menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp) ? MenuPreviewMode.NONE : MenuPreviewMode.IMAGE,
      previewAnimationOptions: { scale: [0.98, 1.035], transition: this.menuFx.preview() },
      borderRadius: 16, backgroundColor: Color.Transparent,
      backgroundBlurStyle: containerBlur('menu'), systemMaterial: overlayMaterial('menu'),
      transition: this.menuFx.menu(), mask: { color: '#52000000', backgroundBlurStyle: BlurStyle.BACKGROUND_THIN },
      modalMode: ModalMode.TARGET_WINDOW, hapticFeedbackMode: HapticFeedbackMode.AUTO,
      onDisappear: (): void => { this.menuShown = false; }
    });
  }

  build() {
    if (this.plan === null) {
      if (this.kind === 'text') {
        LegacyTextRow({ group: this.group, data: this.data, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      } else if (this.kind === 'single') {
        LegacySingleMediaBubble({ msg: this.group.head, group: this.group, data: this.data, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      } else {
        LegacyAlbumMessageBubble({ group: this.group, data: this.data, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      }
    } else {
      Column() {
        if (this.group.dateLabel !== '') {
          Text(this.group.dateLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 }).margin({ top: 5, bottom: 3 });
        }
        if (this.data.showUnreadDivider) {
          Row() {
            Divider().layoutWeight(1).strokeWidth(1).color(COLOR_TEXT_SECONDARY).opacity(.55);
            Text(this.data.dividerIsResume ? $r('app.string.mb_last_viewed_position') : $r('app.string.mb_unread'))
              .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium).margin({ left: 10, right: 10 });
            Divider().layoutWeight(1).strokeWidth(1).color(COLOR_TEXT_SECONDARY).opacity(.55);
          }.width('100%').height(26).padding({ left: 12, right: 12, bottom: 4 });
        }
        Row() {
          Stack({ alignContent: Alignment.TopStart }) {
            // Keep capture opacity separate from press opacity/scale and the
            // content's jump transform. The existing outer Stack hosts deletion;
            // no extra component + Stack are needed on every normal message.
            Row() {
              Row() { this.canvasContent(); }
                .attributeModifier(!this.deleteCaptureSupported || (this.plan?.caption?.source.links.length ?? 0) > 0
                  ? DRAWN_BUBBLE_PRESS_NONE : DRAWN_BUBBLE_PRESS);
            }.id(this.deleteNodeKey)
            .opacity(this.leaving > 0 && (!this.deleteCaptureSupported || this.capturedDeleteKey === this.deleteNodeKey) ? 0 : 1)
            .hitTestBehavior(this.leaving > 0 ? HitTestMode.None : HitTestMode.Default);
            if (this.leaving > 0 && this.deleteCaptureSupported) {
              ShatterDeleteOverlay({ nodeId: this.deleteNodeKey, particleBudget: this.actions.rowLeave.particleBudget(),
                onCaptured: this.leaveCapture.captured(),
                onFinish: this.leaveCapture.finished(this.group.head.rowId, this.actions.rowLeave) })
                .position({ x: 0, y: 0 }).hitTestBehavior(HitTestMode.None);
            }
            if ((this.plan?.avatar.width ?? 0) > 0) {
              Row().width(this.plan?.width ?? 0).height(this.plan?.height ?? 0)
                .drawModifier(this.avatarPainter.bind(this.plan, this.media)).hitTestBehavior(HitTestMode.None);
            }
            if ((this.plan?.avatar.width ?? 0) > 0 && this.nativeAvatar(this.avatarStateRevision)) {
              Image(this.media.avatarPixels).width(38).height(38).borderRadius(19).clip(true)
                .position({ x: this.plan?.avatar.x ?? 0, y: this.plan?.avatar.y ?? 0 })
                .draggable(false).objectFit(ImageFit.Cover).hitTestBehavior(HitTestMode.None);
            }
            if (this.avatarAnimated && (this.plan?.avatar.width ?? 0) > 0) {
              SenderAnimatedLayer({ senderId: this.group.head.senderId, senderIsUser: this.group.head.senderIsUser, avatarSize: 38 })
                .position({ x: this.plan?.avatar.x ?? 0, y: this.plan?.avatar.y ?? 0 });
            }
          }.width(this.plan?.width ?? 0).height(this.plan?.height ?? 0);
        }.width('100%').padding({ left: 4, right: 4, top: this.group.showSenderName ? 3 : 1,
          bottom: this.group.showAvatar ? 3 : 1 })
        .justifyContent(this.group.head.isOutgoing ? FlexAlign.End : FlexAlign.Start)
        .translate({ x: this.swipeX })
        .parallelGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((e: GestureEvent): void => { this.swipe(e.offsetX); })
          .onActionEnd((): void => { this.endSwipe(); }).onActionCancel((): void => { this.endSwipe(); }))
        .parallelGesture(LongPressGesture({ fingers: 1, repeat: false,
          duration: this.group.head.reactions.length > 0 ? 450 : 500 })
          .onAction((e: GestureEvent): void => { this.longPress(e); }))
        .onTouch((e: TouchEvent): void => { this.rowTouch(e); })
        .onClick((e: ClickEvent): void => {
          if (!this.claimed && !this.data.selectionActive && messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
            this.openMenu(this.rowToCanvasX(e.x, Number(e.target.area.width)));
          }
        });
        if (this.group.head.inlineButtons.length > 0) {
          BubbleInlineKeyboard({ msg: this.group.head, group: this.group, data: this.data, actions: this.actions,
            context: this.keyboardState(), drawnWidth: this.keyboardWidth(),
            drawnLeft: 4 + (this.plan?.bubbleX ?? 0) + (this.group.head.isOutgoing ? 0 :
              this.keyboardGutter()),
            drawnRight: 4 + (this.group.head.isOutgoing ? this.keyboardGutter() : 0) });
        }
      }.width('100%')
        .onVisibleAreaApproximateChange({ ratios: [0], expectedUpdateInterval: 16 },
          this.kind === 'album' ? this.mediaVisibility() : undefined)
        .transition(this.data.animateIn
        ? TransitionEffect.translate({ y: 16 }).combine(TransitionEffect.OPACITY)
          .animation({ duration: animationDurationFor(this.env.chatEffects && this.env.messageEffects &&
            !this.env.powerSaving, scrollActiveNow(), 220), curve: Curve.FastOutSlowIn })
        : TransitionEffect.IDENTITY);
    }
  }
}
