import { KeyboardBtn, ReplyKeyboard } from '../../store/ReplyKeyboard';
import { PendingMediaItem } from '../../util/pendingMedia';
import { attachActions } from '../../util/attachActions';
import { ChatSendAccess } from './ChatSendAccess';
import { EmojiDrawerState } from './EmojiDrawerState';
import { ComposerSession } from './ComposerSession';
import { CommandSuggestionState } from './ComposerSuggestionState';
import { VoiceRecordingState } from './VoiceRecordingState';
import { ChatComposerInput } from './ChatComposerInput';
import { ReplyKeyboardPanel } from './ReplyKeyboardPanel';
import { BottomDrawerShell } from './BottomDrawerShell';
import { AttachPanel } from './AttachPanel';
import { EmojiPanel } from './EmojiPanel';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';

// The writable bottom dock owns the composer tree and its drawers. ChatPage keeps
// session/store decisions and supplies callbacks, so search and membership docks
// remain outside this component.
@ComponentV2
export struct ChatComposerHost {
  @Require @Param composer: ComposerSession;
  @Require @Param commandSuggestion: CommandSuggestionState;
  @Require @Param recording: VoiceRecordingState;
  @Require @Param emojiDrawer: EmojiDrawerState;
  @Require @Param sendAccess: ChatSendAccess;

  @Param appDark: boolean = false;
  @Param attachPanelOpen: boolean = false;
  @Param pendingMedia: PendingMediaItem[] = [];
  @Param showEmojiPanel: boolean = false;
  @Param composerEditorReady: boolean = false;
  @Param editorFocused: boolean = false;
  @Param keyboardVisible: boolean = false;
  @Param draft: string = '';
  @Param composerPlaceholder: string = '';
  @Param composerController: TextAreaController = new TextAreaController();
  @Param sendByEnter: boolean = false;
  @Param replyKeyboard: ReplyKeyboard | null = null;
  @Param replyKbCollapsed: boolean = false;
  @Param botMiniAppUrlValue: string = '';
  @Param composerSending: boolean = false;
  @Param replyKeyboardVisible: boolean = false;
  @Param replyKeyboardSendingKey: string = '';
  @Param bottomGap: number = 0;
  @Param hasDraft: boolean = false;
  @Param accentColor: ResourceColor = Color.Transparent;
  @Param chromeIconColor: ResourceColor = Color.Transparent;
  @Param menuEffectDuration: (duration: number) => number = (duration: number): number => duration;
  @Param replyEffectDuration: (duration: number) => number = (duration: number): number => duration;
  @Param smoothEffectDuration: (duration: number) => number = (duration: number): number => duration;

  @Event onToggleAttach: () => void = (): void => {};
  @Event onRemoveMedia: (index: number) => void = (_index: number): void => {};
  @Event onMoveMedia: (from: number, to: number) => void = (_from: number, _to: number): void => {};
  @Event onClearMedia: () => void = (): void => {};
  @Event onCancelEdit: () => void = (): void => {};
  @Event onReplyTap: (messageId: number) => void = (_messageId: number): void => {};
  @Event onClearReply: () => void = (): void => {};
  @Event onCancelRecording: () => void = (): void => {};
  @Event onFinishRecording: () => void = (): void => {};
  @Event onToggleBotMenu: () => void = (): void => {};
  @Event onEmojiButtonTap: () => void = (): void => {};
  @Event onDraftChange: (value: string) => void = (_value: string): void => {};
  @Event onSubmit: () => void = (): void => {};
  @Event onEditorFocus: () => void = (): void => {};
  @Event onEditorBlur: () => void = (): void => {};
  @Event onActivateEditor: () => void = (): void => {};
  @Event onScheduleEditorMount: () => void = (): void => {};
  @Event onToggleReplyKeyboard: () => void = (): void => {};
  @Event onOpenMiniApp: () => void = (): void => {};
  @Event onRecord: () => void = (): void => {};
  @Event onSend: () => void = (): void => {};
  @Event onSendOptions: () => void = (): void => {};
  @Event onHeightChange: (height: number) => void = (_height: number): void => {};

  @Builder
  buildComposer() {
    Column() {
      ChatComposerInput({
        appDark: this.appDark,
        attachPanelOpen: this.attachPanelOpen,
        pendingMedia: this.pendingMedia,
        composer: this.composer,
        commandSuggestion: this.commandSuggestion,
        recording: this.recording,
        showEmojiPanel: this.showEmojiPanel,
        composerEditorReady: this.composerEditorReady,
        editorFocused: this.editorFocused,
        keyboardVisible: this.keyboardVisible,
        draft: this.draft,
        composerPlaceholder: this.composerPlaceholder,
        composerController: this.composerController,
        sendByEnter: this.sendByEnter,
        replyKeyboard: this.replyKeyboard,
        replyKbCollapsed: this.replyKbCollapsed,
        botMiniAppUrlValue: this.botMiniAppUrlValue,
        composerSending: this.composerSending,
        replyKeyboardVisible: this.replyKeyboardVisible,
        bottomGap: this.bottomGap,
        hasDraft: this.hasDraft,
        accentColor: this.accentColor,
        chromeIconColor: this.chromeIconColor,
        onToggleAttach: this.onToggleAttach,
        onRemoveMedia: this.onRemoveMedia,
        onMoveMedia: this.onMoveMedia,
        onClearMedia: this.onClearMedia,
        onCancelEdit: this.onCancelEdit,
        onReplyTap: this.onReplyTap,
        onClearReply: this.onClearReply,
        onCancelRecording: this.onCancelRecording,
        onFinishRecording: this.onFinishRecording,
        onToggleBotMenu: this.onToggleBotMenu,
        onEmojiButtonTap: this.onEmojiButtonTap,
        onDraftChange: this.onDraftChange,
        onSubmit: this.onSubmit,
        onEditorFocus: this.onEditorFocus,
        onEditorBlur: this.onEditorBlur,
        onActivateEditor: this.onActivateEditor,
        onScheduleEditorMount: this.onScheduleEditorMount,
        onToggleReplyKeyboard: this.onToggleReplyKeyboard,
        onOpenMiniApp: this.onOpenMiniApp,
        onRecord: this.onRecord,
        onSend: this.onSend,
        onSendOptions: this.onSendOptions,
        menuEffectDuration: this.menuEffectDuration,
        replyEffectDuration: this.replyEffectDuration,
        smoothEffectDuration: this.smoothEffectDuration
      });
      if (this.replyKeyboardVisible && this.replyKeyboard !== null) {
        ReplyKeyboardPanel({
          rows: this.replyKeyboard.rows,
          sendingKey: this.replyKeyboardSendingKey,
          resize: this.replyKeyboard.resize,
          bottomGap: this.bottomGap,
          enterDuration: this.menuEffectDuration(190),
          onTap: (button: KeyboardBtn, key: string): void => {
            this.onReplyKeyboardTap(button, key);
          }
        });
      }
    }
    .width('100%')
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      if (typeof size.height === 'number') {
        this.emojiDrawer.measureComposer(size.height);
      }
    })
    .onAreaChange((_old: Area, area: Area): void => {
      if (typeof area.height === 'number') { this.onHeightChange(area.height); }
    });
  }

  private onReplyKeyboardTap(button: KeyboardBtn, key: string): void {
    // Reply-keyboard sending remains a ChatPage business action.
    this.onReplyKeyboardButton(button, key);
  }

  @Event onReplyKeyboardButton: (button: KeyboardBtn, key: string) => void =
    (_button: KeyboardBtn, _key: string): void => {};

  build() {
    this.buildComposer();
  }
}

@ComponentV2
export struct ChatBottomDrawerHost {
  @Require @Param emojiDrawer: EmojiDrawerState;
  @Require @Param sendAccess: ChatSendAccess;
  @Param attachPanelOpen: boolean = false;
  @Param showEmojiPanel: boolean = false;
  @Param panelContentReady: boolean = false;
  @Param emojiPanelClosing: boolean = false;
  @Param emojiPanelTab: number = 0;
  @Param bottomSafe: number = 0;
  @Param drawerHeight: number = 260;
  @Param accentColor: ResourceColor = Color.Transparent;
  @Param chatId: number = 0;
  @Param isGroup: boolean = false;
  @Param isChannel: boolean = false;
  @Param menuEffectDuration: (duration: number) => number = (duration: number): number => duration;

  @Event onAttachPick: (key: string) => void = (_key: string): void => {};
  @Event onEmojiPick: (emoji: string) => void = (_emoji: string): void => {};
  @Event onCustomEmojiPick: (emoji: string, customEmojiId: string) => void =
    (_emoji: string, _customEmojiId: string): void => {};
  @Event onStickerPick: (sticker: StickerItem, x: number, y: number) => void =
    (_sticker: StickerItem, _x: number, _y: number): void => {};
  @Event onGifPick: (gif: GifItem) => void = (_gif: GifItem): void => {};
  @Event onEmojiTabChange: (tab: number) => void = (_tab: number): void => {};
  @Event onEmojiExpanded: (expanded: boolean) => void = (_expanded: boolean): void => {};

  @LocalBuilder
  attachDrawerContent() {
    AttachPanel({
      actions: attachActions(this.isGroup, this.isChannel),
      disabledKeys: this.sendAccess.disabledAttachments(),
      onPick: (key: string): void => { this.onAttachPick(key); },
      effectDuration: this.menuEffectDuration
    });
  }

  @LocalBuilder
  emojiDrawerContent() {
    if (this.panelContentReady) {
      EmojiPanel({
        active: this.showEmojiPanel,
        panelHeight: this.drawerHeight,
        expanded: this.emojiDrawer.expanded,
        onExpanded: (expanded: boolean): void => { this.onEmojiExpanded(expanded); },
        tab: this.emojiPanelTab,
        mediaAllowed: this.sendAccess.allows('sendOtherMessages'),
        chatId: this.chatId,
        onTabChange: (tab: number): void => { this.onEmojiTabChange(tab); },
        onPick: (emoji: string): void => { this.onEmojiPick(emoji); },
        onPickCustomEmoji: (emoji: string, customEmojiId: string): void => {
          this.onCustomEmojiPick(emoji, customEmojiId);
        },
        onPickSticker: (sticker: StickerItem, x: number, y: number): void => {
          this.onStickerPick(sticker, x, y);
        },
        onPickGif: (gif: GifItem): void => { this.onGifPick(gif); }
      });
    } else {
      Column()
        .width('100%')
        .height('100%');
    }
  }

  build() {
    Column() {
      if (this.emojiDrawer.activeSlot === 'attach' && this.emojiDrawer.shellHeight > 0) {
        BottomDrawerShell({
          bottomSafe: this.bottomSafe,
          topOverlap: this.emojiDrawer.topOverlap(this.bottomSafe),
          shellHeight: this.emojiDrawer.shellHeight,
          cardOffsetY: this.emojiDrawer.cardOffsetY,
          cardOpacity: this.emojiDrawer.cardOpacity,
          content: this.attachDrawerContent
        });
      }
      if (this.panelContentReady || (this.emojiDrawer.activeSlot === 'emoji' && this.emojiDrawer.shellHeight > 0)) {
        Column() {
          BottomDrawerShell({
            bottomSafe: this.bottomSafe,
            drawerHeight: this.drawerHeight,
            topOverlap: this.emojiDrawer.topOverlap(this.bottomSafe),
            shellHeight: this.emojiDrawer.activeSlot === 'emoji' ? this.emojiDrawer.shellHeight : 0,
            cardOffsetY: this.emojiDrawer.cardOffsetY,
            cardOpacity: this.emojiDrawer.cardOpacity,
            content: this.emojiDrawerContent
          });
        }
        .width('100%')
        .visibility(this.emojiDrawer.activeSlot === 'emoji' && this.emojiDrawer.shellHeight > 0
          ? Visibility.Visible : Visibility.None);
      }
    }
    .width('100%');
  }
}
