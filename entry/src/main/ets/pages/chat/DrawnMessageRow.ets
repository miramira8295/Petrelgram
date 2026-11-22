import { drawnPlacementKey } from '../../util/drawnPlacementKey';
import { DrawnMenuMedia, DrawnMenuSticker, DrawnMenuPaintState } from './DrawnMenuPreview';
import { StaticMiniThumbnail } from '../common/StaticMiniThumbnail';
import { documentCardFor } from './DrawnDocumentCardLayout';
import { DrawnChecklistMessage } from './DrawnChecklistMessage';
import { DrawnMediaRetry } from './DrawnMediaRetry';
import { StickerMessageBubble } from './StickerMessageBubble';
import { DrawnGiveawayMessage } from './DrawnGiveawayMessage';
import { DrawnGiftMessage } from './DrawnGiftMessage';
import { DrawnPaidMediaMessage } from './DrawnPaidMediaMessage';
import { DrawnGameMessage } from './DrawnGameMessage';
import { DrawnDiceMessage } from './DrawnDiceMessage';
import { DrawnVideoNoteMessage } from './DrawnVideoNoteMessage';
import { DrawnPollMessage } from './DrawnPollMessage';
import { DrawnLocationMessage } from './DrawnLocationMessage';
import { DrawnContactMessage } from './DrawnContactMessage';
import { DrawnVoiceMessage } from './DrawnVoiceMessage';
import { DrawnAudioMessage } from './DrawnAudioMessage';
import { MessageBubble } from './MessageBubble';
import { DrawnFileMessage } from './DrawnFileMessage';
import { DrawnAlbumTransition } from './DrawnAlbumTransition';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { DrawnDocumentVideo } from './DrawnDocumentVideo';
import { DrawnDocumentEmbed } from './DrawnDocumentEmbed';
import { DrawnDocumentArticleImage } from './DrawnDocumentArticleImage';
import { DocumentSwitchInline } from '../../services/DocumentSwitchInline';
import { str } from '../../util/strings';
import { DocumentLoginUrl, DocumentLoginPrompt } from '../../services/DocumentLoginUrl';
import { documentAnchorName, expandDocumentAnchor } from '../../util/drawnDocumentAnchors';
import { DrawnDocumentNote } from './DrawnDocumentNote';
import { DrawnRichSource } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentPostAuthor } from './DrawnDocumentPostAuthor';
import { DrawnDocumentAudio } from './DrawnDocumentAudio';
import { DrawnDocumentVoice } from './DrawnDocumentVoice';
import { DrawnDocumentFile } from './DrawnDocumentFile';
import { DrawnDocumentMap } from './DrawnDocumentMap';
import { DrawnDocumentWidget, DrawnDocumentWidgetPlacement } from '../../util/drawnDocumentWidget';
import { DrawnInlineIconLayer } from './DrawnInlineIconLayer';
import { DrawnDocumentGallery } from './DrawnDocumentGallery';
import { DrawnDocumentMedia } from '../../util/drawnDocumentMedia';
import { DrawnDocumentMediaIsland } from './DrawnDocumentMediaIsland';
import { DocumentMediaSession } from '../../util/documentMediaViewer';
import { stackOf } from '../../util/navStacks';
import { showToast } from '../../util/toast';
import { DrawnMathLayer } from './DrawnMathLayer';
import { DrawnRichLink } from '../../util/drawnRichTextPolicy';
import { DrawnTableIsland } from './DrawnTableIsland';
import { DrawnTablePlacement, DrawnDocumentMediaPlacement } from './DrawnRichTextLayout';
import { TdObject } from '../../tdkit/TdTypes';
import { DrawnGlassBackground } from './DrawnGlassBackground';
import { COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT } from '../../util/theme';
import { DrawnRowAccessibility } from './DrawnRowAccessibility';
import { DrawnPreviewImage } from './DrawnPreviewImage';
import { linkPreviewPresentation } from '../../util/linkPreview';
import { DrawnRowInteraction } from './DrawnRowInteraction';
import { UIContext } from '@kit.ArkUI';
import { DrawnPreparedAlbum, DrawnAlbumPublication } from './DrawnPreparedAlbum';
import { drawnRowChromeReason } from '../../util/drawnRowChromePolicy';
import { DrawnAlbumCanvas } from './DrawnAlbumCanvas';
import { DrawnMediaAnchorPool, DrawnCanvasAttributes } from './DrawnNativeAttributes';
import { drawnPainterReserve } from './DrawnPainterReserve';
import { DrawnRowLayoutEngine, takeDrawnWarmLayout } from './DrawnLayoutWarmCache';
import { DrawnLayoutRetention, takeDrawnRecycledLayout } from './DrawnRecycledLayouts';
import { DrawnRouteReason, DrawnRouteTracker } from '../../util/drawnRouteMetrics';
import { DrawnInvalidation, DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { DrawnMediaFrame, DrawnMediaFrames, drawnAlbumTransitionFrame } from './DrawnMediaFrames';
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
import { drawnAlbumEligible, albumRectContains } from '../../util/drawnAlbumPolicy';
import { DrawnRichHit } from '../../util/drawnRichTextPolicy';
import { drawnTailGutter } from '../../util/drawnPlainTextPolicy';
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

interface DrawnSpoilerOwner { rowId: number; chatId: number; content: string; }

@ComponentV2
export struct DrawnMessageRow {
  @Param kind: 'album' | 'text' | 'single' = 'album';
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param preparedAlbum: DrawnPreparedAlbum | null = null;
  // Stable channel: the staged parent owns admission, the child consumes the
  // packet atomically. Parent builders never unpack the observed payload.
  @Param publication: DrawnAlbumPublication | undefined = undefined;
  @Computed
  private get rowGroup(): AlbumGroup { return this.publication?.packet?.group ?? this.group; }
  @Computed
  private get rowData(): MessageBubbleRenderData { return this.publication?.packet?.data ?? this.data; }
  @Computed
  private get rowPreparedAlbum(): DrawnPreparedAlbum | null { return this.publication?.packet ?? this.preparedAlbum; }

  @Param presentationActive: boolean = true;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  // A staged album host can own the native date header above this body.
  @Param dateInHost: boolean = false;
  // V2 resets these initializers after the current @Param values and before
  // @Computed plan. Read fixed-count channel snapshots here so reuse does not
  // lay out blank metadata first and repeat layout after attach(). No listeners
  // or IO here; attach still subscribes and catches changes since this snapshot.
  @Local private sendState: string = sendStateFor(this.rowGroup.head.rowId) || this.rowGroup.head.sendState;
  @Local private views: string = viewCountLabelFor(this.rowData.chatId, this.rowGroup.head.id);
  @Local private role: string = this.rowGroup.head.senderTag ||
    (this.rowData.isGroup && !this.rowGroup.head.isOutgoing && this.rowGroup.showSenderName
      ? senderRoleFor(senderRoleKey(this.rowData.chatId, this.rowGroup.head.senderId)) : '');
  @Local private revealedSpoiler: DrawnSpoilerOwner | null = null;
  private rowSpoilersRevealed(): boolean {
    const owner = this.revealedSpoiler;
    return !!owner && owner.rowId === this.rowGroup.head.rowId && owner.chatId === this.rowData.chatId &&
      owner.content === (this.kind === 'album' ? this.rowGroup.caption : this.rowGroup.head.text);
  }
  private revealDrawnSpoilers(): void {
    this.revealedSpoiler = { rowId: this.rowGroup.head.rowId, chatId: this.rowData.chatId,
      content: this.kind === 'album' ? this.rowGroup.caption : this.rowGroup.head.text };
  }
  @Local private expandedBlockOffsets: ReadonlyArray<number> | undefined = undefined;
  private expandedBlockChat: number = 0;
  private expandedBlockRow: number = 0;
  @Local private mathRevision: number = 0;
  private emptyWidgets: DrawnDocumentWidgetPlacement[] = [];
  private emptyDocumentMedia: DrawnDocumentMediaPlacement[] = [];
  @Local private noteShown: boolean = false;
  @Local private noteSource: DrawnRichSource | null = null;
  private loginUrl: DocumentLoginUrl | null = null;
  private loginOwner: TdObject[] | undefined;
  private switchInline: DocumentSwitchInline | null = null;
  private loginRow: string = '';
  private documentOwner: string = '';
  private documentBlocks: TdObject[] | undefined;
  private pendingAnchor: string | null = null;
  private pendingDocument: TdObject[] | undefined;
  private documentNodeId(): string { return `drawn-doc-${this.rowData.chatId}-${this.rowGroup.head.rowId}`; }
  private openDocumentLink(url: string): boolean {
    const name = documentAnchorName(url), source = this.plan?.caption?.source;
    if (name === null || source?.anchorPaths === undefined) { return false; }
    if (!this.presentationReady()) { return true; }
    const note = source.footnotes?.get(name);
    this.documentOwner = this.documentNodeId(); this.documentBlocks = this.rowGroup.head.richBlocks;
    if (note !== undefined) { this.noteSource = note; this.noteShown = true; return true; }
    if (name !== '' && !source.anchorPaths.has(name)) { return true; }
    this.noteShown = false;
    const previous = this.rowExpandedBlocks() ?? [];
    const branch = source.anchorPaths.get(name) ?? null;
    const next = branch === null ? previous : expandDocumentAnchor(branch, previous);
    const changed = next !== previous && (next.length !== previous.length || next.some((offset: number, index: number): boolean => offset !== previous[index]));
    this.pendingAnchor = name; this.pendingDocument = this.rowGroup.head.richBlocks;
    if (changed) {
      this.expandedBlockChat = this.rowData.chatId; this.expandedBlockRow = this.rowGroup.head.rowId;
      this.expandedBlockText = this.kind === 'album' ? this.rowGroup.caption : this.rowGroup.head.text;
      this.expandedBlockDocument = this.rowGroup.head.richBlocks; this.expandedBlockOffsets = next;
    } else { this.flushDocumentAnchor(); }
    return true;
  }
  private flushDocumentAnchor(): void {
    const name = this.pendingAnchor;
    if (name === null) { return; }
    this.pendingAnchor = null;
    if (!this.presentationReady() || this.documentOwner !== this.documentNodeId() || this.pendingDocument !== this.rowGroup.head.richBlocks) { return; }
    const y = name === '' ? 0 : this.plan?.caption?.anchors.get(name);
    if (y === undefined || this.actions.onDocumentAnchor === undefined) { return; }
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(this.documentNodeId());
      if (rect.size.height > 0) { this.actions.onDocumentAnchor(this.getUIContext().px2vp(rect.windowOffset.y) + (this.plan?.captionY ?? 0) + y); }
    } catch (_) { /* A recycled native node is no longer a scroll target. */ }
  }
  @Builder private documentNote() {
    DrawnDocumentNote({ source: this.noteSource, msg: this.rowGroup.head, maxWidthVp: Math.max(120, this.env.screenWidthVp - 32),
      onLinkTap: (link: DrawnRichLink): void => {
        if (this.documentOwner === this.documentNodeId() && this.documentBlocks === this.rowGroup.head.richBlocks && !this.openDocumentLink(link.url)) { this.actions.onLinkTap(link.url, link.hidesUrl); }
      } });
  }
  private emptyTables: DrawnTablePlacement[] = [];
  private expandedBlockText: string = '';
  private expandedBlockDocument: TdObject[] | undefined = undefined;
  private rowExpandedBlocks(): ReadonlyArray<number> | undefined {
    const offsets = this.expandedBlockOffsets;
    return this.expandedBlockChat === this.rowData.chatId && this.expandedBlockRow === this.rowGroup.head.rowId && this.expandedBlockDocument === this.rowGroup.head.richBlocks &&
      this.expandedBlockText === (this.kind === 'album' ? this.rowGroup.caption : this.rowGroup.head.text) ? offsets : undefined;
  }
  private toggleDrawnQuote(offset: number): void {
    const offsets = this.rowExpandedBlocks() ?? [];
    const next: number[] = [];
    let found: boolean = false;
    for (const item of offsets) { if (item === offset) { found = true; } else { next.push(item); } }
    if (!found) { next.push(offset); }
    this.expandedBlockChat = this.rowData.chatId; this.expandedBlockRow = this.rowGroup.head.rowId;
    this.expandedBlockText = this.kind === 'album' ? this.rowGroup.caption : this.rowGroup.head.text;
    this.expandedBlockDocument = this.rowGroup.head.richBlocks;
    this.expandedBlockOffsets = next;
  }
  @Local private translation: TranslationStatus | null = translationStatusFor(this.rowGroup.head.id);
  // A retained staged child receives new params without V2 reuse/reset. Keep
  // the metadata owner explicit so plan never applies the previous row's
  // snapshots to a newly published prepared layout. Fixed fields only, O(1).
  @Local private metadataOwner: string = this.metadataKey();
  private metadataKey(): string {
    const m = this.rowGroup.head;
    return `${this.rowData.chatId}:${m.rowId}:${m.id}:${m.senderId}:${m.senderTag}:${this.rowData.isGroup}:${m.isOutgoing}:${this.rowGroup.showSenderName}`;
  }
  @Local private avatarAnimated: boolean = senderHasAnimatedPhoto(this.rowGroup.head.senderId, this.rowGroup.head.senderIsUser);
  // Ordinary, stable owner; each getter still reads an individual @Trace.
  // No @Monitor targets this reference. Metadata above must remain seeded
  // before plan is recalculated by V2; interaction reset cannot replace that.
  private interaction: DrawnRowInteraction = new DrawnRowInteraction();
  private get avatarStateRevision(): number { return this.interaction.avatarRevision; }
  private set avatarStateRevision(value: number) {
    if (this.interaction.avatarRevision !== value) { this.interaction.avatarRevision = value; }
  }
  private get menuShown(): boolean { return this.interaction.menuShown; }
  private set menuShown(value: boolean) {
    if (this.interaction.menuShown !== value) { this.interaction.menuShown = value; }
  }
  private get swipeX(): number { return this.interaction.swipeX; }
  private set swipeX(value: number) {
    if (this.interaction.swipeX !== value) { this.interaction.swipeX = value; }
  }
  private get capturedDeleteKey(): string { return this.interaction.capturedDeleteKey; }
  private set capturedDeleteKey(value: string) {
    if (this.interaction.capturedDeleteKey !== value) { this.interaction.capturedDeleteKey = value; }
  }
  private get allowBodyDrag(): boolean { return this.interaction.allowBodyDrag; }
  private set allowBodyDrag(value: boolean) {
    if (this.interaction.allowBodyDrag !== value) { this.interaction.allowBodyDrag = value; }
  }
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
  private albumCanvas: DrawnAlbumCanvas = new DrawnAlbumCanvas();
  private retainedCanvasMode: boolean = false;
  // Physical component/window scope, retained across row recycling only.
  // Stable identity lets media's existing O(1) duplicate-bind guard work.
  private rowUi: UIContext | null = null;
  private rowContext(): UIContext {
    if (!this.rowUi) { this.rowUi = this.getUIContext(); }
    return this.rowUi;
  }
  private media: DrawnMediaController = new DrawnMediaController(
    (): void => { this.avatarStateRevision++; }, (): void => {
      drawnStageMetrics.invalidated(DrawnInvalidation.AvatarImage); this.avatarPainter.invalidate();
      const m = this.rowGroup.head;
      const animated = senderHasAnimatedPhoto(m.senderId, m.senderIsUser);
      if (this.avatarAnimated !== animated) { this.avatarAnimated = animated; }
    }, (): void => { this.albumCanvas.imageChanged(); });
  private channels: DrawnBubbleController = new DrawnBubbleController({
    send: (value: string): void => { if (this.sendState !== value) { this.sendState = value; } },
    views: (value: string): void => { if (this.views !== value) { this.views = value; } },
    role: (value: string): void => { if (this.role !== value) { this.role = value; } },
    translation: (value: TranslationStatus | null): void => {
      if (this.translation !== value) { this.translation = value; pinForTranslationGrowth(this.rowData.chatId); }
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
    this.routeTracker.record(this.rowData.chatId, this.rowGroup.head.rowId, reason);
  }
  private rejectRoute(reason: DrawnRouteReason): null { this.recordRoute(reason); return null; }
  private keyboardContext: MessageBubbleContext | null = null;
  private keyboardState(): MessageBubbleContext {
    if (this.keyboardContext === null) { this.keyboardContext = new MessageBubbleContext(); }
    return this.keyboardContext;
  }
  private keyboardGutter(): number { return this.kind === 'text' ? drawnTailGutter(this.rowGroup.showAvatar) : 7; }
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
    const eligible = this.kind === 'text' ? drawnTextRowEligible(this.rowGroup, this.rowData, this.env.bubbleMaterialOn, this.a11y.active)
      : this.kind === 'single' ? drawnSingleMediaEligible(this.rowGroup, this.env.bubbleMaterialOn, this.a11y.active)
      : drawnAlbumEligible(this.rowGroup, this.rowData, this.env.bubbleMaterialOn, this.a11y.active);
    if (this.env.drawnEnabled === false) { return this.rejectRoute(DrawnRouteReason.Disabled); }
    if (this.kind === 'text' ? this.env.drawnText === false : this.kind === 'single' ? this.env.drawnSingle === false : this.env.drawnAlbum === false) { return this.rejectRoute(DrawnRouteReason.Disabled); }
    // Match the former caption gate without building a paragraph just to discard
    // it. Empty media rows remain eligible when a body renderer is disabled.
    const bodyText = this.kind === 'album' ? this.rowGroup.caption : this.rowGroup.head.text;
    const structuredBody = this.kind === 'text' && (this.rowGroup.head.contentType === 'richMessage' || this.rowGroup.head.contentType === 'file' || this.rowGroup.head.contentType === 'audio' || this.rowGroup.head.contentType === 'voice' || this.rowGroup.head.contentType === 'contact' || this.rowGroup.head.contentType === 'location' || this.rowGroup.head.contentType === 'venue' || this.rowGroup.head.contentType === 'checklist' || this.rowGroup.head.contentType === 'poll' || this.rowGroup.head.contentType === 'videoNote' || this.rowGroup.head.contentType === 'dice' || this.rowGroup.head.contentType === 'game' || this.rowGroup.head.contentType === 'paidMedia' || this.rowGroup.head.contentType === 'gift' || this.rowGroup.head.contentType === 'giveaway' || this.rowGroup.head.contentType === 'sticker' || this.rowGroup.head.contentType === 'emoji' || this.rowGroup.head.contentType === 'customEmoji');
    if ((bodyText !== '' || structuredBody) && (!structuredBody && this.rowData.lightweightPlainText ? this.env.drawnPlain === false : this.env.drawnRich === false)) { return this.rejectRoute(DrawnRouteReason.BodyDisabled); }
    if (!eligible) { return this.rejectRoute(DrawnRouteReason.Policy); }
    // Read Local values even during handoff to retain async dependencies.
    // Before attach commits the new owner, use current channel snapshots;
    // do not mutate the prepared packet with stale views/role/translation.
    const currentOwner = this.metadataOwner === this.metadataKey();
    const localViews = this.views, localRole = this.role, localTranslation = this.translation;
    const views = currentOwner ? localViews : viewCountLabelFor(this.rowData.chatId, this.rowGroup.head.id);
    const role = currentOwner ? localRole : (this.rowGroup.head.senderTag ||
      (this.rowData.isGroup && !this.rowGroup.head.isOutgoing && this.rowGroup.showSenderName
        ? senderRoleFor(senderRoleKey(this.rowData.chatId, this.rowGroup.head.senderId)) : ''));
    const translation = currentOwner ? localTranslation : translationStatusFor(this.rowGroup.head.id);
    const m = this.rowGroup.head;
    if (this.kind === 'album' && this.rowPreparedAlbum?.sameInput(this.rowGroup, this.rowData) &&
      (this.presentationActive === false || this.rowPreparedAlbum.matches(this.rowGroup, this.rowData, {
      radius: this.env.bubbleRadius, fontSize: this.env.msgTextSize, environment, textEnvironment,
      mathRevision: this.mathRevision, translationStatus: translation, replaceTranslation: this.env.translateReplaceOriginal, spoilersRevealed: this.rowSpoilersRevealed(), expandedBlocks: this.rowExpandedBlocks(), role: m.senderTag || role, views
    }))) {
      drawnStageMetrics.markRoute(this.presentationActive === false ? 'PG/row-plan-held' : 'PG/row-plan-hit');
      drawnStageMetrics.skip(DrawnStage.Layout);
      this.recordRoute(DrawnRouteReason.Drawn);
      return this.rowPreparedAlbum.plan;
    }
    const chromeReason = drawnRowChromeReason(this.rowGroup, this.rowData, role);
    if (chromeReason !== DrawnRouteReason.Drawn) { return this.rejectRoute(chromeReason); }
    const traced = drawnStageMetrics.begin(DrawnStage.Layout);
    try {
      // Footer/role/theme arrivals keep using this physical host's engine;
      // handing off a plan must not make the first views update reshape text.
      if (this.kind === 'album' && this.rowPreparedAlbum?.sameInput(this.rowGroup, this.rowData) && this.rowPreparedAlbum.engine !== null) {
        drawnStageMetrics.markRoute('PG/row-plan-refresh');
        const p = this.rowPreparedAlbum.refresh({ radius: this.env.bubbleRadius, fontSize: this.env.msgTextSize,
          environment, textEnvironment, mathRevision: this.mathRevision, translationStatus: translation, replaceTranslation: this.env.translateReplaceOriginal, spoilersRevealed: this.rowSpoilersRevealed(), expandedBlocks: this.rowExpandedBlocks(), role: m.senderTag || role, views });
        this.recordRoute(p === null ? this.rowPreparedAlbum.engine.failureReason : DrawnRouteReason.Drawn);
        return p;
      }
      const ui = this.rowContext();
      if (this.kind === 'text' && this.textLayouts === null) {
        this.textLayouts = takeDrawnRecycledLayout(this.rowData.chatId, m.rowId, 'text') ??
          takeDrawnWarmLayout(this.rowData.chatId, m.id, 'text') ?? new DrawnTextLayouts();
      }
      if (this.kind === 'album' && this.albumLayouts === null) {
        this.albumLayouts = takeDrawnRecycledLayout(this.rowData.chatId, m.rowId, 'album') ??
          takeDrawnWarmLayout(this.rowData.chatId, m.id, 'album') ?? new DrawnAlbumLayouts();
      }
      if (this.kind === 'single' && this.singleLayouts === null) {
        this.singleLayouts = takeDrawnRecycledLayout(this.rowData.chatId, m.rowId, 'single') ??
          takeDrawnWarmLayout(this.rowData.chatId, m.id, 'single') ?? new DrawnSingleMediaLayouts();
      }
      const layouts = this.kind === 'text' ? this.textLayouts : this.kind === 'single' ? this.singleLayouts : this.albumLayouts;
      if (layouts !== null) { this.layoutRetention.remember(this.rowGroup, this.rowData, this.kind, layouts); }
      const p = layouts?.prepare(ui, this.rowGroup, this.rowData, {
        radius: this.env.bubbleRadius, fontSize: this.env.msgTextSize, environment, textEnvironment,
        pollExpired: this.pollGeometryExpired, mathRevision: this.mathRevision, translationStatus: translation, replaceTranslation: this.env.translateReplaceOriginal, spoilersRevealed: this.rowSpoilersRevealed(), expandedBlocks: this.rowExpandedBlocks(), role: m.senderTag || role, views
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

  // The staged packet and the child's visibility Param arrive in separate
  // updates. Bind the admitted owner as soon as its packet is published: a
  // false -> true visibility reset may reseed Monitor without a callback.
  // Never bind the retained packet while it still belongs to the previous row.
  private presentationReady(): boolean {
    if (this.publication === undefined) { return this.presentationActive !== false; }
    const packet = this.publication.packet;
    return this.publication.hostActive && packet !== null &&
      packet.group.head.rowId === this.group.head.rowId && packet.data.chatId === this.data.chatId;
  }

  private attach(): void {
    if (this.loginRow !== this.documentNodeId() || this.loginOwner !== this.rowGroup.head.richBlocks) { this.loginUrl?.cancel(); this.switchInline?.cancel(); }
    if (this.documentOwner !== this.documentNodeId() || this.documentBlocks !== this.rowGroup.head.richBlocks) { this.noteShown = false; this.noteSource = null; this.pendingAnchor = null; }
    // Packet monitors may run after recursive V2 reset has reseeded the epoch.
    // The explicit live host is authoritative for this retained child.
    if (this.publication?.hostActive === true) { this.active = true; }
    if (!this.active || !this.presentationReady()) { return; }
    if (this.rowGroup.head.contentType === 'richMessage' && this.rowGroup.head.richIsFull === false) {
      this.actions.onRichMessageLoadFull(this.rowGroup.head.id);
    }
    this.syncMediaVisibility();
    const environment = this.roleEnvironment;
    if (this.attachedGroup === this.rowGroup && this.attachedData === this.rowData &&
      this.attachedEnvironment === environment) {
      drawnStageMetrics.skip(DrawnStage.Attach); return;
    }
    // A failed A → B bind must not leave an A cache hit over partial B state.
    this.attachedGroup = null; this.attachedData = null;
    const traced = drawnStageMetrics.begin(DrawnStage.Attach);
    try {
      const m = this.rowGroup.head;
      const identity = `${this.rowData.chatId}:${m.rowId}`;
      if (identity !== this.inputIdentity) {
        this.canvasTransition?.cancel();
        this.inputIdentity = identity; this.touchPlan = null; this.touchReaction = null; this.touchLink = null;
        this.touchRowId = 0; this.touchChatId = 0; this.foreground.press(null);
      }
      // The same sender can gain/lose an animated photo; identity-only memoization
      // would miss store updates. This is one O(1) lookup, with no network request.
      this.avatarAnimated = senderHasAnimatedPhoto(m.senderId, m.senderIsUser);
      this.channels.attach(this.rowData.chatId, m, this.rowData.isGroup && !m.isOutgoing && this.rowGroup.showSenderName);
      const metadataOwner = this.metadataKey();
      if (this.metadataOwner !== metadataOwner) { this.metadataOwner = metadataOwner; }
      // Commit only after successful attachment. Channels deliver later status,
      // translation and avatar changes independently of these input snapshots.
      this.attachedGroup = this.rowGroup; this.attachedData = this.rowData;
      this.attachedEnvironment = environment;
    } finally { drawnStageMetrics.end(traced); }
  }
  private syncMedia(): void {
    if (!this.active || !this.presentationReady()) { return; }
    const p = this.plan;
    if (p === null) { this.albumCanvas.reset(); this.media.recycle(); }
    else {
      const ui = this.rowContext();
      this.media.prepare(ui, p, this.rowGroup, this.kind === 'album');
      this.albumCanvas.bind(ui, p.nativeTiles, this.media.slots, p.density, this.albumCanvasEnabled, this.sendState === 'sending', `${this.rowData.chatId}:${this.rowGroup.head.rowId}`);
    }
  }
  @Computed
  private get albumCanvasEnabled(): boolean {
    return this.kind === 'album' && this.env.drawnAlbumCanvas !== false;
  }
  @Computed
  private get publicationActivationEpoch(): number { return this.publication?.activationEpoch ?? 0; }
  @Monitor('publicationActivationEpoch')
  private publicationActivated(): void {
    if (this.publication?.hostActive !== true) { return; }
    // Do not rely on a retained descendant receiving aboutToReuse. The host
    // explicitly resumes it; pending presentation still blocks old bindings.
    this.active = true;
    this.attach(); this.syncMedia(); this.syncDeleteCapture();
  }
  @Monitor('presentationActive')
  private presentationChanged(): void {
    if (this.presentationReady()) { this.attach(); this.syncMedia(); this.syncDeleteCapture(); }
    else { this.channels.detach(); }
  }
  @Computed
  private get mediaSending(): boolean { return this.sendState === 'sending'; }
  @Monitor('albumCanvasEnabled', 'mediaSending')
  private albumCanvasPolicyChanged(): void { this.syncMedia(); }
  @Computed
  private get roleEnvironment(): string { return `${this.env.langEpoch}:${this.env.bubbleMaterialOn}`; }
  @Monitor('roleEnvironment')
  private roleEnvironmentChanged(): void { this.attach(); }
  @Monitor('rowGroup', 'rowData')
  private inputChanged(): void {
    const traced = drawnStageMetrics.begin(DrawnStage.RowInput);
    try {
      this.attach();
      // Cached geometry may retain identity across sender/path updates. Unchanged
      // tile arrays skip image binding entirely; avatar refresh is constant time.
      this.syncMedia();
    } finally { drawnStageMetrics.end(traced); }
  }
  @Computed
  private get deleteNodeKey(): string { return `dissolve-delete-message-${this.rowData.chatId}-${this.rowGroup.head.rowId}`; }
  @Computed
  private get deleteCaptureSupported(): boolean { return !drawnLiveSurface(this.rowGroup, this.rowData, this.actions.playback !== undefined); }
  @Monitor('deleteNodeKey', 'leaving', 'deleteCaptureSupported', 'actions')
  private syncDeleteCapture(): void {
    if (!this.active || !this.presentationReady() || this.plan === null) { this.leaveCapture.reset(); return; }
    this.leaveCapture.bind(this.deleteNodeKey, this.rowGroup.head.rowId, this.leaving,
      this.deleteCaptureSupported, this.actions.rowLeave);
  }
  @Monitor('plan')
  private layoutChanged(): void {
    const traced = drawnStageMetrics.begin(DrawnStage.RowLayoutChanged);
    try { this.syncMedia(); this.syncDeleteCapture(); }
    finally { drawnStageMetrics.end(traced); }
  }
  aboutToAppear(): void { this.active = true; this.attach(); this.syncMedia(); this.syncDeleteCapture(); }
  aboutToRecycle(): void {
    this.menuPaintState = null;
    this.canvasTransition?.cancel();
    this.loginUrl?.cancel(); this.switchInline?.cancel();
    this.noteShown = false; this.noteSource = null; this.pendingAnchor = null;
    // A staged child keeps its physical branch while hidden. Releasing pixels
    // must not temporarily replace one canvas with six native tiles on reuse.
    if (this.presentationActive !== false) { this.retainedCanvasMode = this.albumCanvas.state.ready; }
    this.layoutRetention.release();
    this.textLayouts = null; this.albumLayouts = null; this.singleLayouts = null;
    this.mediaVisibilityEpoch++; this.mediaVisibilityKey = '';
    this.routeTracker?.reset();
    this.attachedGroup = null; this.attachedData = null; this.attachedEnvironment = '';
    this.inputIdentity = '';
    this.leaveCapture.reset();
    this.interaction.reset();
    this.dragGesture.reset(); this.draggingMessage = false; this.touchOnBody = false;
    this.active = false; this.channels.detach(); this.albumCanvas.reset(); this.media.recycle();
    this.touchRowId = 0; this.touchChatId = 0;
    this.claimed = false; this.touchLink = null; this.touchPlan = null; this.foreground.press(null);
    this.touchReaction = null;
  }
  aboutToReuse(): void {
    const traced = drawnStageMetrics.begin(DrawnStage.RowReuse);
    try {
      this.interaction.reset();
      this.dragGesture.reset(); this.draggingMessage = false; this.touchOnBody = false;
      this.touchRowId = 0; this.touchChatId = 0; this.touchPlan = null; this.touchLink = null;
      this.touchReaction = null;
      this.claimed = false; this.edge = false; this.menuOffset = 0;
      this.active = true; this.attach(); this.syncMedia(); this.syncDeleteCapture();
    } finally { drawnStageMetrics.end(traced); }
  }
  aboutToDisappear(): void { this.aboutToRecycle(); this.media.dispose(); this.rowUi = null; }

  private linkAt(x: number, y: number): DrawnRichHit | null {
    const p = this.plan;
    return p?.caption?.hitIndex.find(x - p.captionX, y - p.captionY) ?? null;
  }
  private reactionAt(x: number, y: number): DrawnReactionChip | null {
    const c = this.plan?.chrome;
    return c?.reactions?.hit(x - c.reactionsX, y - c.reactionsY) ?? null;
  }
  private click(event: ClickEvent, hitX: number = event.x, hitY: number = event.y, semantic: boolean = false): void {
    const p = this.plan;
    if (this.claimed || p === null || (!semantic && event.source === SourceType.TouchScreen &&
      (this.touchRowId !== this.rowGroup.head.rowId || this.touchChatId !== this.rowData.chatId))) {
      return;
    }
    const m = this.rowGroup.head;
    if (p.avatar.width > 0 && albumRectContains(p.avatar, hitX, hitY)) {
      this.actions.onAvatarTap(m.senderId, m.senderIsUser);
      return;
    }
    for (const tile of p.tiles) {
      if (albumRectContains(tile, hitX, hitY)) {
        if (this.rowData.selectionActive) { this.actions.onToggleSelectedMessage(tile.cell.messageId); }
        else if (tile.cell.failed && (this.kind === 'single' ? m.photoPath === ''
          : this.imageSlot(tile.cell.idx)?.path === '') && tile.cell.thumbFileId !== 0) {
          this.actions.onSpecialPhotoRetry(tile.cell.messageId);
        } else if (this.kind === 'single' && m.isAnimation) {
          if (drawnAnimationPlaying(m, this.rowData, this.env, true)) { this.openMenu(hitX); }
          else { this.actions.onAnimationTap(m.id, false); }
        } else if (this.albumCanvas.state.ready) {
          this.openCanvasMedia(tile, event);
        } else { this.actions.onMediaTap(tile.cell.messageId, event.windowX, event.windowY); }
        return;
      }
    }

    if (this.rowData.selectionActive) { return; }
    const chrome = p.chrome;
    const reaction = this.reactionAt(hitX, hitY);
    if (reaction !== null) {
      if (!semantic && event.source === SourceType.TouchScreen && (this.touchPlan !== p || this.touchReaction !== reaction)) { return; }
      this.foreground.press(null);
      if (reaction.reaction === null) {
        this.actions.onShowReactorsList(m.id, `reactors_anchor_${this.rowData.chatId}_${m.id}`);
      } else if (reaction.reaction.isPaid) { this.actions.onShowReactors(m.id, reaction.key); }
      else { this.actions.onSetReaction(m.id, reaction.key, reaction.reaction.isChosen); }
      return;
    }
    if (chrome !== null && chrome.content.forward !== null && albumRectContains(chrome.forwardRect, hitX, hitY)) {
      if (!semantic && event.source === SourceType.TouchScreen && this.touchPlan !== p) { return; }
      if (m.forwardOriginChatId !== 0 || m.forwardOriginUserId !== 0) {
        this.actions.onForwardTap(m.forwardOriginChatId, m.forwardOriginMsgId, m.forwardOriginUserId);
      }
      return;
    }
    if (chrome !== null && chrome.content.comments !== null && albumRectContains(chrome.commentsRect, hitX, hitY)) {
      if (semantic || event.source !== SourceType.TouchScreen || this.touchPlan === p) { this.actions.onCommentTap(m.id); }
      return;
    }
    if (p.quote !== null && albumRectContains(p.quoteRect, hitX, hitY)) {
      this.actions.onReplyTap(m.replyToMessageId, m.id); return;
    }
    const link = this.linkAt(hitX, hitY);
    if (link !== null) {
      if (semantic || event.source !== SourceType.TouchScreen || (this.touchPlan === p && this.touchLink === link)) {
        this.foreground.press(null);
        if (link.link.action === 'rich-task-toggle' && link.link.taskId !== undefined) {
          this.actions.onRichTaskToggle(m.id, link.link.taskId, link.link.taskChecked !== true);
        } else if (link.link.action === 'web-preview') {
          if (m.linkPhotoFailed) { this.actions.onLinkPreviewRetry(m.id); }
          else if (linkPreviewPresentation(m.linkUrl, m.linkPreviewType, m.linkSiteName).actionable) { this.actions.onLinkTap(m.linkUrl, false); }
        }
        else if (link.link.action === 'page-button' && link.link.button !== undefined) {
          const button = link.link.button;
          if (button.kind === 'login') { this.openLoginButton(button.buttonId ?? 0, button.value); }
          else if (button.kind === 'switch-inline') { this.openSwitchInline(button.value); }
          else if (button.kind === 'url') { this.actions.onLinkTap(button.value, true); }
          else if (button.kind === 'copy') { this.actions.onCopyCode(button.value); }
          else if (button.kind === 'callback') { this.actions.onBotCallback(m.id, button.value); }
          else if (button.kind === 'webapp') { this.actions.onMiniApp(m.id, button.value); }
          else if (button.kind === 'profile' && button.userId > 0) { this.actions.onAvatarTap(button.userId); }
          else if (button.kind === 'game') { this.actions.onGameOpen(m.id); }
          else if (button.kind !== 'disabled') { showToast($r('app.string.miniapp_button_unsupported')); }
        }
        else if (link.link.action === 'voice-transcribe') {
          if (m.speechState !== 'pending' && m.speechState !== 'done' && this.sendState !== 'sending') { this.actions.onRecognizeSpeech(m.id); }
        }
        else if (link.link.action === 'translation-toggle') { this.actions.onToggleTranslation(m.id, !m.translationHidden); }
        else if (link.link.action === 'translation-retry') { this.actions.onRetryTranslation(m.id); }
        else if (link.link.action === 'spoiler') { this.revealDrawnSpoilers(); }
        else if (link.link.action === 'copy') { this.actions.onCopyCode(link.link.label); }
        else if (link.link.action === 'quote' && link.link.blockOffset !== undefined) { this.toggleDrawnQuote(link.link.blockOffset); }
        else if (!this.openDocumentLink(link.link.url)) { this.actions.onLinkTap(link.link.url, link.link.hidesUrl); }
      }
      return;
    }
    if (messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) { this.openMenu(hitX); }
  }
  private openSwitchInline(query: string): void {
    const row = this.documentNodeId(), blocks = this.rowGroup.head.richBlocks;
    this.loginRow = row; this.loginOwner = blocks;
    if (this.switchInline === null) { this.switchInline = new DocumentSwitchInline(); }
    this.switchInline.open(this.rowData.chatId, this.rowGroup.head.id, query, {
      current: (): boolean => this.presentationReady() && !this.rowData.selectionActive &&
        row === this.documentNodeId() && blocks === this.rowGroup.head.richBlocks,
      insert: (text: string): void => {
        if (this.actions.onSwitchInlineCurrent !== undefined) { this.actions.onSwitchInlineCurrent(text); }
        else { showToast($r('app.string.miniapp_button_unsupported')); }
      },
      unavailable: (): void => { showToast($r('app.string.miniapp_button_unsupported')); }
    });
  }
  private openLoginButton(buttonId: number, url: string): void {
    const row = this.documentNodeId(), blocks = this.rowGroup.head.richBlocks;
    this.loginRow = row; this.loginOwner = blocks;
    if (this.loginUrl === null) { this.loginUrl = new DocumentLoginUrl(); }
    this.loginUrl.open(this.rowData.chatId, this.rowGroup.head.id, buttonId, url, {
      current: (): boolean => this.presentationReady() && !this.rowData.selectionActive &&
        row === this.documentNodeId() && blocks === this.rowGroup.head.richBlocks,
      open: (target: string, ask: boolean): void => this.actions.onLinkTap(target, ask),
      confirm: (prompt: DocumentLoginPrompt): Promise<string> => new Promise<string>((resolve): void => {
        const sheets: SheetInfo[] = [
          { title: str('document_login_accept'), action: (): void => resolve('login') },
          { title: str('document_login_open'), action: (): void => resolve('open') }
        ];
        if (prompt.writeAccess) { sheets.push({ title: str('document_login_write'), action: (): void => resolve('write') }); }
        this.getUIContext().showActionSheet({ title: str('document_login_title'),
          message: str('document_login_message', prompt.domain), sheets, cancel: (): void => resolve('cancel') });
      })
    });
  }
  private claimDocumentWidget(widget: DrawnDocumentWidget): boolean {
    if (!this.presentationReady() || !this.plan?.caption?.widgetOwners.has(widget)) { return false; }
    this.claimed = true;
    if (this.rowData.selectionActive) { this.actions.onToggleSelectedMessage(this.rowGroup.head.id); return false; }
    return true;
  }
  private openDocumentMedia(media: DrawnDocumentMedia): void {
    if (!this.presentationReady()) { return; }
    const items = this.plan?.caption?.source.mediaItems;
    if (items === undefined || items[media.index] !== media) { return; }
    this.claimed = true;
    if (this.rowData.selectionActive) { this.actions.onToggleSelectedMessage(this.rowGroup.head.id); return; }
    const session: DocumentMediaSession = { media: items, chatId: this.rowData.chatId,
      messageId: this.rowGroup.head.id, date: this.rowGroup.head.date, senderName: this.rowGroup.head.senderName };
    const params: Record<string, Object> = { 'documentMedia': session, 'startIndex': media.index };
    stackOf('chat')?.pushPath({ name: 'DownloadPreviewPage', param: params });
  }
  private openMenu(x: number): void {
    this.menuOffset = x - (this.plan?.width ?? 0) / 2; this.menuShown = true;
  }
  private longPress(event: GestureEvent): void {
    if (this.claimed || this.draggingMessage || tableScrollTouched()) { return; }
    const f = firstFinger(event.fingerList), p = this.plan;
    const x = this.rowToCanvasX(f?.localX ?? 0, Number(event.target.area.width));
    const y = (f?.localY ?? 0) - (this.rowGroup.showSenderName ? 3 : 1);
    const reaction = this.reactionAt(x, y);
    if (!this.rowData.selectionActive && reaction !== null && reaction.reaction !== null &&
      this.touchPlan === p && this.touchReaction === reaction) {
      this.claimed = true; this.foreground.press(null);
      this.actions.onShowReactors(this.rowGroup.head.id, reaction.key); return;
    }
    if (f !== undefined && p !== null && p.avatar.width > 0 && albumRectContains(p.avatar, x, y)) {
      this.claimed = true; this.foreground.press(null);
      const m = this.rowGroup.head;
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
    if (this.rowData.selectionActive || policy.longPressSelects) { this.actions.onSelectMessages(this.rowGroup.memberIds); }
    else if (policy.longPressOpensMenu) { this.openMenu(x); }
  }
  private rowToCanvasX(x: number, rowWidth: number): number {
    return x - (this.rowGroup.head.isOutgoing ? rowWidth - 4 - (this.plan?.width ?? 0) : 4);
  }
  private rowTouch(event: TouchEvent): void {
    const t = event.changedTouches[0] ?? event.touches[0];
    if (event.type === TouchType.Down && t !== undefined) {
      this.claimed = false; this.draggingMessage = false;
      this.touchRowId = this.rowGroup.head.rowId; this.touchChatId = this.rowData.chatId;

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
      // The canvas owns its tap even when a retained ancestor does not receive
      // the same Down. Keep the identity guard local; never accept a stale click.
      this.touchRowId = this.rowGroup.head.rowId; this.touchChatId = this.rowData.chatId;
      this.touchPlan = this.plan; this.touchX = t.x; this.touchY = t.y;
      this.touchLink = this.linkAt(t.x, t.y);
      this.touchReaction = this.reactionAt(t.x, t.y);
      this.foreground.setPress(this.touchLink, this.plan?.density ?? 1);
      if (!this.rowData.selectionActive) { this.foreground.pressReaction(this.touchReaction); }
    } else if (event.type === TouchType.Cancel || event.touches.length > 1 || this.touchPlan !== this.plan) {
      if (event.type === TouchType.Cancel || event.touches.length > 1) {
        this.claimed = true; this.touchRowId = 0; this.touchChatId = 0;
      }
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
    if (tableScrollTouched() || this.edge || this.rowData.editingActive || this.draggingMessage ||
      (this.touchOnBody && this.canDragMessage() && this.dragGesture.prefersDrag(Date.now()))) { return; }
    this.swipeX = Math.max(this.rowData.canReply ? SWIPE_REPLY_MAX : 0, Math.min(SWIPE_SELECT_MAX, offset));
    if (this.swipeX !== 0) { this.claimed = true; this.foreground.press(null); }
  }
  private endSwipe(): void {
    const usable = !tableScrollTouched() && !this.edge && !this.rowData.editingActive && !this.draggingMessage &&
      !(this.touchOnBody && this.canDragMessage() && this.dragGesture.prefersDrag(Date.now()));
    const reply = usable && this.rowData.canReply && this.swipeX <= SWIPE_REPLY_TRIGGER;
    const select = usable && this.swipeX >= SWIPE_SELECT_TRIGGER;
    this.getUIContext().animateTo({ duration: this.env.powerSaving || this.env.reduceAnim ? 0 : 180,
      curve: Curve.EaseOut }, (): void => { this.swipeX = 0; });
    if (reply) { this.actions.onReplyTo(this.rowGroup.head.id); }
    else if (select) { this.actions.onSelectMessages(this.rowGroup.memberIds); }
  }

  private canDragMessage(): boolean {
    return this.kind === 'text' && !this.rowData.selectionActive && !this.rowData.editingActive &&
      this.rowGroup.memberIds.length === 1 && this.rowGroup.head.id > 0;
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
      const stale = this.touchRowId !== this.rowGroup.head.rowId || this.touchChatId !== this.rowData.chatId;
      if (this.dragGesture.end(now, event.type !== TouchType.Up || stale || this.claimed)) {
        this.invokeLongPress(t?.x ?? this.touchX);
      }
    }
  }

  @Builder
  menu() {
    DrawnBubbleMenu({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData,
      actions: this.actions, nowSec: this.nowSec });
  }

  @Local private canvasTransitionIndex: number = -1;
  private canvasTransition: DrawnAlbumTransition | null = null;
  private canvasTransitionFrame: DrawnMediaFrame | undefined = undefined;

  private openCanvasMedia(tile: DrawnBubbleTile, event: ClickEvent): void {
    if (this.canvasTransition === null) {
      this.canvasTransition = new DrawnAlbumTransition((index: number): void => {
        if (this.canvasTransitionIndex !== index) { this.canvasTransitionIndex = index; }
      }, (task: () => void): void => { this.rowContext().postFrameCallback(new OneShotFrameCallback(task)); });
    }
    const chatId = this.rowData.chatId, rowId = this.rowGroup.head.rowId;
    const index = tile.cell.idx;
    const source = this.nativeTiles[index];
    const frame = this.mediaFrames[index];
    const transitionFrame = source !== undefined && frame !== undefined
      ? drawnAlbumTransitionFrame(frame, source, this.gridRadii()) : undefined;
    const windowX = event.windowX, windowY = event.windowY;
    // begin first clears the previous anchor, then publishes the new index.
    this.canvasTransitionFrame = transitionFrame;
    this.canvasTransition.begin(index, tile.cell.messageId, (): boolean => {
      const current = this.nativeTiles[index];
      return this.active && this.presentationReady() &&
        this.rowData.chatId === chatId && this.rowGroup.head.rowId === rowId && current !== undefined &&
        current.cell.messageId === tile.cell.messageId;
    }, (): void => { this.actions.onMediaTap(tile.cell.messageId, windowX, windowY); }, (): boolean => {
      const current = this.nativeTiles[index];
      return this.albumCanvas.state.ready && transitionFrame !== undefined && current !== undefined &&
        source !== undefined &&
        current.x === source.x && current.y === source.y && current.width === source.width && current.height === source.height;
    });
  }

  private gridRadii(): BorderRadiuses {
    const m = this.rowGroup.head;
    const pure = this.rowGroup.caption === '' && m.text === '' && m.replyToMessageId === 0 &&
      m.reactions.length === 0 && m.forwardFrom === '' && !(this.rowData.isChannel && m.commentCount > 0) &&
      !(this.rowData.isGroup && !m.isOutgoing && this.rowGroup.showSenderName && m.senderName !== '');
    return this.gridCorners.prepare(pure, this.env.bubbleRadius, m.isOutgoing, this.rowGroup.showSenderName, this.rowGroup.showAvatar);
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
    const key = `${this.rowData.chatId}:${this.rowGroup.head.rowId}`;
    if (key !== this.mediaVisibilityKey) { this.mediaVisibilityKey = key; this.mediaVisibilityEpoch++; }
    return this.mediaVisibilityEpoch;
  }
  private mediaVisibility(): (visible: boolean, ratio: number) => void {
    const generation = this.syncMediaVisibility();
    const chatId = this.rowData.chatId, rowId = this.rowGroup.head.rowId;
    return (_visible: boolean, ratio: number): void => {
      if (this.active && generation === this.mediaVisibilityEpoch && this.rowData.chatId === chatId && this.rowGroup.head.rowId === rowId) {
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
  // Cheap projections read their underlying state in the consuming observer.
  // They need no extra Computed binding to clear/rebuild during recursive reuse.
  private get footerPaintKey(): string { return `${this.views}:${this.rowGroup.head.date}:${this.rowGroup.head.editDate}`; }

  // Computed publishes only when the grid snapshot changes. Footer, caption
  // placement and shell style can invalidate plan without touching tile nodes.
  @Computed
  private get nativeTiles(): DrawnBubbleTile[] { return this.plan?.nativeTiles ?? EMPTY_DRAWN_NATIVE_TILES; }
  private get mediaChatId(): number { return this.rowData.chatId; }
  private mediaFrameCache: DrawnMediaFrames = new DrawnMediaFrames();
  @Computed
  private get mediaFrames(): DrawnMediaFrame[] {
    return this.mediaFrameCache.prepare(this.nativeTiles, this.mediaChatId, this.kind === 'single');
  }
  private mediaSlotCache: DrawnMediaSlots = new DrawnMediaSlots();
  // This equality boundary keeps same-count tile replacements from notifying
  // ForEach. The physical cache alone does not suppress reactive propagation.
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
          StaticMiniThumbnail({ source: this.imageSlot(slot.index)?.mini ?? '',
            boxW: this.nativeTiles[slot.index]?.width ?? 0, boxH: this.nativeTiles[slot.index]?.height ?? 0 });
        }
        if (this.sendState === 'sending') {
          LiveProgressRing({ fileId: (this.nativeTiles[slot.index]?.cell.isVideo ?? false) ? this.kind === 'single' ? this.rowGroup.head.videoFileId : (this.nativeTiles[slot.index]?.cell.videoFileId ?? 0)
            : (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0), initialPercent: 0, ringSize: Math.min(44, Math.min((this.nativeTiles[slot.index]?.width ?? 0), (this.nativeTiles[slot.index]?.height ?? 0)) * .3) });
        } else if (this.imageSlot(slot.index)?.path === '') {
          if (!(this.nativeTiles[slot.index]?.cell.isVideo ?? false) && ((this.nativeTiles[slot.index]?.cell.failed ?? false) || (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) === 0)) {
            DrawnMediaRetry({ maxWidth: this.nativeTiles[slot.index]?.width ?? 160 });
          } else if ((this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) !== 0 && !(this.nativeTiles[slot.index]?.cell.failed ?? false)) {
            LiveProgressRing({ fileId: (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0), initialPercent: this.kind === 'single' ? this.rowGroup.head.photoProgress : (this.nativeTiles[slot.index]?.cell.progress ?? 0),
              ringSize: Math.min(34, Math.min((this.nativeTiles[slot.index]?.width ?? 0), (this.nativeTiles[slot.index]?.height ?? 0)) * .4) });
          }
        }
      }
      if (this.kind === 'single' && (this.nativeTiles[slot.index]?.cell.isVideo ?? false)) {
        DrawnSingleMediaVideo({ msg: this.rowGroup.head, data: this.rowData, actions: this.actions,
          slot: this.media.slots[0], sendState: this.sendState, mediaWidth: (this.nativeTiles[slot.index]?.width ?? 0), mediaHeight: (this.nativeTiles[slot.index]?.height ?? 0),
          thumbReady: ((this.imageSlot(0)?.path ?? '') !== '' ||
            (this.nativeTiles[slot.index]?.cell.thumbFileId ?? 0) === 0 || (this.nativeTiles[slot.index]?.cell.failed ?? false)) });
      } else if (this.kind === 'album' && (this.media.slots[slot.index]?.content.hostReady ?? false)) {
        DrawnAlbumVideo({ content: this.media.slots[slot.index]?.content, actions: this.actions, sendState: this.sendState });
      }
    }
    .attributeModifier(this.nativeAnchors.bind(slot.index, this.mediaFrames[slot.index]))
    .drawModifier(this.media.slots[slot.index]?.receiver);
  }

  // Preserve the equality boundary for retained canvas/native branch changes.
  // The same effective mode must not replay the grid during staged reuse.
  @Computed
  private get useAlbumCanvas(): boolean {
    return this.presentationActive === false ? this.retainedCanvasMode : this.albumCanvas.state.ready;
  }

  @Computed private get pollGeometryExpired(): boolean {
    const message = this.rowGroup.head;
    if (message.contentType !== 'poll' || message.pollIsClosed || message.pollCloseDate <= 0) { return false; }
    return Math.floor(Date.now() / 1000) >= message.pollCloseDate || this.nowSec >= message.pollCloseDate;
  }

  private transparentSticker(): boolean {
    const type = this.rowGroup.head.contentType;
    return type === 'sticker' || type === 'emoji' || type === 'customEmoji';
  }
  private glassLive(): boolean { return !this.transparentSticker() && this.env.bubbleMaterialOn && !this.env.powerSaving; }

  private menuMediaPath(tile: DrawnBubbleTile, index: number): string {
    const slot = this.imageSlot(index), owner = slot?.content.cell, expected = tile.cell;
    return owner?.chatId === expected.chatId && owner?.messageId === expected.messageId &&
      owner?.thumbFileId === expected.thumbFileId ? slot?.path || expected.thumbPath : expected.thumbPath;
  }
  private menuPaintState: DrawnMenuPaintState | null = null;
  private menuPaint(): DrawnMenuPaintState {
    if (this.menuPaintState === null) { this.menuPaintState = new DrawnMenuPaintState(); }
    return this.menuPaintState;
  }
  @Builder
  menuPreview() { this.canvasContent(true); }

  // Snapshot ownership includes native card/widget islands. The custom preview
  // reuses prepared geometry but owns its painters and uses posters, never a
  // second video/sticker player. No parsing/layout work is added to scrolling.
  @Builder
  canvasContent(preview: boolean = false) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.glassLive()) {
        DrawnGlassBackground({ plan: this.plan, fillColor: this.rowGroup.head.isOutgoing ?
          (this.rowData.themeBubbleOut || COLOR_BUBBLE_OUT) : COLOR_BUBBLE_IN });
      }
      if (this.kind !== 'text') {
        Stack({ alignContent: Alignment.TopStart }) {
          if (preview) {
            ForEach(this.nativeTiles, (tile: DrawnBubbleTile, index: number) => {
              DrawnMenuMedia({ path: this.menuMediaPath(tile, index), mini: tile.cell.mini,
                sourceKey: `${tile.cell.chatId}:${tile.cell.messageId}:${tile.cell.thumbFileId}`,
                boxWidth: tile.width, boxHeight: tile.height, corners: tile.corners })
                .position({ x: tile.x, y: tile.y });
            }, (tile: DrawnBubbleTile): string => tile.key);
          }
          if (!preview && this.useAlbumCanvas && this.canvasTransitionIndex >= 0) {
            Stack() {}
              .attributeModifier(this.nativeAnchors.bind(this.canvasTransitionIndex, this.canvasTransitionFrame))
              .drawModifier(this.media.slots[this.canvasTransitionIndex]?.receiver)
              .accessibilityLevel('no')
              .onAreaChange((): void => { this.canvasTransition?.ready(); });
          }
          if (!preview && !this.useAlbumCanvas) {
            ForEach(this.mediaSlots, (slot: DrawnMediaSlot) => {
              this.mediaTile(slot);
            }, (slot: DrawnMediaSlot): string => slot.key);
          }
        }.width(this.plan?.grid.width ?? 0).height(this.plan?.grid.height ?? 0)
        .position({ x: this.plan?.grid.x ?? 0, y: this.plan?.grid.y ?? 0 })
        .borderRadius(this.gridRadii()).clip(true).hitTestBehavior(HitTestMode.None)
        .accessibilityLevel(this.a11y?.active ? 'no-hide-descendants' : 'auto')
        .drawModifier(!preview && this.useAlbumCanvas ? this.albumCanvas : undefined);
      }
      if (this.plan?.caption?.hitsByUrl.has(this.env.linkNavBusy)) {
        DrawnBusyLink({ plan: this.plan?.caption ?? null, url: this.env.linkNavBusy })
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 });
      }
      // Static/TGS/video stickers share the canvas transform and capture host.
      // The existing non-hit-test foreground draws time AFTER the native content.
      if (preview && this.transparentSticker()) {
        DrawnMenuSticker({ msg: this.rowGroup.head,
          boxWidth: this.plan?.caption?.widgets[0]?.width ?? 0, boxHeight: this.plan?.caption?.widgets[0]?.height ?? 0 })
          .position({ x: (this.plan?.captionX ?? 0) + (this.plan?.caption?.widgets[0]?.x ?? 0),
            y: (this.plan?.captionY ?? 0) + (this.plan?.caption?.widgets[0]?.y ?? 0) });
      }
      if (!preview && this.rowGroup.head.contentType === 'sticker') {
        StickerMessageBubble({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData,
          actions: this.actions, contentOnly: true,
          contentMax: Math.max(this.plan?.caption?.widgets[0]?.width ?? 0, this.plan?.caption?.widgets[0]?.height ?? 0),
          onClaim: (): boolean => {
            const widget = this.plan?.caption?.widgets[0]?.widget;
            if (this.claimed || widget === undefined) { return false; }
            return this.claimDocumentWidget(widget);
          } }).position({ x: (this.plan?.captionX ?? 0) + (this.plan?.caption?.widgets[0]?.x ?? 0),
            y: (this.plan?.captionY ?? 0) + (this.plan?.caption?.widgets[0]?.y ?? 0) });
      }
      Row().width(this.plan?.width ?? 0).height(this.plan?.height ?? 0)
        .drawModifier((preview ? this.menuPaint().foreground : this.foreground).bind(this.plan, this.sendState, this.footerPaintKey))
        .hitTestBehavior(HitTestMode.None);
      if (this.plan?.caption?.previewImage !== null && this.plan?.caption?.previewImage !== undefined) {
        Stack() { DrawnPreviewImage({ msg: this.rowGroup.head, plan: this.plan?.caption ?? null }); }
          .width(this.plan?.caption?.widthVp ?? 0).height(this.plan?.caption?.heightVp ?? 0)
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 })
          .hitTestBehavior(HitTestMode.None);
      }
      if ((this.plan?.caption?.icons.length ?? 0) > 0) {
        DrawnInlineIconLayer({ plan: this.plan?.caption ?? null })
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 }).hitTestBehavior(HitTestMode.None);
      }
      if ((this.plan?.caption?.maths.length ?? 0) > 0) {
        DrawnMathLayer({ plan: this.plan?.caption ?? null, onMetricsChanged: (): void => { this.mathRevision++; } })
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 });
      }
      if ((this.plan?.caption?.emojis.length ?? 0) > 0) {
        DrawnInlineEmojiLayer({ plan: this.plan?.caption ?? null, msg: this.rowGroup.captionMessage ?? this.rowGroup.head })
          .position({ x: this.plan?.captionX ?? 0, y: this.plan?.captionY ?? 0 });
      }
      if ((this.plan?.quote?.mediaWidthPx ?? 0) > 0 || (this.plan?.chrome?.content.avatarCount ?? 0) > 0 ||
        (this.plan?.chrome?.reactions?.chips.length ?? 0) > 0) {
        DrawnChromeIslands({ plan: this.plan, msg: this.rowGroup.head, chatId: this.rowData.chatId,
          themeBubbleOut: this.rowData.themeBubbleOut });
      }
      if (!preview && this.a11y?.active) {
        DrawnRowAccessibility({ plan: this.plan, msg: this.rowGroup.head, sendState: this.sendState,
          onActivate: (x: number, y: number, event: ClickEvent): void => { this.click(event, x, y, true); },
          onMenu: (): void => {
            if (this.rowData.selectionActive) { this.actions.onToggleSelectedMessage(this.rowGroup.head.id); }
            else { this.openMenu((this.plan?.width ?? 0) / 2); }
          } });
      }
      if ((this.plan?.caption?.widgets.length ?? 0) > 0) {
        ForEach(this.plan?.caption?.widgets ?? this.emptyWidgets, (item: DrawnDocumentWidgetPlacement) => {
          if (item.widget.kind === 'message-sticker') {
            if (!preview && this.rowGroup.head.contentType !== 'sticker') {
              StickerMessageBubble({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData,
                actions: this.actions, contentOnly: true, contentMax: Math.max(item.width, item.height),
                onClaim: (): boolean => {
                  if (this.claimed) { return false; }
                  return this.claimDocumentWidget(item.widget);
                } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
            }
          } else if (item.widget.kind === 'message-giveaway') {
            DrawnGiveawayMessage({ chatId: this.rowData.chatId, msg: this.rowGroup.head, actions: this.actions, widget: item.widget, boxWidth: item.width,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-gift') {
            DrawnGiftMessage({ chatId: this.rowData.chatId, msg: this.rowGroup.head, actions: this.actions, widget: item.widget, boxWidth: item.width,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-paid-media') {
            DrawnPaidMediaMessage({ msg: this.rowGroup.head, actions: this.actions, widget: item.widget,
              boxWidth: item.width, pending: this.rowData.paidMediaPending, chatId: this.rowData.chatId,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-game') {
            DrawnGameMessage({ chatId: this.rowData.chatId, msg: this.rowGroup.head, actions: this.actions, widget: item.widget, boxWidth: item.width,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-dice') {
            DrawnDiceMessage({ msg: this.rowGroup.head, actions: this.actions, boxWidth: item.width,
              chatId: this.rowData.chatId, selectionActive: this.rowData.selectionActive,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (preview && item.widget.kind === 'message-video-note') {
            DrawnMenuMedia({ path: this.rowGroup.head.photoPath, mini: this.rowGroup.head.photoMini,
              sourceKey: `menu-note:${this.rowGroup.head.rowId}:${this.rowGroup.head.photoFileId}`,
              boxWidth: item.width, boxHeight: item.height,
              corners: { topLeft: item.width / 2, topRight: item.width / 2, bottomLeft: item.width / 2, bottomRight: item.width / 2 } })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-video-note') {
            DrawnVideoNoteMessage({ chatId: this.rowData.chatId, msg: this.rowGroup.head, actions: this.actions, boxWidth: item.width, sendState: this.sendState,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-checklist') {
            DrawnChecklistMessage({ msg: this.rowGroup.head, actions: this.actions, widget: item.widget,
              chatId: this.rowData.chatId, boxWidth: item.width,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-poll') {
            DrawnPollMessage({ msg: this.rowGroup.head, actions: this.actions, widget: item.widget,
              boxWidth: item.width, nowSec: this.nowSec,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-location') {
            DrawnLocationMessage({ widget: item.widget, msg: this.rowGroup.head, actions: this.actions, boxWidth: item.width,
              chatId: this.rowData.chatId, nowSec: this.nowSec,
              sharing: this.rowData.liveSharingId !== 0 && this.rowData.liveSharingId === this.rowGroup.head.id,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-contact') {
            DrawnContactMessage({ chatId: this.rowData.chatId, msg: this.rowGroup.head, actions: this.actions, widget: item.widget, boxWidth: item.width,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-voice') {
            DrawnVoiceMessage({ msg: this.rowGroup.head, actions: this.actions, boxWidth: item.width, sendState: this.sendState,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-audio') {
            DrawnAudioMessage({ widget: item.widget, msg: this.rowGroup.head, data: this.rowData, actions: this.actions, boxWidth: item.width,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'message-file') {
            DrawnFileMessage({ msg: this.rowGroup.head, actions: this.actions, widget: item.widget, boxWidth: item.width, sendState: this.sendState,
              onClaim: (): boolean => {
                if (this.claimed) { return false; }
                return this.claimDocumentWidget(item.widget);
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'video-embed') {
            DrawnDocumentVideo({ widget: item.widget, boxWidth: item.width, boxHeight: item.height,
              onClaim: (): boolean => this.claimDocumentWidget(item.widget),
              onOpen: (url: string): void => { this.actions.onLinkTap(url, true); } })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'html-embed') {
            DrawnDocumentEmbed({ widget: item.widget, boxWidth: item.width, boxHeight: item.height,
              onMetricsChanged: (): void => {
                if (this.presentationReady() && this.plan?.caption?.widgetOwners.has(item.widget)) { this.mathRevision++; }
              },
              onClaim: (): boolean => this.claimDocumentWidget(item.widget),
              onOpen: (url: string): void => { this.actions.onLinkTap(url, true); } })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'article-image') {
            DrawnDocumentArticleImage({ widget: item.widget })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'post-author' || item.widget.kind === 'chat-link') {
            DrawnDocumentPostAuthor({ widget: item.widget, boxWidth: item.width,
              onOpen: (): void => {
                if (this.claimDocumentWidget(item.widget) && item.widget.url !== undefined && item.widget.url !== '') {
                  this.actions.onLinkTap(item.widget.url, true);
                }
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'map') {
            DrawnDocumentMap({ widget: item.widget, chatId: this.rowData.chatId, boxWidth: item.width, boxHeight: item.height,
              onOpen: (): void => {
                if (this.claimDocumentWidget(item.widget)) { this.actions.onLocationOpen(item.widget.latitude, item.widget.longitude, '', true); }
              } }).position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'audio') {
            DrawnDocumentAudio({ widget: item.widget, preparedCard: documentCardFor(item), audioItems: this.plan?.caption?.source.audioItems, chatId: this.rowData.chatId, messageId: this.rowGroup.head.id, boxWidth: item.width,
              onClaim: (): boolean => this.claimDocumentWidget(item.widget) })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else if (item.widget.kind === 'voice') {
            DrawnDocumentVoice({ widget: item.widget, preparedCard: documentCardFor(item), boxWidth: item.width,
              onClaim: (): boolean => this.claimDocumentWidget(item.widget) })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          } else {
            DrawnDocumentFile({ widget: item.widget, preparedCard: documentCardFor(item), chatId: this.rowData.chatId, messageId: this.rowGroup.head.id, boxWidth: item.width,
              onClaim: (): boolean => this.claimDocumentWidget(item.widget) })
              .position({ x: (this.plan?.captionX ?? 0) + item.x, y: (this.plan?.captionY ?? 0) + item.y });
          }
        }, (item: DrawnDocumentWidgetPlacement): string => `${this.rowData.chatId}:${this.rowGroup.head.id}:${drawnPlacementKey(item)}`);
      }
      if ((this.plan?.caption?.media.length ?? 0) > 0) {
        ForEach(this.plan?.caption?.media ?? this.emptyDocumentMedia, (asset: DrawnDocumentMediaPlacement) => {
          if (asset.slides !== undefined) {
            DrawnDocumentGallery({ slides: asset.slides, boxWidth: asset.width, boxHeight: asset.height,
              onOpen: (media: DrawnDocumentMedia): void => { this.openDocumentMedia(media); } })
              .position({ x: (this.plan?.captionX ?? 0) + asset.x, y: (this.plan?.captionY ?? 0) + asset.y });
          } else {
          DrawnDocumentMediaIsland({ media: asset.media, boxWidth: asset.width, boxHeight: asset.height,
            onOpen: (): void => {
              this.openDocumentMedia(asset.media);
            } })
            .position({ x: (this.plan?.captionX ?? 0) + asset.x, y: (this.plan?.captionY ?? 0) + asset.y });
          }
        }, (asset: DrawnDocumentMediaPlacement): string => `${this.rowData.chatId}:${this.rowGroup.head.id}:${drawnPlacementKey(asset)}`);
      }
      if ((this.plan?.caption?.tables.length ?? 0) > 0) {
        ForEach(this.plan?.caption?.tables ?? this.emptyTables, (table: DrawnTablePlacement) => {
          DrawnTableIsland({ msg: this.rowGroup.head, placement: table, onMetricsChanged: (): void => { this.mathRevision++; },
            onClaimTouch: (): void => {
              if (!this.presentationReady() || !this.plan?.caption?.tables.includes(table)) { return; }
              if (!this.claimed && this.rowData.selectionActive) { this.actions.onToggleSelectedMessage(this.rowGroup.head.id); }
              this.claimed = true;
            },
            onLinkTap: (link: DrawnRichLink): void => {
              if (!this.presentationReady() || !this.plan?.caption?.tables.includes(table)) { return; }
              if (this.rowData.selectionActive) { this.claimed = true; this.actions.onToggleSelectedMessage(this.rowGroup.head.id); }
              else { this.claimed = true; if (!this.openDocumentLink(link.url)) { this.actions.onLinkTap(link.url, link.hidesUrl); } }
            } })
            .position({ x: (this.plan?.captionX ?? 0) + table.x, y: (this.plan?.captionY ?? 0) + table.y });
        }, (table: DrawnTablePlacement): string => `${this.rowData.chatId}:${this.rowGroup.head.id}:${drawnPlacementKey(table)}`);
      }
    }
    .attributeModifier((preview ? this.menuPaint().attributes : this.canvasAttributes).bind(this.plan?.width ?? 0, this.plan?.height ?? 0,
      preview ? 1 : 1 + this.jumpFocus * JUMP_FOCUS_SCALE,
      this.rowGroup.head.isOutgoing ? '100%' : (this.plan?.bubbleX ?? 0),
      preview ? 1 : 1 + this.jumpFocus * JUMP_FOCUS_BRIGHTNESS, !preview && this.canDragMessage() && this.allowBodyDrag,
      !preview && this.deleteCaptureSupported && (this.plan?.caption?.source.links.length ?? 0) === 0))
    .drawModifier((preview ? this.menuPaint().background : this.painter).bind(this.plan, false, !this.transparentSticker() && !this.glassLive()))
    .hitTestBehavior(preview ? HitTestMode.None : HitTestMode.Default)
    .accessibilityLevel(preview ? 'no-hide-descendants' : 'no')
    .onTouch((e: TouchEvent): void => { this.touch(e); })
    .onClick((e: ClickEvent): void => { this.click(e); })
    .onDragStart((event: DragEvent): DragItemInfo => {
      // Reaction holds are handled before the system's 500ms drag recognizer.
      // Never export the message when the initial target was a reaction chip.
      if (!this.touchOnBody || this.claimed) { return {}; }
      this.dragGesture.claim(); this.draggingMessage = true; this.claimed = true;
      this.menuShown = false; this.foreground.press(null);
      return configureMessageDrag(event, this.rowData.chatId, this.rowGroup.head.id, messageDragType(this.rowGroup.head.contentType));
    })
    .onDragEnd((): void => { this.draggingMessage = false; });
  }

  build() {
    if (this.plan === null) {
      if (this.rowGroup.head.contentType === 'sticker' || this.rowGroup.head.contentType === 'emoji' || this.rowGroup.head.contentType === 'customEmoji') {
        StickerMessageBubble({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      } else if (this.rowGroup.head.contentType === 'file' || this.rowGroup.head.contentType === 'audio' || this.rowGroup.head.contentType === 'voice' || this.rowGroup.head.contentType === 'contact' || this.rowGroup.head.contentType === 'location' || this.rowGroup.head.contentType === 'venue' || this.rowGroup.head.contentType === 'checklist' || this.rowGroup.head.contentType === 'poll' || this.rowGroup.head.contentType === 'videoNote' || this.rowGroup.head.contentType === 'dice' || this.rowGroup.head.contentType === 'game' || this.rowGroup.head.contentType === 'paidMedia' || this.rowGroup.head.contentType === 'gift' || this.rowGroup.head.contentType === 'giveaway') {
        MessageBubble({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      } else if (this.kind === 'text') {
        LegacyTextRow({ group: this.rowGroup, data: this.rowData, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      } else if (this.kind === 'single') {
        LegacySingleMediaBubble({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
      } else {
        LegacyAlbumMessageBubble({ group: this.rowGroup, data: this.rowData, actions: this.actions,
          nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, dateInHost: this.dateInHost });
      }
    } else {
      Column() {
        if (!this.dateInHost && this.rowGroup.dateLabel !== '') {
          Text(this.rowGroup.dateLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 }).margin({ top: 5, bottom: 3 });
        }
        if (this.rowData.showUnreadDivider) {
          Row() {
            Divider().layoutWeight(1).strokeWidth(1).color(COLOR_TEXT_SECONDARY).opacity(.55);
            Text(this.rowData.dividerIsResume ? $r('app.string.mb_last_viewed_position') : $r('app.string.mb_unread'))
              .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium).margin({ left: 10, right: 10 });
            Divider().layoutWeight(1).strokeWidth(1).color(COLOR_TEXT_SECONDARY).opacity(.55);
          }.width('100%').height(26).padding({ left: 12, right: 12, bottom: 4 });
        }
        Row() {
          Stack({ alignContent: Alignment.TopStart }) {
            // Keep capture opacity separate from canvas press feedback and the
            // content's jump transform. The existing outer Stack hosts deletion;
            // no extra component + Stack are needed on every normal message.
            Row() {
              this.canvasContent();
            }.accessibilityLevel('no').id(this.deleteNodeKey)
            .opacity(this.leaving > 0 && (!this.deleteCaptureSupported || this.capturedDeleteKey === this.deleteNodeKey) ? 0 : 1)
            .hitTestBehavior(this.leaving > 0 ? HitTestMode.None : HitTestMode.Default)
            .bindContextMenu(this.menuShown, this.menu(), {
              offset: { x: this.menuOffset, y: 0 },
              // The framework invokes custom previews without a component receiver.
              preview: menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp) ? MenuPreviewMode.NONE
                : (this.transparentSticker() || drawnLiveSurface(this.rowGroup, this.rowData, this.actions.playback !== undefined))
                  ? (): void => { this.menuPreview(); } : MenuPreviewMode.IMAGE,
              previewAnimationOptions: { scale: [0.98, 1.035], transition: this.menuFx.preview() },
              borderRadius: 16, backgroundColor: Color.Transparent,
              backgroundBlurStyle: containerBlur('menu'), systemMaterial: overlayMaterial('menu'),
              transition: this.menuFx.menu(), mask: { color: '#52000000', backgroundBlurStyle: BlurStyle.BACKGROUND_THIN },
              modalMode: ModalMode.TARGET_WINDOW, hapticFeedbackMode: HapticFeedbackMode.AUTO,
              onDisappear: (): void => { this.menuShown = false; this.menuPaintState = null; }
            });
            if (this.leaving > 0 && this.deleteCaptureSupported) {
              ShatterDeleteOverlay({ nodeId: this.deleteNodeKey, particleBudget: this.actions.rowLeave.particleBudget(),
                onCaptured: this.leaveCapture.captured(),
                onFinish: this.leaveCapture.finished(this.rowGroup.head.rowId, this.actions.rowLeave) })
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
            // Position creates an outer wrapper; it must also pass touches to the canvas avatar hit region.
            if (this.avatarAnimated && (this.plan?.avatar.width ?? 0) > 0) {
              SenderAnimatedLayer({ senderId: this.rowGroup.head.senderId, senderIsUser: this.rowGroup.head.senderIsUser, avatarSize: 38 })
                .position({ x: this.plan?.avatar.x ?? 0, y: this.plan?.avatar.y ?? 0 })
                .hitTestBehavior(HitTestMode.None);
            }
          }.width(this.plan?.width ?? 0).height(this.plan?.height ?? 0)
            .id(this.rowGroup.head.richBlocks !== undefined ? this.documentNodeId() : undefined)
            .onAreaChange((this.plan?.caption?.source.anchorPaths?.size ?? 0) > 0 ? (): void => this.flushDocumentAnchor() : undefined);
        }.width('100%').padding({ left: 4, right: 4, top: this.rowGroup.showSenderName ? 3 : 1,
          bottom: this.rowGroup.showAvatar ? 3 : 1 })
        .justifyContent(this.rowGroup.head.isOutgoing ? FlexAlign.End : FlexAlign.Start)
        .translate({ x: this.swipeX })
        .parallelGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((e: GestureEvent): void => { this.swipe(e.offsetX); })
          .onActionEnd((): void => { this.endSwipe(); }).onActionCancel((): void => { this.endSwipe(); }))
        .parallelGesture(LongPressGesture({ fingers: 1, repeat: false,
          duration: this.rowGroup.head.reactions.length > 0 ? 450 : 500 })
          .onAction((e: GestureEvent): void => { this.longPress(e); }))
        .onTouch((e: TouchEvent): void => { this.rowTouch(e); })
        .onClick((e: ClickEvent): void => {
          if (!this.claimed && !this.rowData.selectionActive && messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
            this.openMenu(this.rowToCanvasX(e.x, Number(e.target.area.width)));
          }
        });
        if (this.rowGroup.head.inlineButtons.length > 0) {
          BubbleInlineKeyboard({ msg: this.rowGroup.head, group: this.rowGroup, data: this.rowData, actions: this.actions,
            context: this.keyboardState(), drawnWidth: this.keyboardWidth(),
            drawnLeft: 4 + (this.plan?.bubbleX ?? 0) + (this.rowGroup.head.isOutgoing ? 0 :
              this.keyboardGutter()),
            drawnRight: 4 + (this.rowGroup.head.isOutgoing ? this.keyboardGutter() : 0) });
        }
      }.width('100%')
        .bindSheet($$this.noteShown, this.documentNote, { height: SheetSize.MEDIUM, dragBar: true, showClose: true })
        .onVisibleAreaApproximateChange({ ratios: [0], expectedUpdateInterval: 16 },
          this.kind === 'album' ? this.mediaVisibility() : undefined)
        .transition(this.rowData.animateIn
        ? TransitionEffect.translate({ y: 16 }).combine(TransitionEffect.OPACITY)
          .animation({ duration: animationDurationFor(this.env.chatEffects && this.env.messageEffects &&
            !this.env.powerSaving, scrollActiveNow(), 220), curve: Curve.FastOutSlowIn })
        : TransitionEffect.IDENTITY);
    }
  }
}
