// 对方"正在输入…"提示的状态与轮询定时器。从 ChatPage 整体搬出（B10 批）。
//
// 【为什么要搬】
// typingLabel 只喂两处：输入区占位符（composerPlaceholder）和它间接驱动的
// ChatComposerInput 一个 @Param。搬之前它是 ChatPage 的 @Local，任何一次
// updateChatAction 到达、或 1500ms 轮询裁掉一个过期项，都要重跑一遍页面的
// 依赖收集。搬进 @ObservedV2 之后状态和定时器收进一个能单测的对象里；
// composerPlaceholder 仍留页面（它还要读 replyKbVisible()/replyKeyboard，
// 与本簇无关），只是把 `this.typingLabel` 换成 `this.typing.label`。
//
// 【纯逻辑不在本类里重新实现】
// 过滤/到期/文案三段纯函数在 util/typingIndicator.ets（B3 抽出，由
// entry/src/test/TypingIndicator.test.ets 钉住）：applyTypingUpdate 判定一条
// updateChatAction 是否落在本会话/本话题作用域内并就地更新到期表，
// pruneExpiredTyping 裁掉过期项，typingLabelOf 按「私聊/密聊」与「群/频道」
// 两档合成文案。本类只搬运状态容器（到期表、轮询定时器、显示态字段）与围绕
// 这三个纯函数的副作用（getUserStore().ensure/displayName、写 @Trace label）。
//
// 【senders 按引用喂给纯函数，是刻意的】
// applyTypingUpdate/pruneExpiredTyping 就地修改传入的 Map，不返回新表——这不是
// 纯函数破例，是刻意的「传入可变容器」：不复制 Map 才能让本类继续持有唯一
// 真源，也避免每条 chatAction/每轮轮询都新建一张表（原页面注释原样保留）。
//
// 【currentKind 必须经 host 取值器现取，不能retreat到近似值】
// rebuildTypingLabel 要按「私聊/密聊」与「群/频道」两档挑文案，档位来自 B8
// HeaderIdentitySession 的 currentKind()。这一条 host 回调是 B9/B10 之间
// 唯一的耦合点，也是 B8 迁移时踩过的坑：一度用 `isGroup ? 'group' : 'private'`
// 顶替，那个判据在 identity 首次解析之前会把默认档从「群」错翻成「私聊」。
// 本类不得在内部缓存一份 kind 影子拷贝，也不得用 isGroup 之类的字段猜——
// 每次要用就经 host.currentKind() 现取当下的真值。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，各自会话的输入提示互不相干。
// 做成单例会让两页互相覆盖对方的"正在输入"文案。页面用字段初始化器 new 一个：
// 首帧前就已存在、引用全生命周期稳定、类型非空。
//
// 【为什么没有 …Seq 守卫】
// 本簇不发任何 TDLib 请求（updateChatAction 是 TDLib 主动推送，不是本类发出的
// 请求的响应），不存在"发出去的请求晚于后来的操作回来"这种竞态，因此没有序号
// 要守。timer 仍然是需要跨调用保留的句柄，dispose() 负责清掉它。
//
// 【dispose() 只清定时器，不清 senders/label】
// 搬之前 aboutToDisappear 对这簇状态唯一做的事就是 clearInterval 那三行，
// 并不连带清空 typingSenders 或把 typingLabel 归零——页面销毁在即，那两样
// 清不清都不影响任何人。dispose() 逐字保留这个范围，不额外"顺手"清理。
//
// 【不在本类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。本簇没有需要监听
// @Param/@Local 变化联动的地方，天然用不上 @Monitor。

import { TdObject } from '../../tdkit/TdTypes';
import { getUserStore } from '../../tdkit/Globals';
import { applyTypingUpdate, pruneExpiredTyping, typingLabelOf } from '../../util/typingIndicator';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，本类不缓存。仿 LiveTopCardController.ets 的 LiveTopCardHost。
export interface TypingIndicatorHost {
  // 当前会话/话题作用域四件套，onChatAction 的过滤判据直接吃这四个值。
  chatId: () => number;
  threadRootId: () => number;
  forumTopicId: () => number;
  directMessagesTopicId: () => number;
  // B8 HeaderIdentitySession.currentKind() 的转发——本类不得直接持有 header
  // 控制器的引用（控制器只与页面 host 打交道，不与兄弟控制器互相引用），
  // 也不得用 isGroup 之类的近似值顶替（见文件头说明）。
  currentKind: () => string;
}

@ObservedV2
export class TypingIndicatorState {
  // ——— 显示态：composerPlaceholder()（留在页面）直接读这个 @Trace ———
  // 原 ChatPage @Local typingLabel。

  @Trace label: string = '';

  // ——— 内部机件：一律**不加 @Trace** ———
  // 到期表与定时器句柄都不驱动任何 UI，加了 @Trace 只会在每次 set/delete 或
  // 定时器自增时白发一轮通知。

  // senderId -> expiry ms。**按引用**传进 util/typingIndicator 的纯函数，
  // 由它们就地修改——见文件头「senders 按引用喂给纯函数」。
  private senders: Map<number, number> = new Map();
  // -1 = 未在轮询。
  private timer: number = -1;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是"什么都还没有"的值。
  private host: TypingIndicatorHost = {
    chatId: (): number => 0,
    threadRootId: (): number => 0,
    forumTopicId: (): number => 0,
    directMessagesTopicId: (): number => 0,
    currentKind: (): string => ''
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: TypingIndicatorHost): void {
    this.host = host;
  }

  // Live "typing…" from peers (updateChatAction). Entries expire after 6s —
  // TDLib sends chatActionCancel, but a dropped cancel must not stick forever.
  //
  // 过滤/到期/文案三段纯逻辑在 util/typingIndicator.ets（由
  // entry/src/test/TypingIndicator.test.ets 钉住）；留在这里的是副作用：
  // getUserStore().ensure、1500ms 轮询定时器、写 @Trace label。
  onChatAction(update: TdObject): void {
    const uid: number = applyTypingUpdate(this.senders, update, Date.now(),
      this.host.chatId(), this.host.threadRootId(), this.host.forumTopicId(),
      this.host.directMessagesTopicId());
    if (uid === 0) { return; }
    // 记下了一次输入（不是 cancel）才去补用户资料——顺序同原实现：set 之后、
    // 重建文案之前。
    if (this.senders.has(uid)) {
      getUserStore().ensure(uid);
    }
    this.rebuildTypingLabel();
    if (this.timer === -1 && this.senders.size > 0) {
      this.timer = setInterval((): void => {
        if (pruneExpiredTyping(this.senders, Date.now())) { this.rebuildTypingLabel(); }
        if (this.senders.size === 0 && this.timer !== -1) {
          clearInterval(this.timer);
          this.timer = -1;
        }
      }, 1500);
    }
  }

  // typingLabelOf 用 headerKind 分两档：'private'/'secret' 走简单的「正在输入…」，
  // 其余（group/channel/''）走人数/姓名那两档。kind 字段随 B8 迁进
  // HeaderIdentitySession 成了 private，这里经 host.currentKind() 原样取回——
  // 迁移中途曾用 `isGroup ? 'group' : 'private'` 顶替，那个判据在 identity 首次
  // 解析之前会把默认档从「群」翻成「私聊」，取值器把这点差异消掉了（B8 教训，
  // B10 不得重犯）。
  private rebuildTypingLabel(): void {
    this.label = typingLabelOf(this.host.currentKind(),
      Array.from(this.senders.keys()),
      (uid: number): string => getUserStore().displayName(uid));
  }

  // ChatPage.disposePlaybackAndSlots 调用（aboutToDisappear 分组之一），放在
  // 原来清 typingTimer 的位置。
  //
  // 只清定时器，不清 senders/label——搬之前 aboutToDisappear 在这簇状态上
  // 唯一做的事就是这三行 clearInterval，见文件头「dispose() 只清定时器」。
  // 没有 seq 需要先 ++（本簇没有在途的异步请求要作废，见文件头「为什么没有
  // …Seq 守卫」），因此不套用其余控制器"先 ++seq 再清定时器"的顺序约定。
  dispose(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }
}
