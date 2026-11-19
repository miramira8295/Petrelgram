import {
  caretAfterExternalEdit, pasteFitsLimit
} from '../../util/composerText';
import { chromeOutline } from '../../util/chromeOutline';
import { showToast } from '../../util/toast';
import { ComposerFullscreenSheet } from './ComposerFullscreenSheet';
import { composerLineProbe } from '../../util/composerLineProbe';
import { ComposerLayoutMeasurement, composerMeasuredHeight } from '../../util/composerLayout';
import { ComposerLayoutFrame } from './ComposerLayoutFrame';
import { shouldOfferFullscreenEdit } from '../../util/composerExpand';
import { pushSheetDismiss } from '../../util/sheetDismissStack';
import { promptAction } from '@kit.ArkUI';
import { str } from '../../util/strings';
import { ReplyKeyboard } from '../../store/ReplyKeyboard';
import { logE } from '../../util/log';
import { PendingMediaItem, hasPendingMedia } from '../../util/pendingMedia';
import { COLOR_ICON_SECONDARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { containerBlur, immersiveMaterialAvailable, overlayMaterial, plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
import { EditStrip, ReplyStrip } from './ComposerStrip';
import { MediaStrip } from './MediaStrip';
import { ComposerSendButton } from './ComposerSendButton';
import { NativeGlassHost } from './NativeGlassHost';
import { ComposerSession } from './ComposerSession';
import { CommandSuggestionState } from './ComposerSuggestionState';
import { VoiceRecordingState } from './VoiceRecordingState';

// Telegram 单条文本消息的上限。
const COMPOSER_MAX_LENGTH: number = 4096;

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
export const COMPOSER_MAX_LINES: number = 7;
// 输入条那一行自己的上下内边距。进 minHeight/maxHeight 的推导，别再手算。
export const COMPOSER_ROW_PADDING: number = 4;
// 胶囊内右侧那排尾部按钮（回复键盘/全屏/命令/表情）的点击区边长。多行时用它把
// 按钮中心对齐到最后一行文字的中线，见 trailingInset()。
const COMPOSER_TAIL_SIZE: number = 34;

// Input-area presentation. ChatPage remains the owner of all state machines,
// store actions, and keyboard/IME coordination; this component only renders
// the tree and forwards UI events.
@ComponentV2
export struct ChatComposerInput {
  @Param attachPanelOpen: boolean = false;
  @Param appDark: boolean = false;
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
  @Param composerEditorReady: boolean = true;
  @Param editorFocused: boolean = false;
  @Param keyboardVisible: boolean = false;
  @Param draft: string = '';
  // 当前光标位置。页面真的整段改写草稿时（@提及补全、读回草稿、插表情），
  // 用它和 caretAfterExternalEdit 推出新位置，再 caretPosition 放回去。
  private caretSeen: number = 0;
  // 输入框自己的文本，经 `!!` 与 TextArea 双向同步（#219-1 的根因修复）。
  //
  // 原来是受控写法 `text: this.draft`：每打一个字，页面把同一份文本经 @Param
  // 传回来，TextArea 看到绑定值变了就重设一次文本、光标随之落到末尾。
  // [Caret] 探针实测：插字后光标先正确落在 6，4ms 后被挪到 9（末尾），期间我们
  // 自己一次 caretPosition 都没调。所以 09-18 那版"认回声、不挪光标"挡不住它。
  // 改成组件自有 @Local + `!!` 之后，打字不再从外面回灌；只有页面真的改写了
  // 草稿（@提及补全、插表情、发送后清空、恢复草稿、全屏编辑回写）才写这里。
  @Local editorText: string = '';
  @Param composerPlaceholder: string = '';
  @Param composerController: TextAreaController = new TextAreaController();
  // 输入框的真实宽度，editorHeight() 拿它做排版约束。原来是绕一圈的：本组件
  // onAreaChange 量到 → @Event 送回 ChatPage 存进 @Local composerEditorW →
  // 页面算好高度 → 再作为 @Param composerEditorHeight 传回本组件。中间那一圈
  // 页面什么也没做，第二轮第 9 项把它收回原地（三个几何常量本来就定义在本文件）。
  @Local private editorW: number = 0;
  @Local private editorLayout: ComposerLayoutMeasurement | undefined = undefined;
  // 全屏编辑入口保留最近行数；其出现会改变宽度，不能随几何快照失效而反复收起。
  @Local private editorLines: number = 0;
  // 全屏编辑面板。挂在本组件而不是页面：它编辑的就是这里的草稿，页面只通过
  // 已有的 onDraftChange / onSend 收结果。
  // ⚠️ **不要加 private**（issue #210）。`bindSheet($$this.fullscreenOpen, ...)`
  // 的双向绑定要在组件上生成一对读写访问器；带 private 时"我们自己置 false"这条
  // 路传不到面板上——系统右上角那个 × 走的是 sheet 内部的关闭流程所以照常好使，
  // 于是现象正好是"× 能关、我们的按钮都关不掉"。
  // 判据：同仓库另外三个 bindSheet（ChatPage.diceSheetOpen /
  // stickerSetSheetOpen、ProxyPage.sheetOpen）都不带 private，都正常。
  // 玻璃画布的尺寸：跟随输入胶囊的实测大小（回复条/媒体条出现时高度会变）。
  @Local private glassSurfaceW: number = 260;
  @Local private glassSurfaceH: number = 46;
  // 「按住拖动跟着手指走」：同一时刻只可能按一个，共用一套位移。
  // 槽位 0=附件钮 1=输入胶囊 2=表情钮 3=发送/语音钮 4=命令钮。只做位移不做
  // 缩放：整块面板缩放会显得像在变形，位移这点跟手感就够了（同 766 行那条判据）。
  @Local private grabSlot: number = -1;
  @Local private grabDX: number = 0;
  @Local private grabDY: number = 0;
  private grabStartX: number = 0;
  private grabStartY: number = 0;
  // 输入法的「预上屏」文本（composition / preview text）。语音转文字时识别结果先进
  // 这里，**不写进 TextArea 的 text 值**，所以 onChange 拿到的 value 一直是空串、
  // 页面的 draft 也一直空着 —— 发送键就停在麦克风上。用户以为能点发送，点下去却
  // 开始录音。现在单独记一份，按钮据此切纸飞机，点发送时把它并进正文一起发。
  @Local private previewValue: string = '';
  private previewOffset: number = 0;
  @Local fullscreenOpen: boolean = false;
  private layoutRefreshPending: boolean = false;
  private layoutGeneration: number = 0;
  private layoutActive: boolean = false;
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
  @Event onEditorAreaChange: (area: Area | undefined) => void = (): void => {};
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
  //
  // 【为什么不能只量 'A' —— issue #209】'A' 既没有下伸部也没有上方标记，是拉丁
  // 字母里最矮的一档。而真正要画的是草稿，草稿为空时画的是 placeholder——那里
  // 塞的是「<昵称> 正在输入…」。昵称带天城文元音符号、泰文上标或某些 emoji 时，
  // 真实行盒比 'A' 高，而盒子高度是按这个数**显式写死**的，装不下就把文字往下
  // 挤，用户报的「文本位置整体下移」就是这个。
  //
  // 所以量两样取大：'A'（保证不小于今天的值，也保证空输入框不塌）和真正要画的
  // 那一行（探针取法见 util/composerLineProbe）。
  //
  // 【缓存与字号缩放】'A' 每次都量——它便宜，而且它跟着系统字号缩放变，正好
  // 当缓存的校验位。探针那次只在"探针变了 或 'A' 的高度变了"时重量。少了这个
  // 校验位，用户在设置里改字号后行高不会更新，就会踩回本函数上方记的那条
  // 「第三行连同光标被切在盒子外面」。
  private probeCacheKey: string = '\u0000';
  private probeCacheVp: number = 0;

  private lineHeightVp(): number {
    let baseVp: number = COMPOSER_LINE_HEIGHT;
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: 'A',
        fontSize: 15
      });
      const measured: number = this.getUIContext().px2vp(size.height as number);
      if (measured > 0) {
        baseVp = measured;
      }
    } catch (e) {
      return COMPOSER_LINE_HEIGHT;
    }
    const probe: string = composerLineProbe(this.draft, this.composerPlaceholder);
    if (probe === '') {
      return baseVp;
    }
    const key: string = `${Math.round(baseVp * 100)}|${probe}`;
    if (key === this.probeCacheKey) {
      return this.probeCacheVp > baseVp ? this.probeCacheVp : baseVp;
    }
    let probeVp: number = 0;
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: probe,
        fontSize: 15
      });
      probeVp = this.getUIContext().px2vp(size.height as number);
    } catch (e) {
      probeVp = 0;
    }
    this.probeCacheKey = key;
    this.probeCacheVp = probeVp;
    return probeVp > baseVp ? probeVp : baseVp;
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
    const lineVp: number = this.lineHeightVp();
    const measured: number = this.measuredEditorHeight(lineVp);
    // 四行的闸门。量得到真实排版就用真实值；量不到时（文本刚变过的那一帧，
    // 采样必然对不上）按 1.35 倍余量估——宁可多留一截，也不能把真实行盒卡在
    // 闸门外，那正是 09-11 写死行高、11-19 写死高度两次"字被裁没"的形状。
    const budget: number = measured > 0 ? measured : lineVp * COMPOSER_MAX_LINES * 1.35;
    return Math.max(lineVp * COMPOSER_MAX_LINES, budget) +
      COMPOSER_EDITOR_PADDING * 2 + COMPOSER_ROW_PADDING * 2;
  }

  // 【尾部按钮钉在哪一行】(2026-11-19 用户纠正)
  // 只靠 Row 的 alignItems(VerticalAlign.Bottom)，按钮落在 Row 内容盒的下沿，
  // 比最后一行文字的底还低 COMPOSER_EDITOR_PADDING(9vp)——那是"贴着玻璃下沿"，
  // 不是"钉在最后一行"。多行时把按钮往上抬 9 + (按钮高 − 行高)/2，让它的中心
  // 落在最后一行文字的中线上；单行不抬：单行胶囊高度 = 行高 + 9×2 + 4×2 ≈ 46，
  // 抬 15vp 会把 34vp 的按钮顶出内容盒，Row 跟着长到 51，和左右两颗 46 的圆钮错位。
  // 【抬多少】(2026-11-19 用户第二次纠正)
  // 按钮贴 Row 内容盒下沿时，底边比最后一行文字低 COMPOSER_EDITOR_PADDING(9vp)；
  // 要让 34vp 按钮的中线落在最后一行文字的中线上，只需上抬 9 − (34 − 行高)/2
  // （行高 22 → 3vp）。重点是**这一档和行数无关**：单行、七行都抬同一个值，
  // 这样输入框长高时按钮不会往回跳一下（上一版给多行额外加 9+6=15，看着就是
  // 「字一多按钮就往上蹿」）。行高比按钮还高时（超大字号）退回 0。
  private trailingInset(): number {
    const lineVp: number = this.lineHeightVp();
    const rise: number = (COMPOSER_TAIL_SIZE - lineVp) / 2;
    return Math.max(0, COMPOSER_EDITOR_PADDING - Math.round(rise));
  }

  // 【扩展键的显隐】(2026-11-19 用户要求把键搬到右上角，判据本身不变)：
  // 只在这段文字已经在小框里看不全时出现（字数/行数/换行三条判据见 util/composerExpand）。
  // 单独提一个方法是因为它在两处要用：右上角那颗键本身、以及 TextArea 的右侧让位。
  private fullscreenShown(): boolean {
    return this.composerEditorReady && shouldOfferFullscreenEdit(this.draft, this.editorLines);
  }

  private measuredEditorHeight(lineVp: number): number {
    return composerMeasuredHeight(this.editorLayout, this.editorText, this.editorW,
      lineVp, COMPOSER_MAX_LINES);
  }

  private editorHeight(): number {
    const lineVp: number = this.lineHeightVp();
    const oneLine: number = lineVp + COMPOSER_EDITOR_PADDING * 2;
    const measured: number = this.measuredEditorHeight(lineVp);
    const cap: number = Math.max(lineVp * COMPOSER_MAX_LINES, measured) + COMPOSER_EDITOR_PADDING * 2;
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
      estimatedLines = Math.ceil(this.getUIContext().px2vp(size.height as number) / lineVp);
    } catch (e) {
      // 量不出来就退回一行，宁可矮也不要抖：TextArea 超出部分自己能滚。
      logE(`editorHeight measure failed: ${(e as Error).message}`);
    }
    // 估算用于即时响应；帧后同时用真实行数和文本区域高度纠偏。
    // 只校正行数不足以覆盖系统字体与 emoji 混排造成的行高差异。
    const lines: number = Math.max(1, Math.min(COMPOSER_MAX_LINES, estimatedLines));
    return Math.max(oneLine,
      Math.min(cap, Math.max(lines * lineVp, measured) + COMPOSER_EDITOR_PADDING * 2));
  }

  aboutToDisappear(): void {
    this.onEditorAreaChange(undefined);
    this.layoutActive = false;
    this.layoutGeneration++;
    this.layoutRefreshPending = false;
  }

  // 隔一帧再问一次真实行数。
  //
  // 【为什么必须有这条，不能只在 onAreaChange 里问】(2026-09-11 真机截图定位)
  // 真实行数原来只在「盒子高度变过」时才刷新，可高度是**按估算算的**：估算说
  // 1 行、真实排了 2 行时，高度压根不变 ⇒ onAreaChange 不触发 ⇒ 永远学不到真相，
  // 自锁。用户看到的是输入框只有一行高、内部却滚到了第二行——第一行连同开头
  // 那个字被顶出视野，像是"少显示了一个字"。
  //
  // onChange 中排版可能尚未落地；改用 FrameCallback.onIdle，不能把
  // setTimeout(0) 当作布局完成通知。
  //
  // 顺带解决输入法**候选中的字**：那些字不在 this.draft 里（measureTextSize 因此
  // 一定漏算），但它们已经被 TextArea 排进去了，问组件就问得到。
  // 外部（页面）整段改写了 draft：把光标放回改动之后，而不是让它跑到末尾。
  // V2 用 @Monitor（@Watch 只在 V1 里有），名字必须是本 struct 的真实成员。
  aboutToAppear(): void {
    this.editorText = this.draft;
    this.layoutActive = true;
    this.editorLayout = undefined;
    this.editorLines = 0;
    this.scheduleLinesRefresh();
  }

  @Monitor('composerEditorReady')
  onEditorReadyChanged(): void {
    this.layoutGeneration++;
    this.layoutRefreshPending = false;
    this.editorLayout = undefined;
    this.editorLines = 0;
    this.scheduleLinesRefresh();
  }

  @Monitor('draft')
  onDraftReplacedOutside(): void {
    // 页面传回来的就是输入框里现有的内容（打字的回声）：什么都不做，
    // 尤其不能再赋给 TextArea。
    if (this.draft === this.editorText) {
      return;
    }
    // 与输入框现有内容不同 = 页面真的改写了草稿。原来这里还有两道"认回声"的
    // 判断（上一份相等 / 最近 6 份里有），现在不能留：它们会把真实的改写也拦下，
    // 比如发送后清空——空串若曾被打出来过就在那份名单里，输入框就不清了。
    // 页面是同步回写的（[Caret] 探针实测每次回声都与上一份相等），不存在迟到的旧回声。
    const next: number = caretAfterExternalEdit(this.editorText, this.draft, this.caretSeen);
    this.editorText = this.draft;
    this.caretSeen = next;
    this.scheduleLinesRefresh();
    // 等这一帧的文本落地再挪光标，否则挪的是旧内容上的位置。
    setTimeout((): void => { this.composerController.caretPosition(next); }, 0);
  }

  // ⑥ 粘贴只进来一半：maxLength 会把超出的部分静默截掉。这里自己接管——放得下
  // 就照常走系统粘贴；放不下就按剩余空间插入并明确提示被截断，而不是不吭声地丢。
  private onComposerPaste(content: string, event: PasteEvent): void {
    if (pasteFitsLimit(this.draft.length, content.length, COMPOSER_MAX_LENGTH)) {
      return;
    }
    if (event.preventDefault !== undefined) {
      event.preventDefault();
    }
    const room: number = Math.max(0, COMPOSER_MAX_LENGTH - this.draft.length);
    const head: number = Math.max(0, Math.min(this.caretSeen, this.draft.length));
    const merged: string = this.draft.substring(0, head) + content.substring(0, room) +
      this.draft.substring(head);
    this.onDraftChange(merged.substring(0, COMPOSER_MAX_LENGTH));
    showToast(str('cp_paste_trimmed', COMPOSER_MAX_LENGTH), 2600);
  }

  private scheduleLinesRefresh(): void {
    if (!this.layoutActive || !this.composerEditorReady || this.layoutRefreshPending) {
      return;
    }
    this.layoutRefreshPending = true;
    const generation: number = this.layoutGeneration;
    try {
      this.getUIContext().postFrameCallback(new ComposerLayoutFrame((): void => {
        if (!this.layoutActive || generation !== this.layoutGeneration) {
          return;
        }
        this.layoutRefreshPending = false;
        this.refreshEditorLines();
      }));
    } catch (e) {
      this.layoutRefreshPending = false;
    }
  }

  // 帧后读取 TextArea 的完整文字区域，不使用其滚动偏移作为高度。
  // 内容/宽度不变时不重复写状态，避免「测量 → 改高度」持续请求渲染。
  private refreshEditorLines(): void {
    if (this.editorText === '') {
      this.editorLines = 0;
      if (this.editorLayout !== undefined) {
        this.editorLayout = undefined;
      }
      return;
    }
    try {
      const lines: number = this.composerController.getTextContentLineCount();
      if (Number.isFinite(lines) && lines > 0 && this.editorLines !== lines) {
        this.editorLines = lines;
      }
      const rect = this.composerController.getTextContentRect();
      if (rect === undefined || lines <= 0 || this.editorW <= 0) {
        return;
      }
      const height: number = this.getUIContext().px2vp(rect.height);
      if (!Number.isFinite(height) || height < 0) {
        return;
      }
      const lineVp: number = this.lineHeightVp();
      const previous: ComposerLayoutMeasurement | undefined = this.editorLayout;
      if (previous !== undefined && previous.text === this.editorText &&
        previous.lines === lines && Math.abs(previous.widthVp - this.editorW) <= 0.5 &&
        Math.abs(previous.probeLineVp - lineVp) <= 0.01 &&
        Math.abs(previous.contentHeightVp - height) <= 0.5) {
        return;
      }
      this.editorLayout = {
        text: this.editorText, widthVp: this.editorW, probeLineVp: lineVp,
        contentHeightVp: height, lines: lines
      };
    } catch (e) {
      // 首帧/重建期问不到是正常的，保持上一次的值。
    }
  }

  // 输入栏的玻璃外皮改走「原生 Navigation 标题栏当画布」这条路（见 NativeGlassHost）：
  // 普通容器挂 .systemMaterial() 真机上不画，右上角功能菜单之所以能画，是因为它长在
  // 框架容器（openMenu 的 Menu 宿主）里。这里把同一套材质参数（'menu' 档）搬到一个
  // 缩到控件大小的 Navigation.title 上。
  //
  // 材质不可用（低于 API 26、设备自报不支持、用户把厚度调到「关闭」）时退回原来的
  // 自绘玻璃：plainGlassFill + plainBackdropBlur，观感与上一版一致。
  private glassHostOn(): boolean {
    return immersiveMaterialAvailable();
  }

  // 按下的那一刻记原点，之后每次 Move 只算与原点之差：手指来回拖时元素是黏在
  // 手指上的，不是每帧从零抖一下。幅度夹在 ±3vp，松手/Tap 取消都归零。
  private trackGrab(event: TouchEvent, slot: number): void {
    if (event.type === TouchType.Down) {
      this.grabSlot = slot;
      this.grabDX = 0;
      this.grabDY = 0;
      if (event.touches.length > 0) {
        this.grabStartX = event.touches[0].x;
        this.grabStartY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.grabSlot !== slot || event.touches.length === 0) {
        return;
      }
      const dx: number = (event.touches[0].x - this.grabStartX) * 0.18;
      const dy: number = (event.touches[0].y - this.grabStartY) * 0.18;
      this.grabDX = dx > 3 ? 3 : (dx < -3 ? -3 : dx);
      this.grabDY = dy > 3 ? 3 : (dy < -3 ? -3 : dy);
      return;
    }
    this.grabSlot = -1;
    this.grabDX = 0;
    this.grabDY = 0;
  }

  // 预上屏文字变了：语音转文字、拼音候选、手写都会走这里。
  private trackPreview(preview: PreviewText | undefined): void {
    if (preview === undefined || preview.value === '') {
      if (this.previewValue === '') {
        return;
      }
      this.previewValue = '';
      this.previewOffset = 0;
      return;
    }
    if (preview.value === this.previewValue && preview.offset === this.previewOffset) {
      return;
    }
    this.previewValue = preview.value;
    this.previewOffset = preview.offset;
  }

  // 输入框里此刻**看得见**的全部文字 = 已提交文本 + 预上屏文本。
  private visibleText(): string {
    const base: string = this.editorText;
    if (this.previewValue === '') {
      return base;
    }
    const at: number = Math.max(0, Math.min(this.previewOffset, base.length));
    return base.slice(0, at) + this.previewValue + base.slice(at);
  }

  // 发送键该不该显示成纸飞机：有草稿、或输入框里有还没提交的预上屏文字，都算。
  private canSendText(): boolean {
    return this.hasDraft || this.previewValue !== '';
  }

  // 点发送：预上屏还没提交时要先自己并进草稿。否则 doSend() 读到的是空草稿，
  // 直接静默 return —— 变成「按钮亮着但点了没反应」，比现在更糟。
  private onSendPressed(): void {
    if (this.previewValue !== '') {
      const full: string = this.visibleText();
      this.previewValue = '';
      this.previewOffset = 0;
      this.editorText = full;
      this.onDraftChange(full);
      this.scheduleLinesRefresh();
    }
    this.onSend();
  }

  build() {
    Row({ space: 6 }) {
      // The attachment action stays outside the growing text capsule.
      if (!this.recording.isRecording) {
        Stack({ alignContent: Alignment.Top }) {
          if (this.glassHostOn()) {
            NativeGlassHost({ hostWidth: 46, hostHeight: 46, hostRadius: 23, dark: this.appDark })
          }
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
          .backgroundColor(Color.Transparent)
          .onClick((): void => { this.onToggleAttach(); });
        }
        .width(46)
        .height(46)
        .borderRadius(23)
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 1 })
        .backgroundColor(this.glassHostOn() ? Color.Transparent : plainGlassFill($r('app.color.surface')))
        .backdropBlur(0)
        .visualEffect(hdsVisualEffect('control', !this.appDark))
        // 玻璃模式去掉自绘描边：画布比内容小几像素，这圈 1px 白线会露在玻璃下面变成一条横线。
        .border(this.glassHostOn() ? { width: 0 } : chromeOutline(this.appDark))
        .clip(true)
        // 附件钮：按住拖动时跟着手指走。
        .translate({ x: this.grabSlot === 0 ? this.grabDX : 0, y: this.grabSlot === 0 ? this.grabDY : 0 })
        .onTouch((event: TouchEvent): void => { this.trackGrab(event, 0); });
      }
      // 悬浮玻璃：底层画布 + 上层内容。内容自己不再画底色/模糊/描边，全部交给画布上的系统材质。
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.glassHostOn()) {
          NativeGlassHost({
            hostWidth: this.glassSurfaceW, hostHeight: this.glassSurfaceH, hostRadius: 24, dark: this.appDark
          })
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
              Circle({ width: 8, height: 8 }).fill(this.recording.readyToSend ? COLOR_TEXT_SECONDARY : '#FF3B30');
              Text(this.recording.secondsLabel()).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
              Text(this.recording.readyToSend ? $r('app.string.mm_voice_messages') : $r('app.string.cp_recording')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
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
            if (this.composerEditorReady) {
              TextArea({
                text: this.editorText!!,
                placeholder: this.composerPlaceholder,
                controller: this.composerController
              })
                .layoutWeight(1)
                // 【不规定高度】和上面「不规定行高」是同一条判据的下一层（2026-11-19）：
                // 写死 .lineHeight 会让手写体的字形整个不画，写死 .height 会做同一件事
                // ——盒子比真实行盒矮，字形落在盒子外的部分被裁掉，看上去就是"字没了、
                // 占位还在"，而且随光标滚动换着地方裁。行高不能替他定，高度也不能。
                // TextArea 不设高时按内容自适应（SDK TextAreaInterface 注释原文：
                // "If the component does not have its height set, it adapts its height
                // to the content"），四行的闸门由 constraintSize + 外层 Row 的 maxHeight
                // 一起兜。自定义字体、彩色 emoji 的 fallback 行盒因此都不会被切。
                .constraintSize({ maxHeight: this.rowMaxHeight() })
                .maxLength(COMPOSER_MAX_LENGTH)
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
                // 【滚动条别压字】(2026-11-19 用户反馈)：TextArea 的滚动条画在组件
                // 右沿、盖在内边距上，右边只留 3 的话会直接压在字上。TextArea 没有
                // barWidth（text_area.d.ts 里只有 barState 和 scrollBarColor），改不了
                // 粗细，只能把右边距让出来：12 ≈ 条宽 4 + 字与条之间 8 的空隙。
                // 【再让一档】(2026-11-19)：扩展键搬到胶囊右上角后，按钮左沿在 W-46，
                // 文字右沿要退到 W-50 才不钻到按钮底下，所以键出现时右边距取 44。
                // 只会让文本更窄、行数更多，不会反过来把键挤掉（无振荡）。
                .padding({
                  // 【右侧为什么不给扩展键让位】(2026-11-19 用户：打字后右边一大片留白)
                  // 扩展键是浮在「尾部按键区」正上方的，不在文字列上，文字本来也不会
                  // 钻到它下面；之前按「让位」写 44，等于每行都被砍掉 32vp 的宽度，
                  // 短句整行缩在左边、右边空一大块。恢复成只给滚动条让的 12。
                  left: 3, right: 12,
                  top: COMPOSER_EDITOR_PADDING, bottom: COMPOSER_EDITOR_PADDING
                })
                .barState(BarState.Auto)
                .backgroundColor(Color.Transparent)
                .key('chat_composer')
                .allowDrop(null)
                .onAreaChange((old: Area, area: Area): void => {
                  this.onEditorAreaChange(area);
                  const next: number = area.width as number;
                  // 0.5vp 以内的抖动不写：宽度是排版约束，写一次就要重算一次高度。
                  if (Math.abs(next - this.editorW) > 0.5) {
                    this.editorW = next;
                    this.scheduleLinesRefresh();
                  }
                  // 盒子高度刚变过 = 刚重排过，这时问到的行数才是新的。
                  if (Math.abs((area.height as number) - (old.height as number)) > 0.5) {
                    this.scheduleLinesRefresh();
                  }
                })
                .onTextSelectionChange((start: number, _end: number): void => {
                  this.caretSeen = start;
                })
                .onPaste((content: string, event: PasteEvent): void => {
                  this.onComposerPaste(content, event);
                })
                // 预上屏（输入法候选/语音转文字）不会进 onChange 的 value，只在
                // previewText 里出现；onWillChange 是先于落地的那一拍，两处都记一次。
                .onWillChange((value: EditableTextChangeValue): boolean => {
                  this.trackPreview(value.previewText);
                  return true;
                })
                .onChange((value: string, previewText?: PreviewText): void => {
                  this.editorText = value;
                  this.trackPreview(previewText);
                  this.onDraftChange(value);
                  // 合并同帧输入，在渲染任务结束后读取真实排版。
                  this.scheduleLinesRefresh();
                })
                .enterKeyType(this.sendByEnter ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
                .onSubmit((): void => { this.onSubmit(); })
                .onFocus((): void => { this.onEditorFocus(); })
                .onBlur((): void => { this.onEditorBlur(); });
            } else {
              Text(this.draft !== '' ? this.draft : this.composerPlaceholder)
                .layoutWeight(1)
                // 同上：高度交给字体度量，和 TextArea 那一支保持同一口径。
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontSize(15)
                .fontColor(this.draft !== '' ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
                .padding({
                  left: 3, right: 12,
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
              .margin({ bottom: this.trailingInset() })
              .onClick((): void => { this.onToggleReplyKeyboard(); });
            }
            if (this.botMiniAppUrlValue !== '') {
              SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                .fontSize(22).fontColor([this.accentColor])
                .accessibilityText($r('app.string.cp_open_miniapp'))
                .margin({ bottom: this.trailingInset() })
                .onClick((): void => { this.onOpenMiniApp(); });
            }
            // 命令入口：Telegram Android 那颗「方框里一道斜杠」的机器人键，
            // 挨着表情钮的左边，只在当前会话有可用 Bot 命令时出现
            // （botMenuAvailable 由 CommandSuggestionState 维护，@Trace 会自动刷新）。
            //
            // 【图标为什么自绘】(2026-11-18 用户反馈) sys.symbol.square_slash 画出来
            // 是「方框有缺口 + 斜杠反向 + 斜杠顶到框外」，而系统符号只能整体换色换大小，
            // 改不了笔画，所以这里用两层 Row 拼：外层闭合圆角边框，内层一条细竖条
            // 顺时针转 20°（竖条顺时针转 = 上端偏右 = "/" 的斜度）。
            // 余量算过：斜杠旋转后的竖直占地 ≈10.0vp，内框可用高 ≈15.2vp，
            // 两端离内框各约 2.6vp，既不超出也不会连到边框上。
            // 只在空输入时露出来：一旦开始打字就让位给文字（用户 2026-11-19 明确）。
            // canSendText 把输入法的预上屏也算进去，语音转文字时说一半就藏。
            // 【表情与命令键为什么收进一个子 Row】(2026-11-19 用户：两键之间的空隙太大)
            // 输入行是 Row({ space: 6 })，两键各 34 宽、图标只有 24 / 18，
            // 6 的盒间距再叠上两个盒子里的居中留白，视觉空隙约 19，
            // 比包盒子之前（表情还是裸字形，约 14）明显变宽。
            // 收进 space:0 的子 Row 后点击区直接贴在一起，视觉空隙回到 13 左右；
            // 子 Row 仍是输入行最后一个孩子，表情键右沿仍在「胶囊宽 − 6」。
            Row({ space: 0 }) {
              if (this.commandSuggestion.botMenuAvailable && !this.canSendText()) {
                Row() {
                  Row() {
                    Row()
                      .width(1.6).height(10).borderRadius(0.8)
                      .backgroundColor(this.commandSuggestion.commandMenuOpen ? this.accentColor : this.chromeIconColor)
                      .rotate({ angle: 20 })
                  }
                  .width(18).height(18).borderRadius(4.5)
                  .border({
                    width: 1.4,
                    color: this.commandSuggestion.commandMenuOpen ? this.accentColor : this.chromeIconColor,
                  })
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                }
                .width(34).height(34).borderRadius(17)
                .justifyContent(FlexAlign.Center)
                .stateStyles({
                  normal: this.composerIconNormalStyle,
                  pressed: this.composerIconPressedStyle
                })
                .animation({ duration: this.smoothEffectDuration(110), curve: Curve.EaseOut })
                .accessibilityText($r('app.string.cp_bot_commands'))
                .margin({ bottom: this.trailingInset() })
                .translate({ x: this.grabSlot === 4 ? this.grabDX : 0, y: this.grabSlot === 4 ? this.grabDY : 0 })
                .onTouch((event: TouchEvent): void => { this.trackGrab(event, 4); })
                .onClick((): void => { this.onToggleBotMenu(); });
              }
              // 表情钮：胶囊内最右，和命令键同一个 34×34 的盒子。
              // 【为什么要包一层】(2026-11-19 用户：表情键要和命令键平齐) 原来这里直接
              // 是裸字形，字形盒比 34 小，底边对齐后中线就和 34 的命令键差几 vp，
              // 看着一高一低。包成同尺寸盒子、内容居中，两键中线天然对齐。
              Row() {
                SymbolGlyph($r(this.showEmojiPanel ? 'sys.symbol.keyboard' : 'sys.symbol.face_smiling'))
                  .fontSize(24)
                  .fontColor([this.showEmojiPanel ? this.accentColor : this.chromeIconColor]);
              }
              .width(34).height(34).borderRadius(17)
              .justifyContent(FlexAlign.Center)
              .stateStyles({
                normal: this.composerIconNormalStyle,
                pressed: this.composerIconPressedStyle
              })
              .accessibilityText(this.showEmojiPanel ? str('cp_show_keyboard') : str('emoji_panel_a11y'))
              .margin({ bottom: this.trailingInset() })
              .translate({ x: this.grabSlot === 2 ? this.grabDX : 0, y: this.grabSlot === 2 ? this.grabDY : 0 })
              .onTouch((event: TouchEvent): void => { this.trackGrab(event, 2); })
              .onClick((): void => { this.onEmojiButtonTap(); });
            }
          }
        }
        .width('100%')
        .constraintSize({ minHeight: this.rowMinHeight(), maxHeight: this.rowMaxHeight() })
        .padding({
          left: 12, right: 6,
          top: COMPOSER_ROW_PADDING, bottom: COMPOSER_ROW_PADDING
        })
        // 按钮一律贴 Row 内容盒下沿；多行时再由各按钮自己的 trailingInset()
        // 抬到「最后一行文字」的中线上（单行不抬，见 trailingInset 注释）。
        // 文字仍从左上排版。
        .alignItems(VerticalAlign.Bottom);
      }
        .width('100%')
        .backgroundColor(Color.Transparent)
        .onAreaChange((_old: Area, area: Area): void => {
          const measuredH: number = area.height as number;
          const measuredW: number = area.width as number;
          if (measuredH > 0 && Math.abs(measuredH - this.glassSurfaceH) > 0.5) {
            this.glassSurfaceH = measuredH;
          }
          if (measuredW > 0 && Math.abs(measuredW - this.glassSurfaceW) > 0.5) {
            this.glassSurfaceW = measuredW;
          }
        })
        // 【扩展键放在右上角】(2026-11-19 用户要求)：原来是输入行尾部的一颗按钮，
        // 现在浮在胶囊右上角；显隐判据不变（fullscreenShown，见 util/composerExpand）。
        // 【为什么套一层满宽 Row】上一版直接给按钮写 .align(Alignment.TopEnd)，
        // 结果它跑到左上角：Stack 子里每个孩子的位置由父的 alignContent(TopStart) 决定，
        // .align 改的是组件**自身内容**的对齐，管不到自己在父里的落点。所以这里用一条
        // 满宽 34 高的 Row 把按钮推到右端；这条 Row 自身设 hitTestBehavior(None)
        // （自己不响应触摸、子节点照常响应），才不挡住下面文字的点选和长按。
        // 右沿留 12：TextArea 的滚动条占 W-10..W-6，按钮右沿停在 W-12，不压条。
        if (this.fullscreenShown()) {
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                .fontSize(19).fontColor([COLOR_ICON_SECONDARY]);
            }
            .width(34).height(34).borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .stateStyles({
              normal: this.composerIconNormalStyle,
              pressed: this.composerIconPressedStyle
            })
            .accessibilityText($r('app.string.cp_fullscreen_edit'))
            .onClick((): void => {
              this.fullscreenOpen = true;
              // 返回键先收面板，而不是退出会话页（见 util/sheetDismissStack）。
              this.fullscreenOff = pushSheetDismiss((): void => {
                this.fullscreenOpen = false;
              });
            });
          }
          .width('100%')
          .height(34)
          .justifyContent(FlexAlign.End)
          // 与表情键的右沿对齐：输入行 Row 的右内边距是 6，覆盖层也必须留 6，
          // 两颗键都是 34 宽，这样中线也落在同一条竖线上（用户 2026-11-19 指出偏了一点）。
          .padding({ right: 6 })
          .margin({ top: 2 })
          .hitTestBehavior(HitTestMode.None);
        }
      }
      .layoutWeight(1)
      .backgroundColor(this.glassHostOn() ? Color.Transparent : plainGlassFill($r('app.color.surface')))
      .borderRadius(24)
      .backdropBlur(0)
      // 'card' 档：给点光源、不给按压阴影——整块面板跟着手指变形很怪，
      // 这条判据在 overlayMaterial.interactionBase 里，和材质那条路共用。
      .visualEffect(hdsVisualEffect('card', !this.appDark))
      // 同上：玻璃模式不要自绘描边，否则玻璃底边外会多一条 1px 白线。
      .border(this.glassHostOn() ? { width: 0 } : chromeOutline(this.appDark))
      .clip(true)
      // 输入胶囊：同样是按住拖动跟手。只位移、不缩放（见上方 trackGrab 注释）。
      .translate({ x: this.grabSlot === 1 ? this.grabDX : 0, y: this.grabSlot === 1 ? this.grabDY : 0 })
      .onTouch((event: TouchEvent): void => { this.trackGrab(event, 1); });
      // 发送/语音：从胶囊里切出来，单独一颗，站位与左边回形针钮对称。
      if (!this.recording.isRecording) {
        Stack() {
          // 与左侧附件键同一套玻璃：玻璃落在这层 Stack 上，图标由子组件出。
          if (this.glassHostOn()) {
            NativeGlassHost({ hostWidth: 46, hostHeight: 46, hostRadius: 23, dark: this.appDark })
          }
          ComposerSendButton({
            hasDraft: this.canSendText(),
            recordingStarting: this.recording.recordingStarting,
            sending: this.composerSending,
            iconColor: this.chromeIconColor,
            accentColor: this.accentColor,
            onRecord: (): void => { this.onRecord(); },
            onSend: (): void => { this.onSendPressed(); },
            onSendOptions: (): void => { this.onSendOptions(); }
          });
        }
        .width(46)
        .height(46)
        .borderRadius(23)
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 1 })
        .backgroundColor(this.glassHostOn() ? Color.Transparent : plainGlassFill($r('app.color.surface')))
        .backdropBlur(0)
        .visualEffect(hdsVisualEffect('control', !this.appDark))
        .border(this.glassHostOn() ? { width: 0 } : chromeOutline(this.appDark))
        .clip(true)
        .translate({ x: this.grabSlot === 3 ? this.grabDX : 0, y: this.grabSlot === 3 ? this.grabDY : 0 })
        .onTouch((event: TouchEvent): void => { this.trackGrab(event, 3); });
      }
    }
    .width('100%')
    .padding({
      left: 14,
      right: 14,
      top: 6,
      bottom: this.replyKeyboardVisible ? 8 : this.bottomGap
    })
    .alignItems(VerticalAlign.Center)
    .bindSheet($$this.fullscreenOpen, this.fullscreenEditor(), {
      height: SheetSize.LARGE,
      // 显式写出来：面板里已经没有自己的关闭按钮了，右上角这个系统 × 是**唯一**
      // 的关闭入口（issue #210 用户定的形态）。默认就是 true，但这里不能默认——
      // 谁哪天顺手关掉它，面板就再也收不起来了。
      showClose: true,
      backgroundColor: Color.Transparent,
      dragBar: false,
      blurStyle: containerBlur('dialog'), systemMaterial: overlayMaterial('dialog'),
      onDisappear: (): void => {
        if (this.fullscreenOff !== null) {
          this.fullscreenOff();
          this.fullscreenOff = null;
        }
      }
    });
  }

  private fullscreenOff: (() => void) | null = null;

  @Builder
  private fullscreenEditor() {
    // 每次打开都重建：面板内部持有编辑中的文本，重建才能拿到当前草稿。
    if (this.fullscreenOpen) {
      ComposerFullscreenSheet({
        initialText: this.draft,
        placeholder: this.composerPlaceholder,
        maxLength: COMPOSER_MAX_LENGTH,
        accentColor: this.accentColor,
        onCommit: (text: string): void => {
          this.onDraftChange(text);
        },
        onSend: (): void => {
          this.fullscreenOpen = false;
          this.onSend();
        }
      });
    }
  }
}
