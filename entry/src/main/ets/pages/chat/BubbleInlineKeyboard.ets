import { showToast } from '../../util/toast';
import { MessageEntry, InlineBtn } from '../../store/MessageEntry';
import { chatEnv } from '../../util/chatEnvMirror';
import { BUBBLE_AVATAR_GUTTER_VP, bubbleMaxWidth } from '../../util/mediaBox';
import { inlineButtonKey, InlineKeyboardKeys, InlineKeyboardKeyPlan } from '../../util/inlineButtonKey';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { botButtonBg } from '../../util/theme';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';

import { MessageBubbleContext } from './MessageBubbleShell';

@Styles
function contentButtonNormal() { .opacity(1).scale({ x: 1, y: 1 }) }
@Styles
function contentButtonPressed() { .opacity(.72).scale({ x: .975, y: .975 }) }
@ComponentV2
export struct BubbleInlineKeyboard {
  @Require @Param context: MessageBubbleContext;
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param drawnWidth: number = 0;
  @Param drawnLeft: number = 0;
  @Param drawnRight: number = 0;
  private env = chatEnv;
  private keys: InlineKeyboardKeys = new InlineKeyboardKeys();
  @Computed
  private get keyPlan(): InlineKeyboardKeyPlan { return this.keys.prepare(this.msg.inlineButtons); }
  private active: boolean = false;
  private identity: string = '';
  private generation: number = 0;
  private bindIdentity(): number {
    const key = `${this.data.chatId}:${this.msg.rowId}:${this.msg.id}`;
    if (key !== this.identity) { this.identity = key; this.generation++; }
    return this.generation;
  }
  @Monitor('msg', 'data')
  private changed(): void { this.bindIdentity(); }
  aboutToAppear(): void { this.active = true; this.bindIdentity(); }
  aboutToReuse(): void { this.active = true; this.bindIdentity(); }
  aboutToRecycle(): void { this.active = false; this.generation++; this.identity = ''; }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private clickCallback(btn: InlineBtn, row: number, column: number): () => void {
    const generation = this.bindIdentity(), key = inlineButtonKey(row, column, btn);
    return (): void => {
      const current = this.msg.inlineButtons[row]?.[column];
      if (!this.active || generation !== this.generation || this.context.gestureClaimed || current === undefined ||
        inlineButtonKey(row, column, current) !== key) { return; }
      if ((current.webAppUrl ?? '') !== '') { this.actions.onMiniApp(this.msg.id, current.webAppUrl!); }
      else if (current.url !== '') { this.actions.onLinkTap(current.url, true); }
      else if (current.callbackData !== '') { this.actions.onBotCallback(this.msg.id, current.callbackData); }
      else if (current.isGame) { this.actions.onGameOpen(this.msg.id); }
      else { showToast($r('app.string.miniapp_button_unsupported')); }
    };
  }
  @Builder
  inlineKeyboard() {
    Row() {
      Column({ space: 4 }) {
        ForEach(this.msg.inlineButtons, (row: InlineBtn[], rowIdx: number) => {
          Row({ space: 4 }) {
            ForEach(row, (btn: InlineBtn, btnIdx: number) => {
              Text(btn.text)
                .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .layoutWeight(1).height(36)
                .backgroundColor(botButtonBg(btn.style, '#4d000000'))
                .borderRadius(8)
                .stateStyles({ normal: contentButtonNormal, pressed: contentButtonPressed })
                .animation({ duration: this.effectDuration(100), curve: Curve.EaseOut })
                .onClick(this.clickCallback(btn, rowIdx, btnIdx));
            // 点击目标、游戏分支和样式都属于组件身份，不能只看显示文字。
            }, (btn: InlineBtn, btnIdx: number) => this.keyPlan.buttons[rowIdx]?.[btnIdx] ?? '');
          }.width('100%');
        // 行键也得带内容。**只修内层的按钮键是修不动的**：外层键不变时 ForEach
      // 连行的构建函数都不会重跑，内层那个 ForEach 拿的还是上一条消息的
      // `row`，按钮文字于是停在上一条上——与相册格子当年同一个机理，推导见
      // albumGrid 上方那段（相册已改成固定槽位，不再靠键）。
      }, (row: InlineBtn[], rowIdx: number) => this.keyPlan.rows[rowIdx] ?? '');
      }
      // Match the bubble's MEASURED width (it shrinks to fit its content), so
      // the keyboard is never wider than the bubble above it.
      .width(this.drawnWidth > 0 ? this.drawnWidth : this.context.bubbleW > 0 ? this.context.bubbleW : this.inlineMaxW() + 16);
    }
    .width('100%')
    .padding({
      // Align with the bubble body; every row reserves the same 7vp tail
      // gutter so first/middle/last bubbles never shift horizontally.
      left: this.drawnWidth > 0 ? this.drawnLeft : 10 + (this.msg.isOutgoing ? 0 : (this.data.isGroup ? 38 : 0) +
        7),
      right: this.drawnWidth > 0 ? this.drawnRight : 10 + (this.msg.isOutgoing ? 7 : 0),
      top: 2, bottom: 2
    })
    .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start);
  }

  private inlineMaxW(): number {
    return this.bubbleMaxW() - 16;
  }

  private bubbleMaxW(): number {
    // 只有群聊来信才有头像位；发出的消息和私聊来信按 0 算，能宽出 44vp。
    return bubbleMaxWidth(this.data.contentWidth, this.avatarReserve());
  }

  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }


  build() { this.inlineKeyboard(); }
}
