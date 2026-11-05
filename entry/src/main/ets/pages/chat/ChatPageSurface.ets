import { SearchResultsSheet } from './SearchResultsSheet';
import { MentionSuggestionState, CommandSuggestionState, InlineQueryState, StickerSuggestionState } from './ComposerSuggestionState';
import { SuggestionPanel } from './SuggestionPanel';
import { InlineResultsBar, StickerSuggestionBar } from './ComposerStrips';
import { MentionItem, CommandItem } from '../../store/InputSuggestions';
import { InlineResultRow } from '../../store/BotApi';
import { ScrollFab } from './ScrollFab';
import { UnreadMentionSession } from './UnreadMentionSession';
import { SearchSession } from './SearchSession';
import { COLOR_PRIMARY } from '../../util/theme';
import { ChatBackdrop } from './ChatBackdrop';
import { ChatTimelineSession } from './ChatTimelineSession';
import { ChatViewerSession } from './ChatViewerSession';
import { ChatOverlayState } from './ChatOverlayState';
import { EmojiDrawerState } from './EmojiDrawerState';
import { ChatBackgroundState, emptyChatBackground } from '../../store/ChatBackgroundStore';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { INITIAL_TIMELINE_ROW_FADE_MS, STICKER_FLY_MS, STICKER_GHOST_SIDE } from '../../util/chatPageTuning';

// Chat layer composition only. Slots keep their original session owners and live bindings.
// The root Stack is the existing underlay node: no added layout container or list wrapper.
// HDS navigation, fullscreen viewer, drop receiving and root sheet stay on ChatPage.
@ComponentV2
export struct ChatPageSurface {
  @Require @Param timeline: ChatTimelineSession;
  @Require @Param viewer: ChatViewerSession;
  @Require @Param overlayState: ChatOverlayState;
  @Require @Param emojiDrawer: EmojiDrawerState;
  @Param chatBg: ChatBackgroundState = emptyChatBackground();
  @Param screenW: number = 360;
  // 页面是否在屏上（NavDestination.onShown/onHidden）→ 背景层的 pin 生命周期。
  @Param surfaceActive: boolean = true;
  @Param screenH: number = 0;
  @Param chatBgBlur: number = 0;
  @Param chatBgPattern: number = 0;
  @Param chatBgDim: number = 0;
  @Event onViewportAreaChange: (oldH: number, newH: number) => void = (_oldH: number, _newH: number): void => {};
  @Event onResizeAreaChange: (oldH: number, newH: number) => void = (_oldH: number, _newH: number): void => {};
  @BuilderParam timelineContent: () => void;
  @BuilderParam bottomContent: () => void;
  @BuilderParam drawerContent: () => void;
  @BuilderParam overlayContent: () => void;
  @Require @Param mention: MentionSuggestionState;
  @Require @Param command: CommandSuggestionState;
  @Require @Param inline: InlineQueryState;
  @Require @Param sticker: StickerSuggestionState;
  @Require @Param unreadMentions: UnreadMentionSession;
  @Require @Param search: SearchSession;
  @Param membershipState: string = '';
  @Param showEmojiPanel: boolean = false;
  @Param replyKeyboardVisible: boolean = false;
  @Param hasReturnTarget: boolean = false;
  @Param pendingJumpId: number = 0;
  @Param unreadBadge: number = 0;
  @Param scrollToBottomBusy: boolean = false;
  @Param bottomChromeH: number = 0;
  @Param chromeIconColor: ResourceColor = Color.Transparent;
  @Event onPickCommand: (item: CommandItem) => void = (_item: CommandItem): void => {};
  @Event onFillCommand: (item: CommandItem) => void = (_item: CommandItem): void => {};
  @Event onPickMention: (item: MentionItem) => void = (_item: MentionItem): void => {};
  @Event onPickInline: (row: InlineResultRow) => void = (_row: InlineResultRow): void => {};
  @Event onPickSticker: (fileId: number) => void = (_fileId: number): void => {};
  @Event onReturnTap: () => void = (): void => {};

  @Builder
  private bottomSuggestions() {
    // Optional panels wait for the existing transition gate. The dock stays mounted from frame one.
    if (this.timeline.initialMessageTransitionSettled &&
      this.membershipState === 'writable' && !this.showEmojiPanel) {
      if (!this.replyKeyboardVisible &&
        (this.mention.mentionItems.length > 0 || this.command.commandPanelActive())) {
        SuggestionPanel({
          commandMode: this.command.commandPanelActive(),
          commands: this.command.commandItems,
          mentions: this.mention.mentionItems,
          loadState: this.command.commandLoadState,
          loadError: this.command.commandLoadError,
          catalogSize: this.command.catalogSize(),
          onPickCommand: (it: CommandItem): void => { this.onPickCommand(it); },
          onFillCommand: (it: CommandItem): void => { this.onFillCommand(it); },
          onPickMention: (it: MentionItem): void => { this.onPickMention(it); },
          onRetryCommands: (): void => { this.command.ensureCommandsLoaded(true); }
        });
      }
      if (this.mention.mentionItems.length === 0 && !this.command.commandPanelActive()) {
        if (this.inline.inlineResults.length > 0) {
          InlineResultsBar({
            results: this.inline.inlineResults,
            onPick: (row: InlineResultRow): void => { this.onPickInline(row); }
          });
        } else if (this.sticker.stickerSuggestions.length > 0) {
          StickerSuggestionBar({
            suggestions: this.sticker.stickerSuggestions,
            onPick: (fileId: number): void => { this.onPickSticker(fileId); }
          });
        }
      }
    }
  }

  @Builder
  private floatingActions() {
    // The latest-message FAB belongs to the chat layer. Keeping it visible
    // while the media panel is open puts it above (and blocks) the GIF tab.
    // 显隐跟着"有没有可返回的位置"走，而不是"在不在底部"：站在最新消息上
    // 但引用链还没退完时，箭头仍然该在。
    if ((this.hasReturnTarget || this.unreadMentions.count > 0) &&
      !this.search.mode && !this.showEmojiPanel && this.emojiDrawer.shellHeight <= 0) {
      Column({ space: 4 }) {
        if (this.unreadMentions.count > 0) {
          ScrollFab({ unreadCount: 0, mention: true,
            busy: this.unreadMentions.busy || this.pendingJumpId !== 0,
            iconColor: COLOR_PRIMARY, onTap: (): void => { this.unreadMentions.next(); } });
        }
        if (this.hasReturnTarget) {
          ScrollFab({
            unreadCount: this.unreadBadge,
            busy: this.scrollToBottomBusy,
            // It floats over the wallpaper, so keep the wallpaper-aware ink.
            iconColor: this.chromeIconColor,
            onTap: (): void => { this.onReturnTap(); }
          });
        }
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.End)
      .padding({ right: 14, bottom: this.bottomChromeH + 8 })
      .hitTestBehavior(HitTestMode.Transparent);
    }
  }

  build() {
    // Keep the covered chat mounted: Visibility.Hidden preserves layout,
    // scroll anchors and the thumbnail nodes used by geometryTransition.
    Stack() {
      // 背景参数由页面传入，背景内部管理渲染。
      // 聊天槽位的三根滑杆由页面按当前深浅色挑好传进去——见 ChatBackdrop 里
      // 那段说明：那一层不再自己读全局键。
      ChatBackdrop({
        chatBg: this.chatBg, screenW: this.screenW, screenH: this.screenH,
        bgBlur: this.chatBgBlur, bgPattern: this.chatBgPattern, chatDim: this.chatBgDim,
        // 分栏 + 统一背景时这层会让位给整窗那张 APP 壁纸（判据在 ChatBackdrop 里）。
        isChatSlot: true,
        active: this.surfaceActive
      });
      Column() {
        Stack() {
          this.timelineContent();
          Column() {
            this.bottomSuggestions();
            this.bottomContent();
          }
          .opacity(this.timeline.initialMessageTransitionSettled ? 1 : 0)
          .animation({
            duration: powerAnimationDuration(
              KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
            curve: Curve.EaseOut
          })
          .width('100%').height('100%')
          .justifyContent(FlexAlign.End)
          .hitTestBehavior(HitTestMode.None);

        }
        .width('100%')
        .height(this.emojiDrawer.topViewportHeight())
        .alignContent(Alignment.TopStart)
        // RESIZE changes this viewport in step with the system keyboard. The
        // area callback runs after the new List height is known, so pinning
        // here keeps message and composer motion visually locked together.
        .onAreaChange((oldArea: Area, newArea: Area) => {
          const oldH: number = typeof oldArea.height === 'number' ? oldArea.height : 0;
          const newH: number = typeof newArea.height === 'number' ? newArea.height : 0;
          this.onViewportAreaChange(oldH, newH);
        });
        this.drawerContent();
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Start)
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(Color.Transparent)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const oldH: number = typeof oldArea.height === 'number' ? oldArea.height : 0;
        const newH: number = typeof newArea.height === 'number' ? newArea.height : 0;
        this.onResizeAreaChange(oldH, newH);
      });

      // 贴纸飞出的残影。叠在最外层、不参与命中测试，纯视觉。
      if (this.overlayState.stickerGhostPath !== '') {
        Image(this.overlayState.stickerGhostPath)
          .width(STICKER_GHOST_SIDE).height(STICKER_GHOST_SIDE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .position({
            x: this.overlayState.stickerGhostX - STICKER_GHOST_SIDE / 2,
            y: this.overlayState.stickerGhostY - STICKER_GHOST_SIDE / 2
          })
          .scale({
            x: this.overlayState.stickerGhostFly ? 0.34 : 1,
            y: this.overlayState.stickerGhostFly ? 0.34 : 1
          })
          .translate({ y: this.overlayState.stickerGhostFly ? -170 : 0 })
          .opacity(this.overlayState.stickerGhostFly ? 0 : 0.95)
          .animation({ duration: STICKER_FLY_MS, curve: Curve.FastOutSlowIn })
          .hitTestBehavior(HitTestMode.None);
      }

      // **顺序就是 z 序**：Stack 里后画的在上。
      // 浮动按钮必须在覆盖层**之下**——否则右下角那颗回底箭头会压在投票/转发/
      // 联系人等底部抽屉上面（2026-11-03 用户报的「箭头盖在抽屉上」）。
      // 抽屉打开时它本来就该被遮住，而不是浮在抽屉之上。
      this.floatingActions();
      this.overlayContent();
      if (this.search.resultsOpen) {
        SearchResultsSheet({ search: this.search });
      }

    }
    .width('100%').height('100%')
    // Visibility changes must not inherit the viewer's fade animation.
    .transition(TransitionEffect.IDENTITY)
    .visibility(this.viewer.underlayHidden ? Visibility.Hidden : Visibility.Visible);
  }
}
