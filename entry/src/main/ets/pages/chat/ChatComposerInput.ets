import { ReplyKeyboard } from '../../store/ReplyKeyboard';
import { logE } from '../../util/log';
import { PendingMediaItem, hasPendingMedia } from '../../util/pendingMedia';
import { COLOR_ICON_SECONDARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
import { EditStrip, ReplyStrip } from './ComposerStrip';
import { MediaStrip } from './MediaStrip';
import { ComposerSendButton } from './ComposerSendButton';
import { ComposerSession } from './ComposerSession';
import { CommandSuggestionState } from './ComposerSuggestionState';
import { VoiceRecordingState } from './VoiceRecordingState';

// Shared geometry for the editor and its height measurement, both in this file.
//
// These three have to agree with the TextArea's own lineHeight/padding: the
// editor height is computed from them, and a mismatch clips the last line
// instead of scrolling to it. (原注释留在 ChatPage.ets 顶部成了孤儿——那三个
// 常量搬到这个文件时它没跟来，2026-09-05 瘦身批 B1 归位。)
export const COMPOSER_LINE_HEIGHT: number = 22;
export const COMPOSER_EDITOR_PADDING: number = 9;
export const COMPOSER_MAX_LINES: number = 4;

// Input-area presentation. ChatPage remains the owner of all state machines,
// store actions, and keyboard/IME coordination; this component only renders
// the tree and forwards UI events.
@ComponentV2
export struct ChatComposerInput {
  @Param attachPanelOpen: boolean = false;
  @Param pendingMedia: PendingMediaItem[] = [];
  // 输入条上方那一条（编辑态/回复态）的八个字段原来是八个标量 @Param，由
  // ChatPage 在 build 里逐个转手——那等于让**页面**订阅这八个 @Trace，编辑/回复
  // 一开一关就重跑整个页面的 build，本组件想要的「只重渲染这一条」根本拿不到
  //（B9 只把字段搬进了控制器，收益停在行数上）。改成直接接控制器本身（B9b）：
  // 页面 build 里只读 this.composer 这个普通私有字段（引用恒定、不是 @Trace，
  // 不建立依赖），八个 @Trace 的读点全部下沉到本组件自己的 build 里，翻转只脏
  // 本组件这一棵子树。
  //
  // @Require：没有合理的默认实例可给（控制器是 per-ChatPage 的，做成模块级
  // 单例会让平板分栏时两个会话串味），漏传必须是编译期错误，而不是静默拿到一个
  // 谁也不会更新的空壳。
  @Require @Param composer: ComposerSession;
  // botMenuAvailable/commandMenuOpen 原来也是两个标量 @Param（同上一段注释里
  // composer 那次改造之前的样子）。B14 把它们的持有者搬进了 CommandSuggestionState，
  // 这里跟着直接接控制器本身，两个读点下沉到本组件自己的 build 里，理由同 composer。
  @Require @Param commandSuggestion: CommandSuggestionState;
  // isRecording/recordingStarting/recordingSecondsLabel 原来是三个标量
  // @Param，由 ChatPage 在 build 里逐个转手（isRecording/recordingStarting
  // 是页面 @Local，recordingSecondsLabel 是页面每次 build 现算的
  // formatRecSeconds() 字符串）——同一个"页面订阅、组件收益停在行数"的形状
  // 第三次出现（侦察报告 3）。改接控制器本身：isRecording/recordingStarting
  // 两个读点、以及 recordingSecondsLabel 改为本组件自己调
  // `this.recording.secondsLabel()`，全部下沉到本组件自己的 build 里，理由
  // 同 composer/commandSuggestion。
  @Require @Param recording: VoiceRecordingState;
  @Param showEmojiPanel: boolean = false;
  @Param composerEditorReady: boolean = false;
  @Param draft: string = '';
  @Param composerPlaceholder: string = '';
  @Param composerController: TextAreaController = new TextAreaController();
  // 输入框的真实宽度，editorHeight() 拿它做排版约束。原来是绕一圈的：本组件
  // onAreaChange 量到 → @Event 送回 ChatPage 存进 @Local composerEditorW →
  // 页面算好高度 → 再作为 @Param composerEditorHeight 传回本组件。中间那一圈
  // 页面什么也没做，第二轮第 9 项把它收回原地（三个几何常量本来就定义在本文件）。
  @Local private editorW: number = 0;
  @Param sendByEnter: boolean = false;
  @Param replyKeyboard: ReplyKeyboard | null = null;
  @Param replyKbCollapsed: boolean = false;
  @Param botMiniAppUrlValue: string = '';
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
  @Event onEmojiButtonTap: () => void = (): void => {};
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
  @Event menuEffectDuration: (duration: number) => number =
    (duration: number): number => duration;
  @Event replyEffectDuration: (duration: number) => number =
    (duration: number): number => duration;
  @Event smoothEffectDuration: (duration: number) => number =
    (duration: number): number => duration;

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

  // TextArea's intrinsic minimum is taller than the old 48vp input capsule on
  // some phones/font scales. Give it an explicit content-driven height so the
  // empty composer keeps the original silhouette and only grows after typing.
  //
  // The cap is derived from the real line box rather than a round number: at
  // lineHeight 22 and 9+9 padding, four lines need 106vp. The old cap of 104
  // was six short, so the fourth line was already clipped — and past the cap
  // the TextArea has to scroll internally, which it can only do if nothing
  // truncates the layout (see the removed maxLines at the call site).
  private editorHeight(): number {
    const oneLine: number = COMPOSER_LINE_HEIGHT + COMPOSER_EDITOR_PADDING * 2;
    const cap: number = COMPOSER_LINE_HEIGHT * COMPOSER_MAX_LINES + COMPOSER_EDITOR_PADDING * 2;
    if (this.draft === '' || this.editorW <= 0) {
      return oneLine;
    }
    // 真实测量，不再按"每行 18 个字"硬估。
    //
    // 那个 18 是拍的：一行能装多少字取决于屏宽、字号缩放和中英文混排，在宽屏
    // 上实际只装得下约 15 个，于是第 16 个字文本已经换行、而 ceil(16/18) 仍是
    // 1，盒子要等到第 19 个字才长高——表现为"输到第二行第 4 个字才展开"
    // （Mate 80 Pro Max 稳定复现）。
    //
    // TextArea 本身是自适应内容高度的（不设 height 时），这里之所以还锁着
    // 高度，是因为它的固有最小高度在某些机型/字号下比一行还高，空输入框会
    // 变胖（见下方 .height 调用点的原注释）。所以保留显式高度，只把估算换成
    // measureTextSize —— 它按给定的约束宽度做真实排版，返回的高度已经算好了
    // 换行。
    let measured: number = oneLine;
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: this.draft,
        fontSize: 15,
        lineHeight: COMPOSER_LINE_HEIGHT,
        // 左右各 3 的内边距要从可用宽度里扣掉，否则会少算一行。
        constraintWidth: Math.max(1, this.editorW - 6)
      });
      // measureTextSize 返回的是 px。
      measured = px2vp(size.height as number) + COMPOSER_EDITOR_PADDING * 2;
    } catch (e) {
      // 量不出来就退回一行，宁可矮也不要抖：TextArea 超出部分自己能滚。
      logE(`editorHeight measure failed: ${(e as Error).message}`);
    }
    return Math.max(oneLine, Math.min(cap, Math.ceil(measured)));
  }

  build() {
    Row({ space: 6 }) {
      // The attachment action stays outside the growing text capsule.
      if (!this.recording.isRecording) {
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
        if (this.composer.editingId !== 0) {
          EditStrip({
            editingKind: this.composer.editingKind,
            preview: this.composer.editingPreview,
            onCancel: (): void => { this.onCancelEdit(); }
          });
        } else if (this.composer.replyToId !== 0) {
          ReplyStrip({
            name: this.composer.replyToName,
            snippet: this.composer.replyToText,
            thumbPath: this.composer.replyToThumb,
            thumbSticker: this.composer.replyToThumbSticker,
            enterDuration: this.replyEffectDuration(180),
            onTapQuote: (): void => { this.onReplyTap(this.composer.replyToId); },
            onCancel: (): void => { this.onClearReply(); }
          });
        }
        Row({ space: 6 }) {
          if (this.recording.isRecording) {
            Row({ space: 7 }) {
              Circle({ width: 8, height: 8 }).fill('#FF3B30');
              Text(this.recording.secondsLabel()).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
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
            if (this.commandSuggestion.botMenuAvailable) {
              Row({ space: 4 }) {
                SymbolGlyph($r(this.commandSuggestion.commandMenuOpen ? 'sys.symbol.xmark' : 'sys.symbol.line_3_horizontal'))
                  .fontSize(15).fontColor([Color.White]);
                Text(this.commandSuggestion.commandMenuOpen ? $r('app.string.close') : $r('app.string.cp_menu'))
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
              .onClick((): void => { this.onEmojiButtonTap(); });
            if (this.composerEditorReady) {
              TextArea({
                text: this.draft,
                placeholder: this.composerPlaceholder,
                controller: this.composerController
              })
                .layoutWeight(1)
                .height(this.editorHeight())
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
                  // 0.5vp 以内的抖动不写：宽度是排版约束，写一次就要重算一次高度。
                  if (Math.abs(next - this.editorW) > 0.5) {
                    this.editorW = next;
                  }
                })
                .onChange((value: string): void => { this.onDraftChange(value); })
                .enterKeyType(this.sendByEnter ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
                .onSubmit((): void => { this.onSubmit(); })
                .onFocus((): void => { this.onEditorFocus(); })
                .onBlur((): void => { this.onEditorBlur(); });
            } else {
              Text(this.draft !== '' ? this.draft : this.composerPlaceholder)
                .layoutWeight(1)
                .height(this.editorHeight())
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
              recordingStarting: this.recording.recordingStarting,
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
    .alignItems(VerticalAlign.Center);
  }
}
