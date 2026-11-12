import { DissolveDeleteEffect } from '../common/DissolveDeleteEffect';
import { MessageDragGesture } from '../../util/messageDragGesture';
import { configureMessageDrag } from '../../services/MessageDragSource';
import { messageDragType } from '../../util/messageDrag';
import { tableScrollTouched } from '../../util/tableTouchChannel';
import { JUMP_FOCUS_SCALE } from '../../util/bubbleFocusChannel';
import { MessageMenuTransitions } from '../../util/messageMenuTransitions';
import { isEdgeSwipeStart, SWIPE_REPLY_MAX, SWIPE_REPLY_TRIGGER, SWIPE_SELECT_MAX, SWIPE_SELECT_TRIGGER } from '../../util/swipeReplyGesture';
import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { BubbleCornerCache, SenderAvatarSpec, SenderAvatarSpecCache } from '../../util/messageBubblePresentation';
import { chatEnv } from '../../util/chatEnvMirror';
import { BUBBLE_AVATAR_GAP_VP, BUBBLE_AVATAR_GUTTER_VP, hitSenderAvatarColumn } from '../../util/mediaBox';
import { isUnformattedPlainText, parseFormattedText } from '../../util/richText';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_OUT, COLOR_BUBBLE_IN } from '../../util/theme';
import { TranslationStatus } from '../../util/translationChannel';
import { pinForTranslationGrowth } from '../../util/translationGrowthPin';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import { logW } from '../../util/log';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { menuPreviewCompact } from '../../util/menuPreview';
import { firstFinger } from '../../util/firstFinger';

import { MessageBubbleContext, MessageBubbleShell } from './MessageBubbleShell';
import { BubbleContentLayout } from './BubbleContentLayout';
import { BubbleInlineKeyboard } from './BubbleInlineKeyboard';
import { MessageSenderAvatar } from './MessageSenderAvatar';
import { DrawnBubbleController } from './DrawnBubbleController';
import { DrawnBubbleMenu } from './DrawnBubbleMenu';
import { DrawnContentOutline } from './DrawnContentOutline';
import { DRAWN_BUBBLE_PRESS, DRAWN_BUBBLE_PRESS_NONE } from './DrawnBubblePress';
import { drawnContentEligible, drawnLiveSurface } from '../../util/drawnContentPolicy';

const AVATAR_GUTTER: Padding = { left: BUBBLE_AVATAR_GUTTER_VP };
const NO_GUTTER: Padding = {};
const PURE_MEDIA_CORNER_RADIUS: BorderRadiuses = { topLeft: 15, topRight: 15, bottomLeft: 15, bottomRight: 15 };

// Hybrid row: native interactive content inside one drawn solid outline. No
// per-message glass geometry, tail components, shadow subtree or eager menu.
@ComponentV2
export struct DrawnContentRow {
  @Require @Param context: MessageBubbleContext;
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  @BuilderParam body: () => void;
  @Local private swipeReplyX: number = 0;
  @Local private draggingMessage: boolean = false;
  private env = chatEnv;
  private active: boolean = false;
  private identity: string = '';
  private swipeFromEdge: boolean = false;
  private dragGesture: MessageDragGesture = new MessageDragGesture();
  private menuFx: MessageMenuTransitions = new MessageMenuTransitions();
  private cornerCache: BubbleCornerCache = new BubbleCornerCache();
  private avatarSpecCache: SenderAvatarSpecCache = new SenderAvatarSpecCache();
  private bubbleOutline: DrawnContentOutline = new DrawnContentOutline();
  private linkBody: string = '';
  private linkEntities: TdObject[] | null = null;
  private linkCaption: string = '';
  private linkCaptionEntities: TdObject[] | null = null;
  private linkPresent: boolean = false;
  private channels: DrawnBubbleController = new DrawnBubbleController({
    send: (value: string): void => { if (this.context.liveSendState !== value) { this.context.liveSendState = value; } },
    views: (value: string): void => { if (this.context.liveViews !== value) { this.context.liveViews = value; } },
    translation: (value: TranslationStatus | null): void => {
      if (this.context.translationStatus !== value) {
        this.context.translationStatus = value; pinForTranslationGrowth(this.data.chatId);
      }
    },
    role: (_value: string): void => {}
  });

  @Computed
  private get supported(): boolean { return drawnContentEligible(this.msg.contentType, this.env.bubbleMaterialOn); }
  private attach(): void {
    if (!this.active) { return; }
    const key = `${this.data.chatId}:${this.msg.rowId}:${this.msg.id}`;
    if (this.identity !== key) {
      this.context.resetInteraction(); this.dragGesture.reset(); this.swipeReplyX = 0;
      this.draggingMessage = false; this.swipeFromEdge = false; this.identity = key;
    }
    if (this.supported) { this.channels.attach(this.data.chatId, this.msg, false); }
    else { this.channels.detach(); }
  }
  @Monitor('msg', 'data', 'supported')
  private inputChanged(): void { this.attach(); }
  aboutToAppear(): void { this.active = true; this.attach(); }
  aboutToReuse(): void { this.active = true; this.identity = ''; this.attach(); }
  aboutToRecycle(): void {
    this.active = false; this.channels.detach(); this.identity = ''; this.dragGesture.reset();
    this.context.resetInteraction(); this.swipeReplyX = 0; this.draggingMessage = false;
  }
  aboutToDisappear(): void { this.aboutToRecycle(); }

  @Builder
  menu() {
    DrawnBubbleMenu({ msg: this.msg, group: this.group, data: this.data, actions: this.actions, nowSec: this.nowSec });
  }
  private senderAvatarSpec(): SenderAvatarSpec {
    const msg = this.msg;
    return this.avatarSpecCache.prepare(msg.senderId, msg.senderIsUser, msg.senderAvatarPath,
      msg.senderInitials, 38, true);
  }


  private compactMenuContext(): boolean {
    return this.context.msgContextMenuShown &&
      menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp);
  }


  private isPureMediaBubble(): boolean {
    const isMedia: boolean = this.msg.contentType === 'photo' ||
      this.msg.contentType === 'video' || this.group.photoPaths.length > 1;
    if (!isMedia) {
      return false;
    }
    return this.msg.text === '' && this.msg.translatedText === '' &&
      this.group.caption === '' && this.msg.replyToMessageId === 0 &&
      this.msg.reactions.length === 0 && !this.forwardLabelShown() &&
      !this.senderLabelShown() && !this.commentsRowShown();
  }


  private hasBubbleTail(): boolean {
    return this.group.showAvatar && !this.isBareEmoji() && !this.isPureMediaBubble();
  }


  private avatarGutterPadding(): Padding {
    return this.data.isGroup && !this.msg.isOutgoing && !this.group.showAvatar
      ? AVATAR_GUTTER : NO_GUTTER;
  }


  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }


  private rowTopPadding(): number {
    return this.group.showSenderName ? 3 : 1;
  }


  private rowBottomPadding(): number {
    return this.group.showAvatar ? 3 : 1;
  }


  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }


  private swipeReplyDuration(duration: number): number {
    return this.env.powerSaving || this.env.reduceAnim ? 0 : duration;
  }


  private recordMenuOffset(localX: number, width: number): void {
    this.context.recordMenuOffset(localX, width);
  }


  private recordRowMenuOffset(localX: number): void {
    const w: number = this.context.bubbleW > 0 ? this.context.bubbleW : 1;
    const x: number = Math.max(0, Math.min(localX, w));
    this.recordMenuOffset(x, w);
  }


  private canDragMessage(): boolean { return !this.data.selectionActive && !this.data.editingActive && this.group.memberIds.length === 1 && this.msg.id > 0 && messageDragType(this.msg.contentType) !== ''; }

  private onDragSourceTouch(event: TouchEvent): void {
    if (!this.canDragMessage()) { return; }
    const touch = event.touches[0] ?? event.changedTouches[0];
    const now = Date.now();
    if (event.type === TouchType.Down && touch !== undefined) {
      this.dragGesture.begin(touch.windowX, touch.windowY, now);
      this.recordMenuOffset(touch.x, Number(event.target.area.width));
    } else if (event.type === TouchType.Move && touch !== undefined) {
      this.dragGesture.move(touch.windowX, touch.windowY, now);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (touch !== undefined) { this.dragGesture.move(touch.windowX, touch.windowY, now); }
      if (this.dragGesture.end(now, event.type === TouchType.Cancel)) { this.onLongPress(); }
    }
  }


  private onLongPress(event?: GestureEvent): void {
    if (this.draggingMessage) { return; }
    // 手指压在气泡里那张可横滑的表格上：不弹菜单、也不做"抬起气泡"那套预览
    // 动效（用户 2026-09-22：「滑动会响应气泡长按的视觉效果」）。按住不动 500ms
    // 再拖，长按先于拖动成立，于是滚表格的同时菜单弹了出来。
    // 标记只在表格**真的可滚**时才打，普通表格上长按照常出菜单。
    if (tableScrollTouched()) {
      return;
    }
    // issue #114 诊断：小窗 + 键盘展开时长按调不出菜单。手势有没有到、走的哪一
    // 支、当时窗口和键盘多高、预览模式取哪种——报告人导日志就能对上。
    logW(`[Menu114] longPress id=${this.msg.id} scheme=${this.env.gestureScheme}`
      + ` kbd=${Math.round(this.env.keyboardHeightVp)} winH=${Math.round(this.env.screenHeightVp)}`
      + ` compact=${this.compactMenuContext()} liveVideo=${this.hasLiveVideoSurface()}`
      + ` shown=${this.context.msgContextMenuShown}`);
    const finger: FingerInfo | undefined = event === undefined ? undefined : firstFinger(event.fingerList);
    if (finger !== undefined && event !== undefined) {
      this.recordMenuOffset(finger.localX, Number(event.target.area.width));
    }
    this.context.gestureClaimed = true;
    // 已在多选：长按就是"选这一行"（相册 = 整组媒体），不弹菜单、也不重进多选。
    // 单条行在多选态下气泡整个不收触摸（ChatPage 行外层 BLOCK_DESCENDANTS），
    // 能走到这里的是相册行——它为了逐格勾选放开了命中。
    if (this.data.selectionActive) {
      this.actions.onSelectMessages(this.group.memberIds);
      return;
    }
    const policy: MessageGesturePolicy = messageGesturePolicy(this.env.gestureScheme);
    if (policy.longPressOpensMenu) {
      this.context.msgContextMenuShown = true;
      return;
    }
    if (policy.longPressSelects) {
      this.actions.onSelectMessages(this.group.memberIds);
    }
  }


  private swipeGestureEligible(): boolean {
    // 手指压在气泡里那张可横滑的表格上时，整行不跟手（用户 2026-09-22：
    // 「横向滑动会和气泡一起滑动」）。整行这条是 parallelGesture，按定义就要
    // 和子孙手势并行跑，子节点那边没有任何属性能让它让路——只能反过来由表格
    // 在按下时打个标记，这里读。详见 util/tableTouchChannel。
    if (this.draggingMessage || (this.canDragMessage() && this.dragGesture.prefersDrag(Date.now())) || tableScrollTouched()) {
      return false;
    }
    return !this.swipeFromEdge && !this.data.editingActive
      && this.msg.contentType !== 'system' && this.msg.contentType !== 'hidden';
  }


  private swipeReplyAllowed(): boolean {
    return this.swipeGestureEligible() && this.data.canReply;
  }


  private onSwipeReplyUpdate(offsetX: number): void {
    if (!this.swipeGestureEligible()) {
      return;
    }
    // 两个方向都跟手：向左（负）回复，向右（正）进多选，各自钳到自己的上限。
    // 不能回复的会话（只读频道等）把左边界收到 0：右滑照常，左滑不跟手。
    const lowerBound: number = this.data.canReply ? SWIPE_REPLY_MAX : 0;
    this.swipeReplyX = Math.max(lowerBound, Math.min(SWIPE_SELECT_MAX, offsetX));
    // 真的滑动起来了才算认领。PanGesture 的 distance 已经是 8，这里再确认
    // 一次位移，避免"手指抖了一下"就把一次正常点击吃掉。
    if (this.swipeReplyX !== 0) {
      this.context.gestureClaimed = true;
    }
  }


  private onSwipeReplyEnd(): void {
    const reply: boolean = this.swipeReplyAllowed() &&
      this.swipeReplyX <= SWIPE_REPLY_TRIGGER;
    // 右滑进多选，动作与长按选择完全一致（同一个 onSelectMessages 入口，
    // 传整组 memberIds——相册要整组一起选，和长按那条保持一致）。
    // 判据是 swipeGestureEligible 而不是 swipeReplyAllowed：多选与发言权无关。
    const select: boolean = this.swipeGestureEligible() &&
      this.swipeReplyX >= SWIPE_SELECT_TRIGGER;
    this.getUIContext().animateTo({ duration: this.swipeReplyDuration(180), curve: Curve.EaseOut }, (): void => {
      this.swipeReplyX = 0;
    });
    if (reply) {
      this.actions.onReplyTo(this.msg.id);
    } else if (select) {
      this.actions.onSelectMessages(this.group.memberIds);
    }
  }


  private suppressBubblePressDim(): boolean {
    return this.hasInlineLink() || this.hasLinkPreview() || this.msg.contentType === 'voice' ||
      this.msg.contentType === 'audio' || this.msg.contentType === 'file';
  }


  private hasLinkPreview(): boolean {
    return this.msg.linkUrl !== '' || this.msg.linkSiteName !== '' ||
      this.msg.linkTitle !== '' || this.msg.linkDescription !== '' ||
      this.msg.linkPhotoFileId !== 0;
  }


  private formattedTextHasLink(text: string, entities: TdObject[]): boolean {
    if (isUnformattedPlainText(text, entities)) {
      return false;
    }
    const segments = parseFormattedText(text, entities);
    for (const segment of segments) {
      for (const run of segment.runs) {
        if (run.url !== '') {
          return true;
        }
      }
    }
    return false;
  }


  private hasInlineLink(): boolean {
    const m = this.msg, g = this.group;
    if (this.linkBody === m.text && this.linkEntities === m.textEntities &&
      this.linkCaption === g.caption && this.linkCaptionEntities === g.captionEntities) { return this.linkPresent; }
    this.linkBody = m.text; this.linkEntities = m.textEntities;
    this.linkCaption = g.caption; this.linkCaptionEntities = g.captionEntities;
    this.linkPresent = this.formattedTextHasLink(this.msg.text, this.msg.textEntities) ||
      (this.group.caption !== '' &&
        this.formattedTextHasLink(this.group.caption, this.group.captionEntities));
    return this.linkPresent;
  }


  private hasLiveVideoSurface(): boolean { return drawnLiveSurface(this.group, this.data); }

  private bubbleCornerRadius(): BorderRadiuses {
    // Read all reactive inputs before the cache lookup, including on hits.
    const group = this.group;
    const base = this.cornerCache.prepare(this.env.bubbleRadius, this.msg.isOutgoing,
      group.showSenderName, group.showAvatar);
    if (this.isPureMediaBubble()) {
      return PURE_MEDIA_CORNER_RADIUS;
    }
    return base;
  }


  private isBareEmoji(): boolean {
    const type: string = this.msg.contentType;
    return type === 'emoji' || type === 'sticker' || type === 'customEmoji'
      || type === 'videoNote' || type === 'dice';
  }


  private bubbleFillColor(): ResourceColor {
    if (this.env.appearanceEpoch < 0) {
      return Color.Transparent; // 只为让 ArkUI 记下对 epoch 的依赖
    }
    if (this.msg.isOutgoing) {
      return this.data.themeBubbleOut !== '' ? this.data.themeBubbleOut : COLOR_BUBBLE_OUT;
    }
    return COLOR_BUBBLE_IN;
  }


  private forwardLabelShown(): boolean {
    return this.msg.forwardFrom !== '';
  }


  private senderLabelShown(): boolean {
    return this.data.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.group.showSenderName;
  }


  private commentsRowShown(): boolean {
    return this.data.isChannel && this.msg.commentCount > 0;
  }


  build() {
    if (!this.supported) {
      MessageBubbleShell({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) { this.body(); }
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
          Row() {
            if (this.data.isGroup && !this.msg.isOutgoing && this.group.showAvatar) {
              MessageSenderAvatar({ spec: this.senderAvatarSpec() }).margin({ right: BUBBLE_AVATAR_GAP_VP })
                .onClick((): void => {
                  if (!this.context.gestureClaimed && this.msg.senderIsUser && this.msg.senderId > 0) {
                    this.actions.onAvatarTap(this.msg.senderId);
                  }
                })
                .gesture(LongPressGesture().onAction((): void => {
                  if (this.msg.senderIsUser && this.msg.senderId > 0) {
                    this.context.gestureClaimed = true;
                    this.actions.onAvatarLongPress(this.msg.senderId, this.msg.senderName);
                  }
                }));
            }
            DissolveDeleteEffect({ instanceKey: 'message-' + this.data.chatId, rowId: this.msg.rowId,
              leaving: this.leaving, channel: this.actions.rowLeave, captureSupported: !this.hasLiveVideoSurface() }) {
              Row() {
                Row() {
                  BubbleContentLayout({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
                    context: this.context, body: (): void => { this.body(); } });
                }
                .padding(this.msg.isOutgoing ? { right: 7 } : { left: 7 })
                .drawModifier(this.bubbleOutline.bind(this.msg.isOutgoing, this.hasBubbleTail(), this.bubbleCornerRadius(),
                  this.bubbleFillColor(), `${this.env.appearanceEpoch}`, !this.env.scrollActive, this.getUIContext().vp2px(1)))
                .scale({ x: 1 + this.jumpFocus * JUMP_FOCUS_SCALE, y: 1 + this.jumpFocus * JUMP_FOCUS_SCALE,
                  centerX: this.msg.isOutgoing ? '100%' : '0%', centerY: '50%' })
                .parallelGesture(this.canDragMessage() ? undefined : LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
                  .onAction((e: GestureEvent): void => { this.onLongPress(e); }))
                .onTouch((e: TouchEvent): void => { this.onDragSourceTouch(e); })
                .onClick((e: ClickEvent): void => {
                  if (!this.context.gestureClaimed && !this.data.selectionActive && messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
                    this.recordMenuOffset(e.x, Number(e.target.area.width)); this.context.msgContextMenuShown = true;
                  }
                });
              }.attributeModifier(this.suppressBubblePressDim() || this.hasLiveVideoSurface() ? DRAWN_BUBBLE_PRESS_NONE : DRAWN_BUBBLE_PRESS);
            }
          }.alignItems(VerticalAlign.Bottom).padding(this.avatarGutterPadding())
          .draggable(this.canDragMessage())
          .onDragStart((e: DragEvent): DragItemInfo => {
            this.dragGesture.claim(); this.draggingMessage = true; this.context.gestureClaimed = true;
            this.context.msgContextMenuShown = false;
            return configureMessageDrag(e, this.data.chatId, this.msg.id, messageDragType(this.msg.contentType));
          })
          .onDragEnd((): void => { this.draggingMessage = false; })
          .bindContextMenu(this.context.msgContextMenuShown, this.menu(), {
            offset: { x: this.context.menuOffsetX, y: 0 },
            preview: this.hasLiveVideoSurface() || this.compactMenuContext() ? MenuPreviewMode.NONE : MenuPreviewMode.IMAGE,
            previewBorderRadius: this.bubbleCornerRadius(),
            previewAnimationOptions: { scale: [.98, 1.035], transition: this.menuFx.preview() },
            borderRadius: 16, backgroundColor: Color.Transparent, backgroundBlurStyle: containerBlur('menu'),
            systemMaterial: overlayMaterial('menu'), transition: this.menuFx.menu(),
            mask: { color: '#52000000', backgroundBlurStyle: BlurStyle.BACKGROUND_THIN }, modalMode: ModalMode.TARGET_WINDOW,
            hapticFeedbackMode: HapticFeedbackMode.AUTO, onDisappear: (): void => { this.context.msgContextMenuShown = false; }
          });
        }.width('100%').padding({ left: 4, right: 4, top: this.rowTopPadding(), bottom: this.rowBottomPadding() })
        .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start).alignItems(VerticalAlign.Bottom)
        .translate({ x: this.swipeReplyX })
        .parallelGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((e: GestureEvent): void => { this.onSwipeReplyUpdate(e.offsetX); })
          .onActionEnd((): void => { this.onSwipeReplyEnd(); }).onActionCancel((): void => { this.onSwipeReplyEnd(); }))
        .parallelGesture(LongPressGesture({ fingers: 1, repeat: false, duration: 500 }).onAction((e: GestureEvent): void => {
          if (this.context.gestureClaimed) { return; }
          const f = firstFinger(e.fingerList);
          if (f !== undefined && hitSenderAvatarColumn(f.localX, this.data.isGroup, this.msg.isOutgoing, this.group.showAvatar)) { return; }
          this.recordRowMenuOffset(f?.localX ?? 0); this.onLongPress(e);
        }))
        .onTouch((e: TouchEvent): void => {
          if (e.type === TouchType.Down) {
            this.context.gestureClaimed = false; this.draggingMessage = false;
            const t = e.touches[0] ?? e.changedTouches[0];
            this.swipeFromEdge = t !== undefined && isEdgeSwipeStart(t.windowX, this.env.screenWidthVp);
          }
        })
        .onClick((e: ClickEvent): void => {
          if (!this.context.gestureClaimed && !this.data.selectionActive && messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
            this.recordRowMenuOffset(e.x); this.context.msgContextMenuShown = true;
          }
        });
        if (this.msg.inlineButtons.length > 0) {
          BubbleInlineKeyboard({ msg: this.msg, group: this.group, data: this.data, actions: this.actions, context: this.context });
        }
      }.width('100%').transition(this.data.animateIn ? TransitionEffect.translate({ y: 16 }).combine(TransitionEffect.OPACITY)
        .animation({ duration: this.effectDuration(220), curve: Curve.FastOutSlowIn }) : TransitionEffect.IDENTITY);
    }
  }
}
