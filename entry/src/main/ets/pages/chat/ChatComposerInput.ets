import { ReplyKeyboard } from '../../store/ReplyKeyboard';
import { PendingMediaItem, hasPendingMedia } from '../../util/pendingMedia';
import { COLOR_ICON_SECONDARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
import { EditStrip, ReplyStrip } from './ComposerStrip';
import { MediaStrip } from './MediaStrip';
import { ComposerSendButton } from './ComposerSendButton';

// Shared geometry for the editor and its height measurement in ChatPage.
export const COMPOSER_LINE_HEIGHT: number = 22;
export const COMPOSER_EDITOR_PADDING: number = 9;
export const COMPOSER_MAX_LINES: number = 4;

// Input-area presentation. ChatPage remains the owner of all state machines,
// store actions, and keyboard/IME coordination; this component only renders
// the tree and forwards UI events.
@ComponentV2
export struct ChatComposerInput {
  @Param isRecording: boolean = false;
  @Param attachPanelOpen: boolean = false;
  @Param pendingMedia: PendingMediaItem[] = [];
  @Param editingId: number = 0;
  @Param editingKind: string = 'text';
  @Param editingPreview: string = '';
  @Param replyToId: number = 0;
  @Param replyToName: string = '';
  @Param replyToText: string = '';
  @Param replyToThumb: string = '';
  @Param replyToThumbSticker: boolean = false;
  @Param botMenuAvailable: boolean = false;
  @Param commandMenuOpen: boolean = false;
  @Param showEmojiPanel: boolean = false;
  @Param composerEditorReady: boolean = false;
  @Param draft: string = '';
  @Param composerPlaceholder: string = '';
  @Param composerController: TextAreaController = new TextAreaController();
  @Param composerEditorHeight: number = COMPOSER_LINE_HEIGHT + COMPOSER_EDITOR_PADDING * 2;
  @Param sendByEnter: boolean = false;
  @Param replyKeyboard: ReplyKeyboard | null = null;
  @Param replyKbCollapsed: boolean = false;
  @Param botMiniAppUrlValue: string = '';
  @Param recordingStarting: boolean = false;
  @Param composerSending: boolean = false;
  @Param replyKeyboardVisible: boolean = false;
  @Param bottomGap: number = 0;
  @Param hasDraft: boolean = false;
  @Param accentColor: ResourceColor = Color.Transparent;
  @Param chromeIconColor: ResourceColor = Color.Transparent;

  @Event onToggleAttach: () => void = (): void => {};
  @Event onRemoveMedia: (index: number) => void = (): void => {};
  @Event onMoveMedia: (from: number, to: number) => void = (): void => {};
  @Event onClearMedia: () => void = (): void => {};
  @Event onCancelEdit: () => void = (): void => {};
  @Event onReplyTap: (messageId: number) => void = (): void => {};
  @Event onClearReply: () => void = (): void => {};
  @Event onCancelRecording: () => void = (): void => {};
  @Event onFinishRecording: () => void = (): void => {};
  @Event onToggleBotMenu: () => void = (): void => {};
  @Event onEmojiButtonArea: (centerX: number) => void = (): void => {};
  @Event onEmojiButtonTap: () => void = (): void => {};
  @Event onEditorWidthChange: (width: number) => void = (): void => {};
  @Event onDraftChange: (value: string) => void = (): void => {};
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
  @Event onInputBarHeightChange: (height: number) => void = (): void => {};
  @Event menuEffectDuration: (duration: number) => number =
    (duration: number): number => duration;
  @Event replyEffectDuration: (duration: number) => number =
    (duration: number): number => duration;
  @Event smoothEffectDuration: (duration: number) => number =
    (duration: number): number => duration;
  @Param recordingSecondsLabel: string = '';

  @Styles
  composerIconNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerIconPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Styles
  composerPrimaryNormalStyle() {
    .backgroundColor(this.accentColor)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerPrimaryPressedStyle() {
    .backgroundColor('#287BC8')
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  build() {
    Row({ space: 6 }) {
      // The attachment action stays outside the growing text capsule.
      if (!this.isRecording) {
        Stack() {
          SymbolGlyph($r('sys.symbol.paperclip'))
            .fontSize(23)
            .fontColor([this.attachPanelOpen ? this.accentColor : this.chromeIconColor])
            .opacity(this.attachPanelOpen ? 0 : 1)
            .rotate({ angle: this.attachPanelOpen ? 45 : 0 })
            .animation({
              duration: this.menuEffectDuration(150),
              curve: Curve.EaseOut
            });
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(21)
            .fontColor([this.accentColor])
            .opacity(this.attachPanelOpen ? 1 : 0)
            .rotate({ angle: this.attachPanelOpen ? 0 : -45 })
            .animation({
              duration: this.menuEffectDuration(150),
              curve: Curve.EaseOut
            });
        }
        .width(46)
        .height(46)
        .borderRadius(23)
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 1 })
        // 玻璃自绘（plainGlassFill + plainBackdropBlur：明确不指望材质，
        // 组件级 systemMaterial 已被系统收回），光感走 hdsEffect 的 visualEffect
        // ——那是另一条通道，6.0.0(20) 起，见 util/hdsPointLight。
        // 这颗是**控件**，走 'control' 档：只有那一档同时给点光源和按压阴影。
        .backgroundColor(plainGlassFill($r('app.color.surface')))
        .backdropBlur(plainBackdropBlur('control'))
        .visualEffect(hdsVisualEffect('control'))
        .onClick((): void => { this.onToggleAttach(); });
      }
      Column() {
        if (hasPendingMedia(this.pendingMedia)) {
          MediaStrip({
            items: this.pendingMedia,
            onRemoveAt: (index: number): void => { this.onRemoveMedia(index); },
            onMove: (from: number, to: number): void => { this.onMoveMedia(from, to); },
            onCancel: (): void => { this.onClearMedia(); }
          });
        }
        if (this.editingId !== 0) {
          EditStrip({
            editingKind: this.editingKind,
            preview: this.editingPreview,
            onCancel: (): void => { this.onCancelEdit(); }
          });
        } else if (this.replyToId !== 0) {
          ReplyStrip({
            name: this.replyToName,
            snippet: this.replyToText,
            thumbPath: this.replyToThumb,
            thumbSticker: this.replyToThumbSticker,
            enterDuration: this.replyEffectDuration(180),
            onTapQuote: (): void => { this.onReplyTap(this.replyToId); },
            onCancel: (): void => { this.onClearReply(); }
          });
        }
        Row({ space: 6 }) {
          if (this.isRecording) {
            Row({ space: 7 }) {
              Circle({ width: 8, height: 8 }).fill('#FF3B30');
              Text(this.recordingSecondsLabel).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
              Text($r('app.string.cp_recording')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
            }.layoutWeight(1).alignItems(VerticalAlign.Center);
            Button($r('app.string.cancel')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .stateStyles({
                normal: this.composerIconNormalStyle,
                pressed: this.composerIconPressedStyle
              })
              .animation({ duration: this.smoothEffectDuration(120), curve: Curve.EaseOut })
              .onClick((): void => { this.onCancelRecording(); });
            Button() {
              SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White]);
            }
            .width(40).height(40).borderRadius(20)
            .stateStyles({
              normal: this.composerPrimaryNormalStyle,
              pressed: this.composerPrimaryPressedStyle
            })
            .animation({ duration: this.smoothEffectDuration(120), curve: Curve.EaseOut })
            .onClick((): void => { this.onFinishRecording(); });
          } else {
            if (this.botMenuAvailable) {
              Row({ space: 4 }) {
                SymbolGlyph($r(this.commandMenuOpen ? 'sys.symbol.xmark' : 'sys.symbol.line_3_horizontal'))
                  .fontSize(15).fontColor([Color.White]);
                Text(this.commandMenuOpen ? $r('app.string.close') : $r('app.string.cp_menu'))
                  .fontSize(13).fontColor(Color.White);
              }
              .padding({ left: 9, right: 10, top: 6, bottom: 6 })
              .borderRadius(15)
              .stateStyles({
                normal: this.composerPrimaryNormalStyle,
                pressed: this.composerPrimaryPressedStyle
              })
              .animation({ duration: this.smoothEffectDuration(120), curve: Curve.EaseOut })
              .onClick((): void => { this.onToggleBotMenu(); });
            }
            SymbolGlyph($r(this.showEmojiPanel ? 'sys.symbol.face_smiling_fill' : 'sys.symbol.face_smiling'))
              .fontSize(24)
              .fontColor([this.showEmojiPanel ? this.accentColor : this.chromeIconColor])
              .onAreaChange((_old: Area, area: Area): void => {
                const gx: number = area.globalPosition.x as number;
                this.onEmojiButtonArea(gx + (area.width as number) / 2);
              })
              .onClick((): void => { this.onEmojiButtonTap(); });
            if (this.composerEditorReady) {
              TextArea({
                text: this.draft,
                placeholder: this.composerPlaceholder,
                controller: this.composerController
              })
                .layoutWeight(1)
                .height(this.composerEditorHeight)
                .maxLength(4096)
                .fontSize(15)
                .lineHeight(COMPOSER_LINE_HEIGHT)
                .fontColor(COLOR_TEXT_PRIMARY)
                .caretColor(this.accentColor)
                .padding({
                  left: 3, right: 3,
                  top: COMPOSER_EDITOR_PADDING, bottom: COMPOSER_EDITOR_PADDING
                })
                .barState(BarState.Auto)
                .backgroundColor(Color.Transparent)
                .key('chat_composer')
                .onAreaChange((_old: Area, area: Area): void => {
                  const next: number = area.width as number;
                  this.onEditorWidthChange(next);
                })
                .onChange((value: string): void => { this.onDraftChange(value); })
                .enterKeyType(this.sendByEnter ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
                .onSubmit((): void => { this.onSubmit(); })
                .onFocus((): void => { this.onEditorFocus(); })
                .onBlur((): void => { this.onEditorBlur(); });
            } else {
              Text(this.draft !== '' ? this.draft : this.composerPlaceholder)
                .layoutWeight(1)
                .height(this.composerEditorHeight)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontSize(15)
                .lineHeight(COMPOSER_LINE_HEIGHT)
                .fontColor(this.draft !== '' ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
                .padding({
                  left: 3, right: 3,
                  top: COMPOSER_EDITOR_PADDING, bottom: COMPOSER_EDITOR_PADDING
                })
                .backgroundColor(Color.Transparent)
                .key('chat_composer_placeholder')
                .accessibilityText(this.composerPlaceholder)
                .onClick((): void => { this.onActivateEditor(); })
                .onAppear((): void => { this.onScheduleEditorMount(); });
            }
            if (this.replyKeyboard !== null) {
              Row() {
                SymbolGlyph($r('sys.symbol.keyboard'))
                  .fontSize(21)
                  .fontColor([this.replyKbCollapsed ? COLOR_ICON_SECONDARY : this.accentColor]);
              }
              .width(34).height(34).borderRadius(17)
              .justifyContent(FlexAlign.Center)
              .stateStyles({
                normal: this.composerIconNormalStyle,
                pressed: this.composerIconPressedStyle
              })
              .animation({ duration: this.smoothEffectDuration(110), curve: Curve.EaseOut })
              .accessibilityText(this.replyKbCollapsed
                ? $r('app.string.cp_open_bot_keyboard') : $r('app.string.cp_switch_to_text'))
              .onClick((): void => { this.onToggleReplyKeyboard(); });
            }
            if (this.botMiniAppUrlValue !== '') {
              SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                .fontSize(22).fontColor([this.accentColor])
                .accessibilityText($r('app.string.cp_open_miniapp'))
                .onClick((): void => { this.onOpenMiniApp(); });
            }
            ComposerSendButton({
              hasDraft: this.hasDraft,
              recordingStarting: this.recordingStarting,
              sending: this.composerSending,
              onRecord: (): void => { this.onRecord(); },
              onSend: (): void => { this.onSend(); },
              onSendOptions: (): void => { this.onSendOptions(); }
            });
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 48, maxHeight: 120 })
        .padding({ left: 12, right: 4, top: 4, bottom: 4 })
        .alignItems(VerticalAlign.Center);
      }
      .layoutWeight(1)
      .backgroundColor(plainGlassFill($r('app.color.surface')))
      .borderRadius(24)
      .backdropBlur(plainBackdropBlur('card'))
      // 'card' 档：给点光源、不给按压阴影——整块面板跟着手指变形很怪，
      // 这条判据在 overlayMaterial.interactionBase 里，和材质那条路共用。
      .visualEffect(hdsVisualEffect('card'));
    }
    .width('100%')
    .padding({
      left: 14,
      right: 14,
      top: 6,
      bottom: this.replyKeyboardVisible ? 8 : this.bottomGap
    })
    .alignItems(VerticalAlign.Center)
    .onAreaChange((_old: Area, area: Area): void => {
      this.onInputBarHeightChange(area.height as number);
    });
  }
}
