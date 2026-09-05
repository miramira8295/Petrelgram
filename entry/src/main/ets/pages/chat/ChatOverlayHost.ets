import { MessageEntry } from '../../store/MessageEntry';
import { ChatOverlayState } from './ChatOverlayState';
import { ReactionSheet } from './ReactionSheet';
import { ForwardSheet } from './ForwardSheet';
import { ScheduledSheet } from './ScheduledSheet';
import { PollComposeSheet } from './PollComposeSheet';
import { ContactPickerSheet, PickedContact } from './ContactPickerSheet';
import { VideoNoteRecorderView } from './VideoNoteRecorderView';

// Presentation host for the transient chat overlays. ChatPage retains the
// state and business actions; this component only wires values and events into
// the existing sheets.
//
// 【B11】showReactionSheet/showForwardSheet/showScheduledSheet/showPollSheet/
// showContactSheet/showVideoNoteRecorder/reactionTargetId/reactionPendingKey/
// forwardMessageIds 这 9 个标量 @Param 收口成一个 @Require @Param
// overlayState: ChatOverlayState——组件内所有读点相应改成 this.overlayState.xxx。
// messages/chatId/threadRootId/bottomSafe/keyboardH 不属于 overlay 簇（页面
// 持有的会话级/视口状态），原样保留标量 @Param。
@ComponentV2
export struct ChatOverlayHost {
  @Require @Param overlayState: ChatOverlayState;

  @Param messages: MessageEntry[] = [];
  @Param chatId: number = 0;
  @Param threadRootId: number = 0;
  @Param bottomSafe: number = 0;
  @Param keyboardH: number = 0;

  // onReactionShowChange/onForwardShowChange/onScheduledShowChange 三个
  // @Event 在 B11 之前把 show 值再转发回页面去写 this.showXxx；现在这三个
  // sheet 的 show/onShowChange 直接落在 this.overlayState.setSheet(kind, show)
  // 上（见下方 build() 里三处 onShowChange），组件自己就能收窄这段重渲染依
  // 赖，不再需要绕页面一趟——因此这三个 @Event 字段本身被收掉，不是漏写。
  @Event onReactionPick: (reactionKey: string, chosen: boolean) => void =
    (): void => {};
  @Event onForwardSent: () => void = (): void => {};
  @Event onPollSubmit: (question: string, options: string[], isAnonymous: boolean,
    isQuiz: boolean, correctOptionId: number) => void = (): void => {};
  @Event onPollClose: () => void = (): void => {};
  @Event onContactPick: (contact: PickedContact) => void = (): void => {};
  @Event onContactClose: () => void = (): void => {};
  @Event onVideoCaptured: (path: string, durationSec: number, length: number) => void =
    (): void => {};
  @Event onVideoClose: () => void = (): void => {};
  @Event effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;

  // 六个开关里有没有任何一个开着。B11b 把"要不要挂载本组件"这道判据从
  // ChatPage 收了进来，页面 build 因此不再读这六个 @Trace；代价是本组件常驻
  // 挂载，所以需要这个判据来决定根 Stack 要不要吃触摸事件（见 build 末尾）。
  //
  // 写成方法而不是把六项表达式直接铺在属性里：这一串在 build 里要出现两次
  // （hitTestBehavior 一次，将来若有别的属性还要一次），铺开容易漏改一项。
  // 方法体里的 @Trace 读取照样被 V2 记账——同 ChatComposerInput.secondsLabel()、
  // ChatPage.prepareMessageBubble 里 translationActive() 的用法。
  private anyOpen(): boolean {
    return this.overlayState.showReactionSheet || this.overlayState.showForwardSheet ||
      this.overlayState.showScheduledSheet || this.overlayState.showPollSheet ||
      this.overlayState.showContactSheet || this.overlayState.showVideoNoteRecorder;
  }

  build() {
    Stack() {
      if (this.overlayState.showReactionSheet) {
        ReactionSheet({
          show: this.overlayState.showReactionSheet,
          onShowChange: (show: boolean): void => { this.overlayState.setSheet('reaction', show); },
          messages: this.messages,
          targetId: this.overlayState.reactionTargetId,
          chatId: this.chatId,
          pendingKey: this.overlayState.reactionPendingKey,
          // ReactionSheet no longer reads V1 storage props for these values.
          bottomSafe: this.bottomSafe,
          keyboardH: this.keyboardH,
          effectDuration: (key: string, ms: number): number => this.effectDuration(key, ms),
          onPick: (reactionKey: string, chosen: boolean): void => {
            this.onReactionPick(reactionKey, chosen);
          }
        });
      }
      if (this.overlayState.showForwardSheet) {
        ForwardSheet({
          show: this.overlayState.showForwardSheet,
          onShowChange: (show: boolean): void => { this.overlayState.setSheet('forward', show); },
          messageIds: this.overlayState.forwardMessageIds,
          sourceChatId: this.chatId,
          threadRootId: this.threadRootId,
          effectDuration: (key: string, ms: number): number => this.effectDuration(key, ms),
          onSent: (): void => { this.onForwardSent(); }
        });
      }
      if (this.overlayState.showScheduledSheet) {
        ScheduledSheet({
          show: this.overlayState.showScheduledSheet,
          onShowChange: (show: boolean): void => { this.overlayState.setSheet('scheduled', show); },
          chatId: this.chatId
        });
      }
      if (this.overlayState.showPollSheet) {
        PollComposeSheet({
          onSubmit: (question: string, options: string[], isAnonymous: boolean,
            isQuiz: boolean, correctOptionId: number): void => {
            this.onPollSubmit(question, options, isAnonymous, isQuiz, correctOptionId);
          },
          onClose: (): void => { this.onPollClose(); }
        });
      }
      if (this.overlayState.showContactSheet) {
        ContactPickerSheet({
          onPick: (contact: PickedContact): void => { this.onContactPick(contact); },
          onClose: (): void => { this.onContactClose(); }
        });
      }
      if (this.overlayState.showVideoNoteRecorder) {
        VideoNoteRecorderView({
          onCaptured: (path: string, durationSec: number, length: number): void => {
            this.onVideoCaptured(path, durationSec, length);
          },
          onClose: (): void => { this.onVideoClose(); }
        });
      }
    }
    .width('100%').height('100%')
    // 【B11b：常驻挂载之后这一行是必须的】
    // B11 之前这个根 Stack 只在"有 sheet 开着"时才被挂上去，所以它是不是全屏、
    // 吃不吃触摸都无所谓。B11b 把那道判据收进本组件（页面 build 不再读那六个
    // @Trace），本组件因此**一直挂着**——一个 width/height 100% 的 Stack 常驻
    // 在会话页上方，默认命中模式下会把整页的触摸全吃掉，表现是消息列表、输入
    // 框、所有按钮统统点不动。
    //
    // 所以按开合切：有 sheet 开着时用 Default（与 B11b 之前一模一样，那时候
    // 根本没写这个属性，Default 就是默认值）；一个都没开时用 None——自身与子
    // 节点都不响应，触摸原样穿过去给下面的会话页。
    // 同一个父 Stack 里的贴纸残影 Image 用的也是 HitTestMode.None，同款先例。
    //
    // **这一行删了或者判据写反，后果是整个会话页不响应触摸**，而本地单测一条
    // 都覆盖不到（没有真实渲染树、没有命中测试）。改动此处必须上真机点一下
    // 消息列表和输入框。
    .hitTestBehavior(this.anyOpen() ? HitTestMode.Default : HitTestMode.None);
  }
}
