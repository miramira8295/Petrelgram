import { MessageEntry } from '../../store/MessageEntry';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  AvailableReactionSet, customEmojiReactionKey, parseAvailableReactions, reactionKeyFrom
} from '../../util/reactions';
import { resolveCustomEmojiThumbs } from '../../util/customEmojiThumbs';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  KEY_POWER_EFFECT_REACTION, KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS, powerGroupFeatureEnabled
} from '../../store/AppSettings';
import { logE } from '../../util/log';

// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
const REACTION_EMOJIS: string[] = [
  '❤️', '👍', '👎', '🔥', '🥰', '👏', '😁', '🤔', '🤯', '😱', '🤬', '😢',
  '🎉', '🤩', '🤮', '💩', '🙏', '👌', '🕊️', '🤡', '🥱', '🥴', '😍', '🐳',
  '❤️‍🔥', '🌚', '🌭', '💯', '🤣', '⚡', '🍌', '🏆', '💔', '🤨', '😐', '🍓',
  '🍾', '💋', '🖕', '😈', '😴', '😭', '🤓', '👻', '👀', '🎃', '🙈', '😇',
  '😨', '🤝', '✍️', '🤗', '🫡', '🎅', '🎄', '☃️', '💅', '🤪', '🗿', '🆒',
  '💘', '🙉', '🦄', '😘', '💊', '🙊', '😎', '👾', '🤷', '😡'
];

// 反应面板里的一枚自定义 emoji：位图路径为 '' 表示还在下载。
interface CustomEmojiOption {
  id: string;
  path: string;
}

// Full emoji reaction picker, extracted from ChatPage.
//
// Ownership split with the page: the page owns the actual add/remove request
// (the quick reaction row on each bubble issues the same one, so it cannot move
// here) and the in-flight guard behind it. This component owns the sheet: which
// emoji the server allows for this message, custom-emoji thumbnails, and the
// selected-state highlight.
// 状态管理 V2（P3 批 2 第 2 项）。迁移的理由不是「顺手统一」，而是还债：
// V1 的 @Prop 对复杂类型是**深拷贝**，且是单向**同步** —— 父组件里的源每换一次
// 新数组就重拷一次。面板开着的时候，页面的 messages 每跳一次下载进度就换一个
// 新数组，几百个 MessageEntry 会整体深拷一遍。V2 的 @Param 是引用传递。
@ComponentV2
export struct ReactionSheet {
  // 单向入 + 回调出，而不是 @Link（@Link 只能被 V1 状态变量初始化，页面已经是
  // 状态管理 V2，接不上）：选中一个 emoji、点遮罩，都是从这里关的。
  // 迁 V2 之后 @Param 不允许组件内部修改，原来那句 `this.show = false` 已删掉
  // ——它本来就是多余的：show 在本组件内一次都没被读过，真正撤掉这一层的是
  // 页面侧 `if (this.showReactionSheet)` 在收到 onShowChange 之后的重建。
  @Param show: boolean = false;
  @Event onShowChange: (show: boolean) => void = (): void => {};
  // @Param（不是普通字段）：高亮要跟着面板打开期间到达的表态更新走，只有被
  // 跟踪的状态变量做得到。@Param 走引用，不再有 @Prop 的整表深拷贝。
  @Param messages: MessageEntry[] = [];

  // Set by the page at construction; the sheet is rebuilt on each open.
  // @Param 而不是无装饰器成员：V2 里无装饰器成员是纯本地常量，父组件初始化它
  // 是编译错误 10905324（P3 批 1 实测）。
  @Param targetId: number = 0;
  @Param chatId: number = 0;

  // The page's in-flight reaction key — a second pick is ignored while one is
  // still being sent.
  @Param pendingKey: string = '';

  // V2 没有 @StorageProp 的等价物，由页面透传（页面自己持有这两个键）。
  @Param bottomSafe: number = 0;
  @Param keyboardH: number = 0;

  // @Event 而不是 @Param：调用点传的是内联箭头函数，页面每重建一次都是新闭包，
  // @Param 的 `!==` 恒不相等会让本层白刷一遍。@Event 不具备观测能力。
  @Event effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;
  @Event onPick: (reactionKey: string, chosen: boolean) => void = (): void => {};

  @Local reactions: string[] = REACTION_EMOJIS;
  @Local customEmojis: CustomEmojiOption[] = [];
  @Local allowCustomEmoji: boolean = false;

  private seq: number = 0;

  aboutToAppear(): void {
    this.loadAvailable();
  }

  aboutToDisappear(): void {
    this.seq++;
  }

  // Empirically tuned on device: with the keyboard up the sheet needs lifting
  // clear of the IME edge; without it the layout already sits above the gesture
  // bar, so only minimal padding applies.
  private bottomInset(): number {
    return this.keyboardH > 0 ? Math.max(this.bottomSafe, 12) : this.bottomSafe;
  }

  private reactionEffectDuration(duration: number): number {
    if (!powerGroupFeatureEnabled(KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS)) {
      return 0;
    }
    return this.effectDuration(KEY_POWER_EFFECT_REACTION, duration);
  }

  // Channels/groups can restrict which reactions are allowed; ask TDLib for
  // the real list so the sheet never offers an emoji the server would reject.
  private loadAvailable(): void {
    const seq: number = ++this.seq;
    const req: TdRequest = { '@type': 'getMessageAvailableReactions' };
    req['chat_id'] = this.chatId;
    req['message_id'] = this.targetId;
    req['row_size'] = 8;
    getTdClient().send(req, 10000).then((result: TdObject): void => {
      if (seq !== this.seq) { return; }
      const available: AvailableReactionSet = parseAvailableReactions(result);
      if (available.emojis.length > 0) { this.reactions = available.emojis; }
      this.allowCustomEmoji = available.allowCustomEmoji;
      if (!available.allowCustomEmoji || available.customEmojiIds.length === 0) { return; }
      this.customEmojis = available.customEmojiIds.map((id: string): CustomEmojiOption => {
        return { id, path: '' };
      });
      resolveCustomEmojiThumbs(available.customEmojiIds, (id: string, path: string): void => {
        if (seq !== this.seq) { return; }
        this.applyCustomEmojiThumb(id, path);
      });
    }).catch((e: TdError): void => {
      logE(`ReactionSheet.availableReactions failed: ${e.message}`);
    });
  }

  // 逐个替换而不是整批重建：先到的位图立刻可见，其余仍显示占位。
  private applyCustomEmojiThumb(customEmojiId: string, path: string): void {
    this.customEmojis = this.customEmojis.map(
      (option: CustomEmojiOption): CustomEmojiOption => {
        return option.id === customEmojiId ? { id: option.id, path } : option;
      });
  }

  private targetReactionChosen(reactionKey: string): boolean {
    let target: MessageEntry | null = null;
    for (const m of this.messages) {
      if (m.id === this.targetId) {
        target = m;
        break;
      }
    }
    if (target === null) {
      return false;
    }
    for (const reaction of target.reactions) {
      if (reactionKeyFrom(reaction.emoji, reaction.customEmojiId) === reactionKey) {
        return reaction.isChosen;
      }
    }
    return false;
  }

  // The full sheet mirrors the quick row: tapping an already-selected emoji
  // removes it instead of issuing a redundant add request.
  private pick(reactionKey: string): void {
    if (this.targetId === 0 || this.pendingKey !== '') {
      return;
    }
    const chosen: boolean = this.targetReactionChosen(reactionKey);
    this.seq++;
    this.onShowChange(false);
    this.onPick(reactionKey, chosen);
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Builder
  customEmojiSection() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.rs_custom_emoji')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
      }
      .width('100%').padding({ left: 6, right: 6 });
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.customEmojis, (option: CustomEmojiOption) => {
            Row() {
              if (option.path !== '') {
                Image(option.path.startsWith('/') ? `file://${option.path}` : option.path)
                  .width(30).height(30).objectFit(ImageFit.Contain)
                  .draggable(false);
              } else {
                // 位图未就绪：灰底占位保持格子尺寸，不闪空白。
                Row().width(30).height(30).borderRadius(8)
                  .backgroundColor($r('app.color.surface_alt'));
              }
            }
            .width(44).height(44).borderRadius(22)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.targetReactionChosen(customEmojiReactionKey(option.id))
              ? $r('app.color.selected_pill') : Color.Transparent)
            .stateStyles({
              normal: this.rowNormalStyle,
              pressed: this.rowPressedStyle
            })
            .animation({ duration: this.reactionEffectDuration(130), curve: Curve.EaseOut })
            .accessibilityText($r('app.string.rs_custom_reaction'))
            .onClick(() => { this.pick(customEmojiReactionKey(option.id)); });
          }, (option: CustomEmojiOption) => `ce_${option.id}_${option.path}`);
        }.width('100%');
      }.constraintSize({ maxHeight: 108 }).scrollBar(BarState.Off);
    }
    .width('100%');
  }

  build() {
    Column() {
      Column().layoutWeight(1)
        .onClick(() => { this.onShowChange(false); });
      Column({ space: 8 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Row() {
          Text($r('app.string.rs_pick_reaction')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium)
            .layoutWeight(1);
          Text($r('app.string.rs_tap_again'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%').padding({ left: 6, right: 6 });
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.reactions, (e: string) => {
              Row() {
                Text(e).fontSize(27);
              }
                .width(44).height(44).borderRadius(22)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.targetReactionChosen(e) ? $r('app.color.selected_pill') : Color.Transparent)
                .stateStyles({
                  normal: this.rowNormalStyle,
                  pressed: this.rowPressedStyle
                })
                .animation({ duration: this.reactionEffectDuration(130), curve: Curve.EaseOut })
                .onClick(() => { this.pick(e); });
            }, (e: string) => e);
          }.width('100%');
        }.constraintSize({ maxHeight: 240 }).scrollBar(BarState.Off);
        if (this.allowCustomEmoji && this.customEmojis.length > 0) {
          this.customEmojiSection();
        }
      }
      .width('calc(100% - 16vp)')
      .padding({ left: 10, right: 10, top: 10, bottom: 14 + this.bottomInset() })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: -2 })
      .margin({ left: 8, right: 8, bottom: 8 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066')
    .transition(
      TransitionEffect.translate({ y: 24 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.reactionEffectDuration(220), curve: Curve.EaseOut })
    );
  }
}
