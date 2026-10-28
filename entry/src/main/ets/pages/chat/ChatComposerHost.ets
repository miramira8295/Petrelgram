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
  @Param panelContentReady: boolean = false;
  @Param emojiPanelClosing: boolean = false;
  @Param emojiPanelTab: number = 0;
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
  @Param bottomSafe: number = 0;
  @Param drawerHeight: number = 260;
  @Param hasDraft: boolean = false;
  @Param accentColor: ResourceColor = Color.Transparent;
  @Param chromeIconColor: ResourceColor = Color.Transparent;
  @Param chatId: number = 0;
  @Param isGroup: boolean = false;
  @Param isChannel: boolean = false;
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
  @Event onAttachPick: (key: string) => void = (_key: string): void => {};
  @Event onEmojiPick: (emoji: string) => void = (_emoji: string): void => {};
  @Event onCustomEmojiPick: (emoji: string, customEmojiId: string) => void =
    (_emoji: string, _customEmojiId: string): void => {};
  @Event onStickerPick: (sticker: StickerItem, x: number, y: number) => void =
    (_sticker: StickerItem, _x: number, _y: number): void => {};
  @Event onGifPick: (gif: GifItem) => void = (_gif: GifItem): void => {};
  @Event onEmojiTabChange: (tab: number) => void = (_tab: number): void => {};
  @Event onEmojiExpanded: (expanded: boolean) => void = (_expanded: boolean): void => {};
  @Event onHeightChange: (height: number) => void = (_height: number): void => {};

  // 传给 BottomDrawerShell 的内容必须保持宿主绑定，不能改成普通 @Builder。
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
    } else if (!this.emojiPanelClosing) {
      Column({ space: 8 }) {
        LoadingProgress().width(26).height(26).color(this.accentColor);
        Text($r('app.string.cp_opening_panel')).fontSize(13)
          .fontColor($r('app.color.text_secondary'));
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center);
    }
  }

  @Builder
  bottomDrawer() {
    if (this.attachPanelOpen) {
      BottomDrawerShell({ bottomSafe: this.bottomSafe, content: this.attachDrawerContent });
    } else if (this.showEmojiPanel) {
      BottomDrawerShell({
        bottomSafe: this.bottomSafe,
        drawerHeight: this.drawerHeight,
        content: this.emojiDrawerContent
      });
    }
  }

  @Builder
  buildComposer() {
    Column() {
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
      });
      if (this.attachPanelOpen || this.showEmojiPanel) {
        this.bottomDrawer();
      }
    }
    .width('100%')
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
