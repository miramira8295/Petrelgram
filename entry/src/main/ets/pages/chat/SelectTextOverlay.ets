// 「选择文本」浮层（issue #94）。
//
// **为什么不是就地选中。** 给气泡里的 Text 挂 `copyOption` 会让它自己接管长按，
// 直接和气泡的长按菜单、左滑回复抢手势——#114「长按无菜单」就是同一族的坑。
// 所以这里走官方 TG 的做法：长按菜单里出一项，把这条消息**另画一遍**到一个
// 独立浮层上，时间轴的手势一个字节都不用动。
//
// **为什么不能复用长按预览。** 那个预览是 `MenuPreviewMode.IMAGE`，
// componentSnapshot 出来的位图，图里的字选不了。这一层必须真的重画。
//
// 重画而不是复用 MessageBubble：气泡那棵树带着手势、反应、时间层、复用协议，
// 搬过来既重又危险。选择层只需要「同样的颜色和排版 + 能选」，所以从
// parseFormattedText 的分段直接画一遍，省掉所有动画和点击态——
// 那些在一个只用来选字的面上没有意义，而且每个 .animation() 都是实打实的
// 更新开销（见 MessageBubble.richInlineRun 里那段真机 trace 的说明）。

import { ComponentContent, UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { logE } from '../../util/log';
import { parseFormattedText, RichRun, RichSegment, richSegmentKey } from '../../util/richText';
import {
  accentSoft, bubbleTextFor, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, COLOR_PRIMARY,
  COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';

// 遮罩。比长按菜单的背板浅一档：那一层要把整页推远，这一层只需要让气泡
// 从背景里浮出来，用户还得看得见自己在哪条消息上。
const SCRIM: string = '#66000000';
// 气泡两侧留白，以及气泡的宽度上限——超过这个宽度一行字太长，反而难选。
const SIDE_GAP: number = 24;
const MAX_BUBBLE_W: number = 520;
const QUOTE_LINE_H: number = 16;

// 这一层要画的全部内容。**在打开的那一刻从 MessageEntry 里摘一份快照**，
// 而不是把整条消息传进来：
//   - MessageEntry 有上百个字段，这一层只用得上九个；
//   - 页面侧需要一个「没打开」时的空值，给九个字段造一个 EMPTY 是一行的事，
//     给 MessageEntry 造一个不是。
// 快照语义也正是想要的：用户是对着**当时看到的那条**点的「选择文本」。
export interface SelectTextPayload {
  text: string;
  entities: TdObject[];
  translatedText: string;
  isOutgoing: boolean;
  hasReply: boolean;
  replySenderName: string;
  replyText: string;
  emojiIds: string[];
  emojiPaths: string[];
}

export const EMPTY_SELECT_TEXT: SelectTextPayload = {
  text: '', entities: [], translatedText: '', isOutgoing: false,
  hasReply: false, replySenderName: '', replyText: '',
  emojiIds: [], emojiPaths: []
};

// 译文隐藏时不带进来：界面上看不见的东西不该出现在选择层里。
export function selectTextPayload(entry: MessageEntry): SelectTextPayload {
  return {
    text: entry.text,
    entities: entry.textEntities,
    translatedText: entry.translationHidden ? '' : entry.translatedText,
    isOutgoing: entry.isOutgoing,
    hasReply: entry.replyToMessageId !== 0,
    replySenderName: entry.replySenderName,
    replyText: entry.replyText,
    emojiIds: entry.inlineCustomEmojiIds,
    emojiPaths: entry.inlineCustomEmojiPaths
  };
}

@ComponentV2
export struct SelectTextOverlay {
  @Param data: SelectTextPayload = EMPTY_SELECT_TEXT;
  @Param topSafe: number = 0;
  @Event onClose: () => void = (): void => {};

  // 全局环境（字号、屏宽、强调色纪元）走镜像，和气泡同一套。
  private env: ChatEnvMirror = chatEnv;

  private accent(): ResourceColor {
    return this.env.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private textColor(): ResourceColor {
    return bubbleTextFor(this.data.isOutgoing);
  }

  private bubbleW(): number {
    return Math.min(this.env.screenWidthVp - SIDE_GAP * 2, MAX_BUBBLE_W);
  }

  private textSize(): number {
    return this.env.msgTextSize > 0 ? this.env.msgTextSize : 16;
  }

  private codeSize(): number {
    return Math.max(12, this.textSize() - 2);
  }

  private inlineCustomEmojiSource(customEmojiId: string): string {
    const idx: number = this.data.emojiIds.indexOf(customEmojiId);
    if (idx < 0 || idx >= this.data.emojiPaths.length) {
      return '';
    }
    const path: string = this.data.emojiPaths[idx];
    return path.startsWith('/') ? `file://${path}` : path;
  }

  private decorationOf(run: RichRun): TextDecorationType {
    if (run.strike) {
      return TextDecorationType.LineThrough;
    }
    return run.underline ? TextDecorationType.Underline : TextDecorationType.None;
  }

  // 剧透在这一层**直接显示**。用户是主动点了「选择文本」才到这儿的，把字
  // 遮起来就没法选；官方客户端复制剧透也是复制明文。
  @Builder
  inlineRun(run: RichRun) {
    if (run.customEmojiId !== '' && this.inlineCustomEmojiSource(run.customEmojiId) !== '') {
      ImageSpan(this.inlineCustomEmojiSource(run.customEmojiId))
        .width(this.textSize() + 3)
        .height(this.textSize() + 3)
        .verticalAlign(ImageSpanAlignment.CENTER)
        .objectFit(ImageFit.Contain);
    } else {
      // 链接照气泡染成强调色，但**不挂 onClick**：这一层上手指是用来划选的，
      // 点一下就跳走会让人选不完一句话。
      Span(run.text)
        .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily(run.code ? 'monospace' : '')
        .fontColor(run.link || run.url !== '' ? this.accent() : this.textColor())
        .decoration({
          type: this.decorationOf(run),
          color: run.link || run.url !== '' ? this.accent() : this.textColor()
        })
        .textBackgroundStyle({
          color: run.code ? $r('app.color.surface_alt') : Color.Transparent,
          radius: run.code ? 3 : 0
        });
    }
  }

  @Builder
  segment(seg: RichSegment) {
    if (seg.kind === 'pre') {
      Text(seg.text)
        .fontSize(this.codeSize())
        .fontFamily('monospace')
        .fontColor(this.textColor())
        .wordBreak(WordBreak.BREAK_ALL)
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(6)
        .margin({ top: 4, bottom: 4 });
    } else if (seg.kind === 'quote') {
      Text() {
        ForEach(seg.runs, (run: RichRun) => {
          this.inlineRun(run);
        }, (run: RichRun, i: number) => `q_${i}_${run.offset}_${run.text}`);
      }
      .fontSize(this.textSize())
      .lineHeight(this.textSize() * 1.34)
      .wordBreak(WordBreak.BREAK_WORD)
      .copyOption(CopyOptions.LocalDevice)
      .width('100%')
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor(accentSoft())
      .borderRadius(6)
      .border({ width: { left: 2 }, color: this.accent() })
      .margin({ top: 4, bottom: 4 });
    } else {
      Text() {
        ForEach(seg.runs, (run: RichRun) => {
          this.inlineRun(run);
        }, (run: RichRun, i: number) => `r_${i}_${run.offset}_${run.text}`);
      }
      .fontSize(this.textSize())
      .lineHeight(this.textSize() * 1.34)
      .wordBreak(WordBreak.BREAK_WORD)
      .copyOption(CopyOptions.LocalDevice);
    }
  }

  // 引用块照气泡画，但**不可点**（点了跳走同样会打断划选），文字也不再
  // 截断成一行——到了这一层，用户很可能就是来复制被引用的那句话的。
  @Builder
  replyQuote() {
    Column() {
      Text(this.data.replySenderName)
        .fontSize(12).fontColor(this.accent()).maxLines(1)
        .lineHeight(QUOTE_LINE_H)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(this.data.replyText)
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .lineHeight(QUOTE_LINE_H)
        .copyOption(CopyOptions.LocalDevice);
    }
    .alignItems(HorizontalAlign.Start)
    .alignSelf(ItemAlign.Stretch)
    .backgroundColor(accentSoft())
    .borderRadius(6)
    .border({ width: { left: 2 }, color: this.accent() })
    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
    .margin({ bottom: 6 });
  }

  // 译文和正文一起进这一层（想复制译文的场景比复制原文还多）。瞬时态
  // 「翻译中 / 翻译失败」不画：那两个状态没有可复制的内容。
  @Builder
  translation() {
    Divider().color(COLOR_TEXT_SECONDARY).opacity(0.3).strokeWidth(0.6)
      .margin({ top: 8, bottom: 6 });
    Text(this.data.translatedText)
      .fontSize(this.textSize())
      .lineHeight(this.textSize() * 1.34)
      .fontStyle(FontStyle.Italic)
      .fontColor(this.textColor())
      .wordBreak(WordBreak.BREAK_WORD)
      .copyOption(CopyOptions.LocalDevice);
  }

  @Builder
  bubble() {
    Column() {
      if (this.data.hasReply) {
        this.replyQuote();
      }
      ForEach(parseFormattedText(this.data.text, this.data.entities),
        (seg: RichSegment, idx: number) => {
          this.segment(seg);
        }, (seg: RichSegment, idx: number) => richSegmentKey(idx, seg));
      if (this.data.translatedText !== '') {
        this.translation();
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.bubbleW())
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.data.isOutgoing ? COLOR_BUBBLE_OUT : COLOR_BUBBLE_IN)
    .borderRadius(this.env.bubbleRadius > 0 ? this.env.bubbleRadius : 18)
    // 吃掉落在气泡（含内边距）上的点击，否则会穿到下面那层遮罩上把浮层关掉。
    .onClick((): void => {});
  }

  build() {
    Stack() {
      // 遮罩单独一层：点空白处关闭。它铺满整屏，包括标题栏那一条——本层由
      // 页面用 bindContentCover 挂成全屏模态，所以压得住框架标题栏。
      Column()
        .width('100%').height('100%')
        .backgroundColor(SCRIM);
      // 内容超过一屏就上下滚，气泡本身不缩放（align(Center) 只在内容比视口
      // 短时生效，短消息因此仍然居中）。
      Scroll() {
        Column() {
          this.bubble();
        }
        .width('100%')
        .padding({ top: this.topSafe + 24, bottom: 40 })
        .justifyContent(FlexAlign.Center);
      }
      .width('100%').height('100%')
      .align(Alignment.Center)
      .scrollBar(BarState.Off)
      .onClick((): void => { this.onClose(); });
    }
    .width('100%').height('100%')
    // 弹窗内容默认排在安全区里，不铺开的话状态栏和手势条那两条不会被遮罩
    // 压住，浮层看着像"没盖满"。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}

// ── 打开这一层的唯一入口 ────────────────────────────────────────────────
//
// 走 ComponentContent + UIContext.openCustomDialog，和 DeleteMessagesDialog
// 同一套：调用页只管"给我打开"，开关、关闭、dispose 全在这个文件里。
// ChatPage 因此只多一个方法，不多状态、不多 build() 里的属性。
//
// ComponentContent 是脱离组件树管理的节点实体，关掉之后必须 dispose，
// 否则那棵子树泄漏。

interface SelectTextOverlayParams {
  data: SelectTextPayload;
  topSafe: number;
  onClose: () => void;
}

@Builder
function selectTextOverlayLayer(params: SelectTextOverlayParams) {
  SelectTextOverlay({
    data: params.data,
    topSafe: params.topSafe,
    onClose: params.onClose
  });
}

export function openSelectTextOverlay(ui: UIContext, data: SelectTextPayload, topSafe: number): void {
  let content: ComponentContent<SelectTextOverlayParams> | null = null;
  const close = (): void => {
    const open: ComponentContent<SelectTextOverlayParams> | null = content;
    if (open === null) {
      return;
    }
    ui.getPromptAction().closeCustomDialog(open)
      .catch((e: Object): void => { logE(`openSelectTextOverlay close failed: ${e}`); });
  };
  const params: SelectTextOverlayParams = { data: data, topSafe: topSafe, onClose: close };
  const node: ComponentContent<SelectTextOverlayParams> =
    new ComponentContent(ui, wrapBuilder(selectTextOverlayLayer), params);
  content = node;
  ui.getPromptAction().openCustomDialog(node, {
    // 遮罩由本层自己画（点它关闭），弹窗的默认蒙版要关掉，否则两层叠着更黑。
    maskColor: Color.Transparent,
    // 内容自己就是满屏，没有"外面"可点，所以 autoCancel 不起作用，
    // 关闭统一走本层 Scroll 上的点击。
    autoCancel: false,
    alignment: DialogAlignment.Center,
    onDidDisappear: (): void => {
      content = null;
      node.dispose();
    }
  }).catch((e: Object): void => {
    content = null;
    node.dispose();
    logE(`openSelectTextOverlay open failed: ${e}`);
  });
}
