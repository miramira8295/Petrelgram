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
// 量不到行高时的兜底值（默认字体下一行约 22vp）。
// **不再用它去规定 .lineHeight()** —— 见 TextArea 那处注释。
export const COMPOSER_LINE_HEIGHT: number = 22;
export const COMPOSER_EDITOR_PADDING: number = 9;
export const COMPOSER_MAX_LINES: number = 4;
// 输入条那一行自己的上下内边距。进 minHeight/maxHeight 的推导，别再手算。
export const COMPOSER_ROW_PADDING: number = 4;

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
  // TextArea 自己报的真实行数（0 = 还没问到）。见 refreshEditorLines。
  @Local private editorLines: number = 0;
  private linesRefreshTimer: number = -1;
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
  // 一行有多高（**vp**）。
  //
  // 【为什么不能直接用 COMPOSER_LINE_HEIGHT】那是给 .lineHeight() 的数字，而
  // ArkUI 文档写明「未指定单位时默认是 fp」——fp 跟随系统字号缩放，vp 不跟。
  // 而 .padding() 的数字是 vp。原来 `lines * 22 + 9 * 2` 把两种单位直接相加：
  // 缩放 1.3 时真实一行是 28.6vp，三行 3×28.6+18 = 103.8vp，我们却只给了
  // 3×22+18 = 84vp —— 第三行连同光标被切在盒子外面，TextArea 内部滚动去追光标，
  // 看着就是「文字闪一下 / 光标不见了」。这和换了哪款字体无关，只跟字号缩放有关
  // （两者在系统设置里挨着，通常一起改）。
  //
  // 量一次就知道真实值：measureTextSize 按当前字号缩放排版，返回 px，换成 vp。
  private lineHeightVp(): number {
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: 'A',
        fontSize: 15
      });
      const measured: number = px2vp(size.height as number);
      return measured > 0 ? measured : COMPOSER_LINE_HEIGHT;
    } catch (e) {
      return COMPOSER_LINE_HEIGHT;
    }
  }

  // 输入条那一行的高度上下限。
  //
  // 【为什么要算而不是写死】原来是 `{ minHeight: 48, maxHeight: 120 }` 两个字面量
  // ——48 正好是 22 + 9×2 + 4×2，也就是按字号缩放 1.0 手算出来的一行高。而
  // editorHeight() 现在按**真实行高**（fp，跟随系统字号）算，两边就会打架：缩放
  // 1.3 时四行要 4×28.6+18 = 132vp，容器却只给得起 120−8 = 112vp，第四行连同
  // 光标被硬生生切掉——用户报的"还是有文字被隐藏"就是这个。
  // 现在两个数都从同一个 lineHeightVp() 推出来，不可能再不一致。
  private rowMinHeight(): number {
    return this.lineHeightVp() + COMPOSER_EDITOR_PADDING * 2 + COMPOSER_ROW_PADDING * 2;
  }

  private rowMaxHeight(): number {
    return this.lineHeightVp() * COMPOSER_MAX_LINES +
      COMPOSER_EDITOR_PADDING * 2 + COMPOSER_ROW_PADDING * 2;
  }

  private editorHeight(): number {
    const lineVp: number = this.lineHeightVp();
    const oneLine: number = lineVp + COMPOSER_EDITOR_PADDING * 2;
    const cap: number = lineVp * COMPOSER_MAX_LINES + COMPOSER_EDITOR_PADDING * 2;
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
    let estimatedLines: number = 1;
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: this.draft,
        fontSize: 15,
        // 同样不带 lineHeight：要和 TextArea 的实际排版用同一套参数，
        // 否则估算和真实换行位置从一开始就对不上。
        // 左右各 3 的内边距要从可用宽度里扣掉，否则会少算一行。
        constraintWidth: Math.max(1, this.editorW - 6)
      });
      // measureTextSize 返回的是 px。
      // 除的是量出来的真实行高，不是那个 fp 常量。
      estimatedLines = Math.ceil(px2vp(size.height as number) / lineVp);
    } catch (e) {
      // 量不出来就退回一行，宁可矮也不要抖：TextArea 超出部分自己能滚。
      logE(`editorHeight measure failed: ${(e as Error).message}`);
    }
    // 【为什么要和 editorLines 取大】measureTextSize **不知道系统字体**：它按默认
    // 字体排版，而 TextArea 渲染用的是用户在系统设置里选的那一款。字宽一差，
    // 同样的约束宽度下换行位置就不同，偏差随字数累积——用户报的正是"非默认字体
    // 时，超过三行会连同光标一起闪动或消失"：估算说 3 行、真实排了 4 行，盒子
    // 按 3 行开，第 4 行连同光标被切在盒子外面，TextArea 内部滚动去追光标，看着
    // 就是闪一下或者不见了。
    //
    // 与其猜字体（系统字体名拿不到，TextArea 自己也没设 fontFamily），不如直接
    // 问排了版的那个组件：TextAreaController 继承 TextContentControllerBase，
    // 有 getTextContentLineCount()。估算负责即时响应（不等下一帧），真实行数负责
    // 兜底纠偏，取大保证光标永远在盒子里。
    const lines: number = Math.max(1,
      Math.min(COMPOSER_MAX_LINES, Math.max(estimatedLines, this.editorLines)));
    return Math.max(oneLine, Math.min(cap, lines * lineVp + COMPOSER_EDITOR_PADDING * 2));
  }

  aboutToDisappear(): void {
    if (this.linesRefreshTimer !== -1) {
      clearTimeout(this.linesRefreshTimer);
      this.linesRefreshTimer = -1;
    }
  }

  // 隔一帧再问一次真实行数。
  //
  // 【为什么必须有这条，不能只在 onAreaChange 里问】(2026-09-11 真机截图定位)
  // 真实行数原来只在「盒子高度变过」时才刷新，可高度是**按估算算的**：估算说
  // 1 行、真实排了 2 行时，高度压根不变 ⇒ onAreaChange 不触发 ⇒ 永远学不到真相，
  // 自锁。用户看到的是输入框只有一行高、内部却滚到了第二行——第一行连同开头
  // 那个字被顶出视野，像是"少显示了一个字"。
  //
  // 延后一拍是必需的：onChange 回调跑的时候这次输入的排版还没落地，当场问到的
  // 是上一次的行数。setTimeout(0) 落在本帧布局之后。
  //
  // 顺带解决输入法**候选中的字**：那些字不在 this.draft 里（measureTextSize 因此
  // 一定漏算），但它们已经被 TextArea 排进去了，问组件就问得到。
  private scheduleLinesRefresh(): void {
    if (this.linesRefreshTimer !== -1) {
      return;
    }
    this.linesRefreshTimer = setTimeout((): void => {
      this.linesRefreshTimer = -1;
      this.refreshEditorLines();
    }, 0);
  }

  // 问 TextArea 实际排了几行。布局还没落地时会抛，下一拍再问即可。
  //
  // 收敛性：行数只取决于文本与宽度，与我们设的高度无关，所以
  // 「改高度 → onAreaChange → 重新问行数」最多走一轮就稳定，不会自激。
  private refreshEditorLines(): void {
    if (this.draft === '') {
      if (this.editorLines !== 0) {
        this.editorLines = 0;
      }
      return;
    }
    try {
      const lines: number = this.composerController.getTextContentLineCount();
      if (lines > 0 && lines !== this.editorLines) {
        this.editorLines = lines;
      }
    } catch (e) {
      // 首帧/重建期问不到是正常的，保持上一次的值。
    }
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
                // 【不规定行高】(2026-09-11 真机截图定位)
                // 原来这里写死 .lineHeight(22)。系统换成手写体之后，a/g/p/q/y
                // 这几个字形最"深"的字母**整个不画**（占了宽度、一点墨都没有，
                // 而尾巴短的 j 活下来了）；同一屏的消息气泡用 Text、不设行高，
                // 同样的字母渲染完好——对照成立。
                // 22 是按默认字体量出来的一个数，对任意系统字体都强加它，就是
                // 把字形压进装不下的行盒。行高交给字体自己定，我们只负责**量**
                // 出来（见 lineHeightVp）。
                .fontColor(COLOR_TEXT_PRIMARY)
                .caretColor(this.accentColor)
                .padding({
                  left: 3, right: 3,
                  top: COMPOSER_EDITOR_PADDING, bottom: COMPOSER_EDITOR_PADDING
                })
                .barState(BarState.Auto)
                .backgroundColor(Color.Transparent)
                .key('chat_composer')
                .onAreaChange((old: Area, area: Area): void => {
                  const next: number = area.width as number;
                  // 0.5vp 以内的抖动不写：宽度是排版约束，写一次就要重算一次高度。
                  if (Math.abs(next - this.editorW) > 0.5) {
                    this.editorW = next;
                  }
                  // 盒子高度刚变过 = 刚重排过，这时问到的行数才是新的。
                  if (Math.abs((area.height as number) - (old.height as number)) > 0.5) {
                    this.refreshEditorLines();
                  }
                })
                .onChange((value: string): void => {
                  this.onDraftChange(value);
                  // 当场问一次（拿到的是上一拍的），再隔一帧问一次拿真值。
                  this.refreshEditorLines();
                  this.scheduleLinesRefresh();
                })
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
        .constraintSize({ minHeight: this.rowMinHeight(), maxHeight: this.rowMaxHeight() })
        .padding({
          left: 12, right: COMPOSER_ROW_PADDING,
          top: COMPOSER_ROW_PADDING, bottom: COMPOSER_ROW_PADDING
        })
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
