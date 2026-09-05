// 反应弹层 / 转发弹层 / 投票·联系人·录制·定时消息弹层的开关状态，以及贴纸
// "飞出"残影动画。从 ChatPage 整体搬出（B11 批）。
//
// 【为什么这些字段拼在一起】
// 六个 sheet 开关（反应/转发/定时/投票/联系人/录像笔记）共享同一处渲染
// 依赖——build() 里唯一读它们的地方是那一整段 ChatOverlayHost 实例化：
// `if (this.showReactionSheet || this.showForwardSheet || ...)`。反应目标 id/
// 互斥锁、转发消息 id 列表是各自 sheet 的入参，贴纸残影动画虽然不挂在任何一个
// sheet 上，但生命周期同样短、同样只在 build() 里被这一小段渲染读到，划进
// 同一簇管理。
//
// 【为什么 messages/findMsg、store、chatId、setEmojiPanel、chatEffectDuration
// 都不搬】
// findMsg 遍历的是页面的 `this.messages`，本簇不拥有消息列表；store/chatId
// 是页面持有的会话级状态，随路由切换而变，控制器不缓存，每次经宿主取值器
// 现取；setEmojiPanel(false) 操作的是表情/贴纸面板域字段 showEmojiPanel，
// 与本簇是两个不相关的域；chatEffectDuration 读 powerSaving/reduceAnimations/
// autoplayVideo 三个 @Param，同样是页面持有的状态。这五样全部经
// ChatOverlayStateHost 的取值器/动作回调中转，本类只调用，不持有引用。
//
// 【paidMediaPendingIds 为什么不搬】
// resetMessageActionSession() 里紧挨着本簇四个字段的清零语句，但它是付费
// 媒体解锁域自己的字段，不属于 overlay 簇，本批不动，仍由页面自己清。
//
// 【reactionPendingKey 互斥锁：两处 === key 比较一个都不能少】
// toggleReaction 发起时把 `${messageId}_${reactionKey}` 拼成的 key 写进锁，
// 两个异步回调（成功/失败）里都先判 `this.reactionPendingKey === key` 才清
// 空——不是无条件清空。因为回调触发时锁可能已经被别的调用重新设置（或者已经
// 被 resetSession()/dispose() 清空），这时候不能把别人刚设上的新锁提前放行，
// 也不能把已经是空的锁再清一次导致语义错乱。每次调用发一枚一次性凭证，只认
// 自己发的那枚。
//
// 【flyStickerGhost：连发保护只挂在收尾 timer 上】
// 每次进入都先查 `stickerGhostTimer !== -1`，若还是上一轮挂着的收尾定时器
// 句柄就 clearTimeout 掉——这是唯一的"连发保护"点。16ms 那个"起始态先落地
// 一帧"的裸 setTimeout 原文没有存句柄，也没有清理，是有意为之的一次性任务，
// 搬迁时原样保留，不新增比较/守卫。
//
// 【dispose() 与 resetSession() 是两个不同的清零点，字段集合不对称】
// resetSession()（对应原 resetMessageActionSession，换会话时触发）清 4 个
// 字段：showReactionSheet/reactionTargetId/reactionPendingKey +
// closeForwardSheet()。dispose()（对应原 disposeTimersAndSeqGuards，页面
// 整体销毁时触发）只清 showReactionSheet/reactionTargetId +
// closeForwardSheet() 这 3 处——**原代码在这条路径上就没有清
// reactionPendingKey**，这是原有的不对称，不是遗漏，搬迁时如实保留，没有替
// dispose() 补上这一行。
// 【B11 新增行为，非逐字搬迁】stickerGhostTimer 在原 aboutToDisappear 全链路
// 里没有任何清理动作（页面销毁时纯靠 GC，不清定时器句柄）。任务书明确要求
// "dispose() 清 stickerGhostTimer"，这是本批新增的加固，不是原代码就有的
// 行为——原样标注在此，不要误当成从旧代码抄来的逐字搬迁。
//
// 【与 ComposerSession/SearchSession/HeaderIdentitySession 同款约定】
// per-ChatPage 字段初始化器 new，绝非模块级单例；宿主接口全是箭头函数取值器，
// 现取不缓存；类中不声明 @Monitor（解注册依赖 GC，销毁时机不可靠）。

import { promptAction } from '@kit.ArkUI';
import { KEY_POWER_EFFECT_MENU } from '../../store/AppSettings';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import { getTdClient, getUserStore, getChatStore } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { STICKER_FLY_MS } from '../../util/chatPageTuning';
import { logE } from '../../util/log';
import {
  AvailableReactionSet, canonicalReactionEmoji, parseAvailableReactions, reactionDisplayLabel,
  reactionTypeOf
} from '../../util/reactions';
import { str } from '../../util/strings';

// setSheet() 的第一个参数：build() 里 ChatOverlayHost 的六个 onXxxShowChange
// 回调共用同一个写入口时用它区分是哪一个开关。
export type ChatOverlaySheetKind =
  'reaction' | 'forward' | 'scheduled' | 'poll' | 'contact' | 'videoNote';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，动作回调把副作用交回页面执行。仿 ComposerSession 的
// ComposerSessionHost。
//
// 两条纪律（与其余控制器一致）：
// 1. 这里只放**取值器**，不放页面的 @Local/状态引用。控制器不缓存页面的值，
//    每次要用就现取——否则页面改了字段、控制器手里还是旧的。
// 2. messages/store/chatId 等留页面的状态，本类只经这里的取值器读，不在本类
//    里存一份影子拷贝。
export interface ChatOverlayStateHost {
  // 当前 MessageStore；路由切换途中可能为 null。toggleReaction 用它发送
  // setReaction 请求（原实现在方法体最开头取一次快照存进局部变量，两个异步
  // 回调共享同一份快照——搬进控制器后仍然是"调用时现取一次，不缓存"）。
  store: () => MessageStore | null;
  // 当前会话 id。ensureAllowedReactions 拼 getMessageAvailableReactions 请求、
  // showReactors 拼 getMessageAddedReactions 请求都要用。
  chatId: () => number;
  // 按 id 在页面当前消息列表（`this.messages`）里查一条，找不到返回 null。
  // openReactionSheet 用它确认目标消息还在，本簇不拥有消息列表。
  findMsg: (messageId: number) => MessageEntry | null;
  // flyStickerGhost 里原来直接调用的 this.setEmojiPanel(false)——表情/贴纸
  // 抽屉域与本簇无关，仍由页面处理。
  setEmojiPanel: (show: boolean) => void;
  // flyStickerGhost 里原来直接调用的
  // this.chatEffectDuration(KEY_POWER_EFFECT_MENU, STICKER_FLY_MS)——读
  // powerSaving/reduceAnimations/autoplayVideo 三个 @Param，页面自己算，本类
  // 只经这个取值器拿结果，不把那三个 @Param 的依赖搬进来。
  effectDuration: (key: string, ms: number) => number;
}

@ObservedV2
export class ChatOverlayState {
  // ——— 显示态：ChatOverlayHost 直接读这些 @Trace ———

  @Trace showReactionSheet: boolean = false; // full emoji reaction picker
  @Trace reactionTargetId: number = 0;
  // The allowed-emoji list and custom-emoji thumbnails live in ReactionSheet,
  // which fetches them per open. Only the in-flight key stays here: the quick
  // reaction row on each bubble issues the same request and shares the guard.
  @Trace reactionPendingKey: string = '';
  // Forwarding is deliberately kept as an in-page sheet: leaving ChatPage to
  // pick a destination used to discard the long-press/selection context.
  @Trace showForwardSheet: boolean = false;
  @Trace showPollSheet: boolean = false;
  @Trace showContactSheet: boolean = false;
  @Trace showVideoNoteRecorder: boolean = false;
  // The list itself lives in ScheduledSheet and reloads on each open.
  @Trace showScheduledSheet: boolean = false;
  // Which messages the picker will forward. The picker's own list/query/send
  // state lives in ForwardSheet and resets with it on each open.
  // 【B11】原字段是不带 @Trace 的 private number[]；方案 §4 把它与其余五个
  // sheet 开关同批列进 @Trace，本类照方案升级——因为它总是与 showForwardSheet
  // 同一次写入、同一次读出（build() 里的 @Param 透传），升级后不预期引入可
  // 观察的行为差异，但这确实是"新增一层依赖收集"的变化，不是纯粹的逐字搬迁，
  // 在此明确标注，不要被当成顺手优化漏审。
  @Trace forwardMessageIds: number[] = [];
  // 贴纸"飞出"动画：从点击处向上收缩淡出，动画收尾时才关面板 —— 关面板要
  // 同步卸载整个贴纸网格并触发全页重排（实测 51ms），压在点击那一帧就是可感
  // 的顿挫；挪到运动尾声则被动作本身盖住。
  @Trace stickerGhostPath: string = '';
  @Trace stickerGhostX: number = 0;
  @Trace stickerGhostY: number = 0;
  @Trace stickerGhostFly: boolean = false;

  // ——— 内部机件：一律**不加 @Trace** ———

  private stickerGhostTimer: number = -1;
  // reactionKey：标准 emoji 原样，自定义 emoji 为 'ce:<custom_emoji_id>'。
  // 本会话允许的表情（服务端的规范写法）。我们内置的快捷表情带变体选择符，
  // 服务端的可能不带，差一个码位 TDLib 就判 REACTION_INVALID——所以发之前先换成
  // 它认的那一个。拉一次缓存在页面上，失败就当没有（不拦着用户发）。
  private allowedReactions: string[] = [];
  private allowedReactionsTask: Promise<string[]> | null = null;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的值。
  private host: ChatOverlayStateHost = {
    store: (): MessageStore | null => null,
    chatId: (): number => 0,
    findMsg: (_messageId: number): MessageEntry | null => null,
    setEmojiPanel: (_show: boolean): void => {},
    effectDuration: (_key: string, ms: number): number => ms
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: ChatOverlayStateHost): void {
    this.host = host;
  }

  // build() 里 ChatOverlayHost 六个 onXxxShowChange 回调的统一写入口——原代码
  // 六处回调各自都是形如 `(show) => { this.showXxx = show; }` 的一行赋值，
  // 只是碰巧散在同一段实参列表里，这里合并成一个方法只是把六份重复代码收口，
  // 每个分支落地的效果和原来逐字一致。
  setSheet(kind: ChatOverlaySheetKind, show: boolean): void {
    switch (kind) {
      case 'reaction':
        this.showReactionSheet = show;
        break;
      case 'forward':
        this.showForwardSheet = show;
        break;
      case 'scheduled':
        this.showScheduledSheet = show;
        break;
      case 'poll':
        this.showPollSheet = show;
        break;
      case 'contact':
        this.showContactSheet = show;
        break;
      case 'videoNote':
        this.showVideoNoteRecorder = show;
        break;
      default:
        break;
    }
  }

  openReactionSheet(messageId: number): void {
    ContextMenu.close();
    if (this.host.findMsg(messageId) === null) {
      return;
    }
    this.reactionTargetId = messageId;
    this.showReactionSheet = true;
  }

  closeReactionSheet(): void {
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
  }

  // **要等它回来再发**：第一次点的时候列表还是空的，直接发就等于发我们内置的
  // 原串（带 U+FE0F），必被判 REACTION_INVALID——用户看到的是「第一个表情第一次
  // 永远失败，再点才行」。拉一次缓存在页面上，之后都是同步命中。
  ensureAllowedReactions(messageId: number): Promise<string[]> {
    if (this.allowedReactions.length > 0) {
      return Promise.resolve(this.allowedReactions);
    }
    const running: Promise<string[]> | null = this.allowedReactionsTask;
    if (running !== null) {
      return running;
    }
    const req: TdRequest = { '@type': 'getMessageAvailableReactions' };
    req['chat_id'] = this.host.chatId();
    req['message_id'] = messageId;
    req['row_size'] = 8;
    const task: Promise<string[]> = getTdClient().send(req).then((result: TdObject): string[] => {
      const set: AvailableReactionSet = parseAvailableReactions(result);
      this.allowedReactions = set.emojis;
      this.allowedReactionsTask = null;
      return this.allowedReactions;
    }).catch((e: TdError): string[] => {
      // 拉不到就按原串发（可能成功，也可能报错——总比拦着用户强）。
      this.allowedReactionsTask = null;
      logE(`ChatOverlayState.ensureAllowedReactions failed: ${e.message}`);
      return [];
    });
    this.allowedReactionsTask = task;
    return task;
  }

  toggleReaction(messageId: number, reactionKey: string, isChosen: boolean): void {
    const store: MessageStore | null = this.host.store();
    const key: string = `${messageId}_${reactionKey}`;
    if (store === null || this.reactionPendingKey !== '') {
      return;
    }
    ContextMenu.close();
    this.reactionPendingKey = key;
    // 自定义表情（'ce:' 前缀）不做映射：它按 id 走，不涉及变体选择符。
    const custom: boolean = reactionKey.startsWith('ce:');
    const ready: Promise<string[]> = custom
      ? Promise.resolve(this.allowedReactions) : this.ensureAllowedReactions(messageId);
    let sendKey: string = reactionKey;
    ready.then((allowed: string[]): Promise<void> => {
      sendKey = custom ? reactionKey : canonicalReactionEmoji(reactionKey, allowed);
      return store.setReaction(messageId, sendKey, isChosen);
    }).then((): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
    }).catch((e: TdError): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
      logE(`ChatOverlayState.toggleReaction(${sendKey}) failed: ${e.message}`);
      // 带上服务端的原因：光说「失败」用户没法反馈，我们也查不动。
      promptAction.showToast({
        message: `${str('cp_reaction_failed')} · ${e.message}`, duration: 2200
      });
    });
  }

  // Long-press on a reaction chip: who reacted with it.
  showReactors(messageId: number, reactionKey: string): void {
    const req: TdRequest = { '@type': 'getMessageAddedReactions' };
    req['chat_id'] = this.host.chatId();
    req['message_id'] = messageId;
    req['reaction_type'] = reactionTypeOf(reactionKey);
    req['offset'] = '';
    req['limit'] = 50;
    getTdClient().send(req, 10000).then((result: TdObject): void => {
      const rows = (result['reactions'] as TdObject[] | undefined) ?? [];
      const total = (result['total_count'] as number | undefined) ?? rows.length;
      const names: string[] = [];
      for (const row of rows) {
        const sender = row['sender_id'] as TdObject | undefined;
        if (sender === undefined) { continue; }
        if (sender['@type'] === 'messageSenderUser') {
          const uid = (sender['user_id'] as number | undefined) ?? 0;
          const name = getUserStore().displayName(uid);
          if (name === '') { getUserStore().ensure(uid); }
          names.push(name !== '' ? name : str('cp_user_id', uid));
        } else {
          const cid = (sender['chat_id'] as number | undefined) ?? 0;
          const entry = getChatStore().entryOf(cid);
          names.push(entry !== undefined ? entry.title : str('cp_anonymous'));
        }
      }
      promptAction.showDialog({
        title: str('cp_reaction_total', reactionDisplayLabel(reactionKey), total),
        message: names.length > 0 ? names.join('\n') : $r('app.string.cp_no_details'),
        buttons: [{ text: $r('app.string.close'), color: '#3390EC' }]
      }).catch((): void => {});
    }).catch((e: TdError): void => {
      logE(`ChatOverlayState.showReactors failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_no_reaction_details'), duration: 1600 });
    });
  }

  // Only decides *whether* the picker opens and what it will forward — the chat
  // list, filtering and the forwardMessages request live in ForwardSheet.
  //
  // 【只搬写字段那部分】原 openForwardPicker 里 forwardableMessageIds 计算、
  // ContextMenu.close()、"没有可转发消息就 toast 返回" 这几步都依赖页面的
  // `this.messages`/`this.findMsg`，留在页面；页面算出非空的 validIds 之后
  // 才调这里，本方法只接手原方法体最后那几行——this.closeReactionSheet()、
  // this.setEmojiPanel(false)（经宿主转发）、写 forwardMessageIds/
  // showForwardSheet，逐字对应原方法尾部的那四行，先后顺序不变。
  openForwardPicker(validIds: number[]): void {
    this.closeReactionSheet();
    this.host.setEmojiPanel(false);
    this.forwardMessageIds = validIds;
    this.showForwardSheet = true;
  }

  closeForwardSheet(): void {
    this.showForwardSheet = false;
    this.forwardMessageIds = [];
  }

  // Show/hide the emoji/sticker panel without resizing the message viewport.
  // 发出去之后的收尾。残影是独立浮层，和面板收起**并行**跑：先前把关面板
  // 排在飞出动画之后，串行等待让面板要一秒多才下去，感觉像卡住了。
  //
  // 【签名/命名变化，B11】原方法名 finishStickerSend(thumbPath, x, y)，页面
  // 侧调用点改为 this.overlay.flyStickerGhost(thumbPath, x, y)——方法体逐字
  // 未改，只是搬进控制器后按任务书要求改了个更贴合动作本身的名字，不是本批
  // 擅自改的。
  flyStickerGhost(path: string, x: number, y: number): void {
    if (this.stickerGhostTimer !== -1) {
      clearTimeout(this.stickerGhostTimer);
      this.stickerGhostTimer = -1;
    }
    // 立刻开始收面板（内部已把卸载与动画分帧）。
    this.host.setEmojiPanel(false);
    const duration: number = this.host.effectDuration(KEY_POWER_EFFECT_MENU, STICKER_FLY_MS);
    if (duration === 0 || path === '') {
      this.stickerGhostPath = '';
      return;
    }
    this.stickerGhostPath = path;
    this.stickerGhostX = x;
    this.stickerGhostY = y;
    this.stickerGhostFly = false;
    // 起始态先落地一帧，否则终态和初始态在同一帧里，动画不会跑。
    setTimeout((): void => { this.stickerGhostFly = true; }, 16);
    this.stickerGhostTimer = setTimeout((): void => {
      this.stickerGhostTimer = -1;
      this.stickerGhostPath = '';
      this.stickerGhostFly = false;
    }, duration + 40);
  }

  // resetMessageActionSession 里本簇**前三行**的搬迁落点（B11）：
  // showReactionSheet=false; reactionTargetId=0; reactionPendingKey=''。
  // 换会话/非续读路由时触发；`selection.reset()`（B7 域）与
  // `paidMediaPendingIds=[]`（付费媒体域）不属于本簇，仍留在页面。
  //
  // 【为什么这里**不**顺手把 closeForwardSheet() 也收进来】
  // 原文那六行里，本簇的第四行 closeForwardSheet() 排在
  // `paidMediaPendingIds = []` **之后**，不是连续的：
  //     this.selection.reset();
  //     this.showReactionSheet = false;
  //     this.reactionTargetId = 0;
  //     this.reactionPendingKey = '';
  //     this.paidMediaPendingIds = [];      ← 中间，别簇
  //     this.closeForwardSheet();           ← 最后，本簇
  // 把四行一并收进来就等于把 closeForwardSheet() 提到了 paidMediaPendingIds
  // 之前。这两者互不相关、之间没有读点，本帧内看不出差别——但那是**推断**出来
  // 的无害，不是搬迁纪律给的保证。页面侧因此在原位分两次调用，语句顺序与
  // HEAD 逐字一致。dispose() 那条路径上这两行本来就是连续的，所以那边收进去了。
  resetSession(): void {
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.reactionPendingKey = '';
  }

  // disposeTimersAndSeqGuards（aboutToDisappear 路径，页面整体销毁）里本簇
  // 那三行的搬迁落点：showReactionSheet=false; reactionTargetId=0;
  // closeForwardSheet()。**与 resetSession() 字段集合不对称**——原代码在这条
  // 路径上没有清 reactionPendingKey，是原有行为，如实保留，不补齐。
  // 【B11 新增】stickerGhostTimer 的清理是任务书明确要求的加固，原
  // aboutToDisappear 全链路里对这个定时器没有任何清理动作——这一行是本批
  // 主动新增的行为，不是从旧代码搬来的。
  dispose(): void {
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.closeForwardSheet();
    if (this.stickerGhostTimer !== -1) {
      clearTimeout(this.stickerGhostTimer);
      this.stickerGhostTimer = -1;
    }
  }
}
