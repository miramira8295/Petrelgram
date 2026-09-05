// 输入条上方那三块建议面板（@ 成员、/ 命令、@bot 内联结果、纯 emoji 贴纸建议）的
// 状态与并发守卫。从 ChatPage 整体搬出（B14 批）。方案见
// docs/chatpage-slimming-plan.md §B14。
//
// 【为什么一个文件放四个类】
// 方案原文明确要求这四个 @ObservedV2 类同文件：MentionSuggestionState、
// CommandSuggestionState、InlineQueryState、StickerSuggestionState。四者各自
// 独立生命周期、互不引用，但都只服务"输入条上方浮出一块建议面板"这一件事，
// SuggestionPanel/InlineResultsBar/StickerSuggestionBar 三个消费方也总是被
// updateSuggestions 这唯一路由入口三选一地驱动（见下）。拆成四个文件反而会让
// "谁跟谁互斥"这件事失去一个能一眼看全的地方。
//
// 【updateSuggestions 是唯一路由入口，本批不动，仍留 ChatPage】
// 顺序：先 command（正则命中就转 refreshCommands 并 return）→ 再 mention
// （'@' 触发且是群聊非频道就转 refreshMentions 并 return）→ 否则 inline 与
// sticker 并列执行（两者都跑，互不 return）。三条路径互斥、inline/sticker
// 互不互斥。这个顺序本身不属于任何一簇的内部状态，搬迁后仍由页面按同样的
// if/return 骨架分别调用四个类暴露的 refresh 方法——本文件不重新实现这段路由。
//
// 【pick 类方法的去留】
// pickCommand（选中命令后还要调 this.doSend()）、sendSuggestedSticker
// （调 this.store?.sendSticker(...)）、pickInlineResult（调
// this.composer.clearReply() 与 sendInlineResult）三个方法涉及"店铺发送"或
// "composer 会话动作"，方案点名必须留在页面，本文件不搬。
// pickMention/mentionSender 不在点名清单里，但两者都要写页面的 this.draft——
// 按控制器约定（本文件不得缓存/直接改宿主字段），拆成两种设计：
//   - pickMention 全程同步，直接**返回新草稿串**，页面拿到返回值自己赋
//     this.draft（方案 249 行原文的模式）。
//   - mentionSender 内部是 mentionOfUser(...).then(...) 异步回调，回调里才能
//     算出新草稿——不可能"返回"给一个早已 return 过的调用点，因此改用
//     bind() 时注入的 host.applyDraft(next) 回调让页面在回调触发的当下写
//     this.draft。这一点意味着 pickMention 与 mentionSender 的返回形状不对称
//     （一个 return 一个 host 回调），这是同步/异步这两种前提本身决定的，
//    不是本文件"觉得应该"这样设计。
// 两者原本在写完 draft 之后都还有一行
// `setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);`。
// focusControl 是 ArkUI 的页面级能力、'chat_composer' 是页面自己的组件 id，
// 控制器不适合持有这个依赖，因此这一步也留给页面：pickMention 的调用点在拿到
// 返回串赋值 this.draft 之后自己补上那一行 setTimeout；mentionSender 的
// host.applyDraft 实现（页面侧）里把"赋 this.draft"与"排一次 0ms 请求焦点"
// 打包成一步，效果与原来单个方法里那两行紧挨着执行完全一致。
//
// 【inlineSeq 是一个字段，不是两个——最容易在这批被"顺手拆开"的地方】
// refreshInlineQuery 的防抖计时器到点后发出的 TDLib 查询、以及查询命中后逐条
// 触发的 downloadInlineThumb 缩略图下载，共用同一个 inlineSeq：查询自己
// `++`一次（refreshInlineQuery 里，唯一自增点），产生的值原样传给
// downloadInlineThumb，两条异步链回来时都拿它跟"当下的 this.inlineSeq"比对。
// 拆成 inlineQuerySeq/inlineThumbSeq 两个字段没有换来任何清晰度：缩略图链路
// 本来就不会自己产生新序号，永远复用查询链传下来的那个值，若拆开就变成必须
// 保证两个字段永远同步递增——只要将来给 inlineResults 加一条新的清空路径却
// 忘了同时 bump 两个字段，就会出现"查询已经作废但缩略图判据仍判定为新"，把
// 陈旧缩略图写回当前显示的结果行。本文件把 inlineSeq 保留为**单个** private
// 字段，downloadInlineThumb 与 refreshInlineQuery 共读共写同一份。
//
// 【为什么四个 dispose() 都是空实现】
// 逐字核对过 aboutToDisappear 全链路（disposeInitialStageAndTgs →
// disposePlaybackAndSlots → persistDraftAndViewport → disposeTimersAndSeqGuards
// → stopVoicePlaybackKeepingMusic → disposeSubscriptionsInOrder → closeStores），
// 对 mentionItems/pendingNameMentions/mentionSeq、commandItems/commandLoadState/
// commandLoadError/commandMenuOpen/botMenuAvailable/allCommands/commandLoadSeq、
// inlineResults/inlineQueryId/inlineSeq/inlineTimer、stickerSuggestions/
// stickerSuggestSeq 这四簇字段一个匹配都没有——页面销毁前从不清它们，包括那个
// 眼看着像该清的 inlineTimer（还挂着的 320ms 防抖定时器）。这与 B9/B10 批
// TypingIndicatorState 记录的"没有…Seq 守卫"是同一种情况的另一面：这里是有
// 定时器/序号却原本就不清。按铁律 2/3，dispose() 不新增任何原代码没有的清理
// 动作；真要补，得先跟作者对齐并在 behaviorChanges 里显式申报（未做）。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，各自会话的输入建议互不相干。
// 做成单例会让两页互相顶替对方正在弹出的建议面板。页面用字段初始化器分别
// new 四个类的实例：首帧前就已存在、引用全生命周期稳定、类型非空。
//
// 【不在这些类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。四簇状态的联动
// 全部用显式方法调用表达，天然用不上 @Monitor。

import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { TdClient } from '../../tdkit/TdClient';
import { getTdClient } from '../../tdkit/Globals';
import { MessageStore } from '../../store/MessageStore';
import {
  searchMentions, mentionOfUser, loadBotCommands, MentionItem, CommandItem
} from '../../store/InputSuggestions';
import { appendMention, mentionToken, mentionQueryOf } from '../../util/mentionDraft';
import { NameMention } from '../../util/mentionEntities';
import { InlineQueryPage, InlineResultRow, getInlineResults } from '../../store/BotApi';
import { getStickersForEmoji } from '../../store/StickerApi';
import { StickerSuggestion } from './ComposerStrips';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// ============================================================================
// MentionSuggestionState — '@' 成员候选
// ============================================================================

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，本类不缓存；applyDraft 是唯一的例外（一个动作回调，不是
// 取值器），供 mentionSender 的异步回调写回页面的 this.draft（见文件头说明）。
export interface MentionSuggestionHost {
  // 当前会话 id。
  chatId: () => number;
  // 页面当前的草稿文本。
  draft: () => string;
  // mentionSender 算出新草稿后，经这个回调交给页面赋 this.draft 并处理后续
  // 的 focusControl.requestFocus 调度（页面侧实现，见文件头）。
  applyDraft: (next: string) => void;
  // TDLib 客户端。搬之前这几个方法体里写的是模块级单例 `getTdClient()`；
  // 改经宿主取值器是本批唯一一处刻意的偏离逐字搬迁（同 B12 把
  // `getContext(this)` 改成 `host.context()` 的先例）。
  //
  // 【为什么非改不可】本簇四个 seq 守卫（丢弃陈旧响应）全部活在
  // `.then()/.catch()` 回调里。本地单测从不跑 initTdKit()，`getTdClient()`
  // 返回的是 undefined，`client.send(...)` 那一行同步抛错——异步回调**永远**
  // 进不去，这四个守卫因此一条用例都写不出来。方案 §3 早就写了"异步用注入的
  // fake"，这条缝就是补上那个约定。有了它，测试注入一个 FakeBridge 撑起来的
  // 真 TdClient，回调就走得通，守卫才钉得住。
  //
  // 页面侧实现恒为 `() => getTdClient()`，取值不缓存，与搬之前逐字等价。
  client: () => TdClient;
}

@ObservedV2
export class MentionSuggestionState {
  // ——— 显示态：SuggestionPanel 直接读这个 @Trace ———
  // '@' mention / '/' command suggestion panels above the input bar.
  @Trace mentionItems: MentionItem[] = [];

  // ——— 内部机件：一律不加 @Trace ———

  // 本次草稿里"按名字"提及过的成员。没有用户名的人，@ 出去只是一串普通
  // 文字，服务器识别不了、对方收不到提及通知——发送时要靠这份记录补上
  // textEntityTypeMentionName 实体（见 mentionEntities）。
  private pendingNameMentions: NameMention[] = [];
  private mentionSeq: number = 0; // drops stale searchChatMembers responses

  private host: MentionSuggestionHost = {
    chatId: (): number => 0,
    draft: (): string => '',
    applyDraft: (_next: string): void => {},
    // 未 bind 时的默认桩：直接回落到模块级单例，也就是搬迁前的原行为。
    // bind() 在 aboutToAppear 里、早于任何输入，正常路径上不会走到这里。
    client: (): TdClient => getTdClient()
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: MentionSuggestionHost): void {
    this.host = host;
  }

  refreshMentions(query: string): void {
    const seq = ++this.mentionSeq;
    searchMentions(this.host.client(), this.host.chatId(), query).then((items: MentionItem[]) => {
      // Drop the response if a newer query fired or the '@' trigger is gone.
      // 和上面共用同一个判定——两边不一致会出现「面板该弹却把结果丢掉」。
      if (seq !== this.mentionSeq || mentionQueryOf(this.host.draft()) === null) {
        return;
      }
      this.mentionItems = items;
    });
  }

  // 记下一次"按名字"的提及。有用户名的走 @username，服务器自己认得，不必记。
  private rememberNameMention(item: MentionItem, name: string): void {
    if (item.username !== '' || name === '' || item.userId <= 0) {
      return;
    }
    const known: boolean = this.pendingNameMentions.some(
      (m: NameMention): boolean => m.userId === item.userId && m.name === name);
    if (!known) {
      this.pendingNameMentions = [...this.pendingNameMentions, { name, userId: item.userId }];
    }
  }

  // Replace the trailing '@token' with the chosen member.
  //
  // 迁移设计（本段为新增说明，非原注释的一部分——原注释只有上面那一行英文）：
  // 原方法直接写 this.draft 并在 0ms 之后 focusControl.requestFocus
  // ('chat_composer')。控制器不碰宿主字段，也不该替页面持有 focusControl 这个
  // ArkUI 依赖，因此改成返回新草稿串，由页面调用处赋 this.draft 并自己补上那一
  // 行 setTimeout，顺序与原来一致。
  pickMention(item: MentionItem): string {
    const draft = this.host.draft();
    const idx = draft.lastIndexOf('@');
    const head = idx >= 0 ? draft.substring(0, idx) : draft;
    const next = `${head}${mentionToken(item.name, item.username)} `;
    this.rememberNameMention(item, item.name.trim());
    this.mentionItems = [];
    return next;
  }

  // Long press on a group message avatar → append that sender's mention to the
  // draft. The message entry has the sender's name but not their username, so
  // the username is fetched here; the name is the fallback if it has none.
  //
  // 本方法内部是异步回调，没法像 pickMention 那样直接返回新草稿串给一个早已
  // return 过的调用点，因此改走 host.applyDraft（见 MentionSuggestionHost 与
  // 文件头说明）。
  mentionSender(userId: number, fallbackName: string): void {
    mentionOfUser(this.host.client(), userId).then((item: MentionItem): void => {
      const name = item.name !== '' ? item.name : fallbackName;
      const token = mentionToken(name, item.username);
      if (token === '') {
        return;
      }
      this.host.applyDraft(appendMention(this.host.draft(), token));
      this.rememberNameMention(item, name.trim());
      this.mentionItems = [];
    });
  }

  // pendingNameMentions 的只读取值器：doSend 的 buildMentionEntities(text,
  // this.pendingNameMentions) 与失败前的快照捕获都只"读"，不需要写方法。
  readPendingNameMentions(): NameMention[] {
    return this.pendingNameMentions;
  }

  // doSend 发送前清空（原 `this.pendingNameMentions = [];`）、
  // sendPendingMedia 成功回调里同样清空。
  clearPendingNameMentions(): void {
    this.pendingNameMentions = [];
  }

  // doSend 失败回调用发送前捕获的快照原样还原（原
  // `this.pendingNameMentions = mentionsSnapshot;`）。
  restorePendingNameMentions(snapshot: NameMention[]): void {
    this.pendingNameMentions = snapshot;
  }

  // resetComposerSession/applyMembershipStatus/toggleReplyKeyboard/
  // toggleBotMenu（打开分支）/startRecording/doSend/composerDock 内
  // onEmojiButtonTap 七+处调用点，现状全部只做 `this.mentionItems = [];`，
  // 一个字段、没有例外——clear() 原样覆盖这唯一的清空形状。
  clear(): void {
    this.mentionItems = [];
  }

  // 原 aboutToDisappear 全链路对 mentionItems/pendingNameMentions/mentionSeq
  // 没有任何清理动作（见文件头「为什么四个 dispose() 都是空实现」），本类同样
  // 不新增。
  dispose(): void {
  }
}

// ============================================================================
// CommandSuggestionState — '/' 命令面板 + 私聊机器人"菜单"
// ============================================================================

export interface CommandSuggestionHost {
  // 当前会话 id；ensureCommandsLoaded 的双守卫判据要用它核对响应没有跨会话。
  chatId: () => number;
  // 当前 MessageStore；ensureCommandsLoaded 用它取 getPeerUserId()。
  store: () => MessageStore | null;
  // 页面当前的草稿文本；commandPanelActive/applyCommandFilter 都要按它判断
  // 是否处于 '/' 触发状态。
  draft: () => string;
  // TDLib 客户端。搬之前这几个方法体里写的是模块级单例 `getTdClient()`；
  // 改经宿主取值器是本批唯一一处刻意的偏离逐字搬迁（同 B12 把
  // `getContext(this)` 改成 `host.context()` 的先例）。
  //
  // 【为什么非改不可】本簇四个 seq 守卫（丢弃陈旧响应）全部活在
  // `.then()/.catch()` 回调里。本地单测从不跑 initTdKit()，`getTdClient()`
  // 返回的是 undefined，`client.send(...)` 那一行同步抛错——异步回调**永远**
  // 进不去，这四个守卫因此一条用例都写不出来。方案 §3 早就写了"异步用注入的
  // fake"，这条缝就是补上那个约定。有了它，测试注入一个 FakeBridge 撑起来的
  // 真 TdClient，回调就走得通，守卫才钉得住。
  //
  // 页面侧实现恒为 `() => getTdClient()`，取值不缓存，与搬之前逐字等价。
  client: () => TdClient;
}

@ObservedV2
export class CommandSuggestionState {
  // ——— 显示态：SuggestionPanel 直接读这些 @Trace ———
  @Trace commandItems: CommandItem[] = [];
  @Trace commandLoadState: string = 'idle'; // idle | loading | ready | error
  @Trace commandLoadError: string = '';
  @Trace commandMenuOpen: boolean = false;
  // Bot "菜单" pill (private bot chats with registered commands).
  @Trace botMenuAvailable: boolean = false;

  // ——— 内部机件：一律不加 @Trace ———
  private allCommands: CommandItem[] = [];
  private commandLoadSeq: number = 0;

  private host: CommandSuggestionHost = {
    chatId: (): number => 0,
    store: (): MessageStore | null => null,
    draft: (): string => '',
    // 未 bind 时的默认桩：直接回落到模块级单例，也就是搬迁前的原行为。
    // bind() 在 aboutToAppear 里、早于任何输入，正常路径上不会走到这里。
    client: (): TdClient => getTdClient()
  };

  bind(host: CommandSuggestionHost): void {
    this.host = host;
  }

  refreshCommands(): void {
    this.ensureCommandsLoaded();
    this.applyCommandFilter();
  }

  ensureCommandsLoaded(force: boolean = false): void {
    if (!force && (this.commandLoadState === 'loading' || this.commandLoadState === 'ready')) {
      return;
    }
    const seq: number = ++this.commandLoadSeq;
    const chatId: number = this.host.chatId();
    const store: MessageStore | null = this.host.store();
    const peer: number = store !== null ? store.getPeerUserId() : 0;
    this.commandLoadState = 'loading';
    this.commandLoadError = '';
    loadBotCommands(this.host.client(), chatId, peer).then((items: CommandItem[]) => {
      if (seq !== this.commandLoadSeq || chatId !== this.host.chatId()) {
        return;
      }
      this.allCommands = items;
      this.commandLoadState = 'ready';
      this.commandLoadError = '';
      // Telegram's persistent 菜单 pill belongs to a private bot chat. Group
      // commands remain available through '/' and include @bot usernames.
      this.botMenuAvailable = peer > 0 && items.length > 0;
      this.applyCommandFilter();
    }).catch((e: TdError) => {
      if (seq !== this.commandLoadSeq || chatId !== this.host.chatId()) {
        return;
      }
      logE(`ChatPage.loadBotCommands failed: ${e.message}`);
      this.allCommands = [];
      this.commandItems = [];
      this.commandLoadState = 'error';
      this.commandLoadError = str('cp_commands_failed');
      this.botMenuAvailable = false;
    });
  }

  commandPanelActive(): boolean {
    return this.commandMenuOpen ||
      this.host.draft().match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/) !== null;
  }

  // Filter against the CURRENT draft, so a slow catalog load can't show stale results.
  applyCommandFilter(): void {
    if (this.commandMenuOpen) {
      this.commandItems = this.commandLoadState === 'ready' ? this.allCommands.slice(0, 20) : [];
      return;
    }
    const m = this.host.draft().match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/);
    if (m === null) {
      this.commandItems = [];
      return;
    }
    if (this.commandLoadState !== 'ready') {
      this.commandItems = [];
      return;
    }
    const q = m[1].toLowerCase();
    const botQuery = (m[2] ?? '').toLowerCase();
    this.commandItems = this.allCommands.filter((c: CommandItem): boolean =>
      c.command.toLowerCase().startsWith(q) &&
      (botQuery === '' || c.botUsername.toLowerCase().startsWith(botQuery))).slice(0, 20);
  }

  // build() 里 `catalogSize: this.allCommands.length`（8069）的只读取值器。
  // allCommands 私有、非 @Trace——它总是与 commandLoadState/commandItems 同批
  // 赋值，build() 因那些 @Trace 触发重跑时顺带取到新值，这里不必单独响应式。
  catalogSize(): number {
    return this.allCommands.length;
  }

  // resetComposerSession 唯一一处把这簇 7 个字段全部复位的调用点：清面板、清
  // 已加载的命令目录、作废在途的 loadBotCommands 响应、连带清掉私聊"菜单"
  // pill。**不要**在 applyMembershipStatus/toggleReplyKeyboard/startRecording/
  // toggleBotMenu/sendPendingMedia/doSend/onEditorFocus/onEmojiButtonTap 那些
  // 只想"关掉当前面板"的调用点直接套用这个全量 clear()——那些点现状只清
  // commandItems/commandMenuOpen 之一或二者，从不动 allCommands/
  // commandLoadState/commandLoadError/botMenuAvailable；用 clear() 顶替会让
  // 用户被移出群/开始录音这类操作意外清空已经加载好的命令目录，是本文件
  // 明确要避免引入的行为变更。窄一点的需求请用下面 closePanel()/closeMenu()/
  // clearItems()。
  clear(): void {
    this.commandItems = [];
    this.allCommands = [];
    this.commandLoadSeq++;
    this.commandLoadState = 'idle';
    this.commandLoadError = '';
    this.commandMenuOpen = false;
    this.botMenuAvailable = false;
  }

  // applyMembershipStatus/toggleReplyKeyboard/startRecording/toggleBotMenu
  // （关闭分支）/pickCommand/composerDock 内 onEmojiButtonTap 六处调用点的现状
  // 形状：只把 commandMenuOpen 和 commandItems 一起清空，不碰已加载的命令目录。
  //
  // 【两行的先后取多数派】六个调用点里五个是 `commandItems = []` 在前、
  // `commandMenuOpen = false` 在后，只有 toggleBotMenu 那一处是反的。这里按
  // 五个的顺序写；两行都是纯赋值、中间不读任何东西，对 toggleBotMenu 那一处
  // 而言顺序归一不改变可观察行为，但这确实是一次顺序归一，记在这里。
  closePanel(): void {
    this.commandItems = [];
    this.commandMenuOpen = false;
  }

  // sendPendingMedia/composerDock 内 onEditorFocus/doSend 里那一处独立的
  // `this.commandMenuOpen = false;`——三处现状都只动这一个字段。
  closeMenu(): void {
    this.commandMenuOpen = false;
  }

  // doSend 里与 commandMenuOpen 那一行不相邻的另一处
  // `this.commandItems = [];`（紧挨着 mentionItems 清空那两行），以及
  // updateSuggestions 里 command 正则未命中分支的 `this.commandItems = [];`。
  clearItems(): void {
    this.commandItems = [];
  }

  // 原 aboutToDisappear 全链路对这簇字段没有任何清理动作（含 commandLoadSeq
  // 这个在途请求守卫——页面销毁时不会主动作废一次还没回来的 loadBotCommands），
  // 见文件头「为什么四个 dispose() 都是空实现」。
  dispose(): void {
  }
}

// ============================================================================
// InlineQueryState — "@bot query" 内联结果
// ============================================================================

export interface InlineQueryHost {
  // 当前会话 id；getInlineResults(botId, chatId, query) 要用它。
  chatId: () => number;
  // TDLib 客户端。搬之前这几个方法体里写的是模块级单例 `getTdClient()`；
  // 改经宿主取值器是本批唯一一处刻意的偏离逐字搬迁（同 B12 把
  // `getContext(this)` 改成 `host.context()` 的先例）。
  //
  // 【为什么非改不可】本簇四个 seq 守卫（丢弃陈旧响应）全部活在
  // `.then()/.catch()` 回调里。本地单测从不跑 initTdKit()，`getTdClient()`
  // 返回的是 undefined，`client.send(...)` 那一行同步抛错——异步回调**永远**
  // 进不去，这四个守卫因此一条用例都写不出来。方案 §3 早就写了"异步用注入的
  // fake"，这条缝就是补上那个约定。有了它，测试注入一个 FakeBridge 撑起来的
  // 真 TdClient，回调就走得通，守卫才钉得住。
  //
  // 页面侧实现恒为 `() => getTdClient()`，取值不缓存，与搬之前逐字等价。
  client: () => TdClient;
}

@ObservedV2
export class InlineQueryState {
  // ——— 显示态：InlineResultsBar 直接读这个 @Trace ———
  @Trace inlineResults: InlineResultRow[] = [];  // @bot query results

  // ——— 内部机件：一律不加 @Trace ———
  private inlineQueryId: string = '';
  // 同时守卫两条异步链——查询防抖到点后的 searchPublicChat/getInlineResults，
  // 与命中结果后逐条触发的缩略图 downloadFile。**不可拆成两个 seq**，理由见
  // 文件头「inlineSeq 是一个字段，不是两个」。
  private inlineSeq: number = 0;
  private inlineTimer: number = -1;

  private host: InlineQueryHost = {
    chatId: (): number => 0,
    // 未 bind 时的默认桩：直接回落到模块级单例，也就是搬迁前的原行为。
    // bind() 在 aboutToAppear 里、早于任何输入，正常路径上不会走到这里。
    client: (): TdClient => getTdClient()
  };

  bind(host: InlineQueryHost): void {
    this.host = host;
  }

  // "@bot query" in the composer runs an inline query and shows the bot's
  // results above the input bar (tap one to send it).
  refreshInlineQuery(v: string): void {
    const match = v.match(/^@([A-Za-z0-9_]{3,32})\s+(.*)$/);
    if (match === null) {
      if (this.inlineResults.length > 0) {
        this.inlineResults = [];
        this.inlineQueryId = '';
      }
      return;
    }
    const username = match[1];
    const query = match[2];
    const seq = ++this.inlineSeq;
    if (this.inlineTimer !== -1) { clearTimeout(this.inlineTimer); }
    this.inlineTimer = setTimeout((): void => {
      this.inlineTimer = -1;
      const req: TdRequest = { '@type': 'searchPublicChat' };
      req['username'] = username;
      this.host.client().send(req, 10000).then((chat: TdObject): Promise<InlineQueryPage> => {
        const type = chat['type'] as TdObject | undefined;
        const botId = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
        if (botId === 0) { return Promise.reject(new TdError(404, 'not a bot')); }
        return getInlineResults(botId, this.host.chatId(), query);
      }).then((page: InlineQueryPage): void => {
        if (seq !== this.inlineSeq) { return; }
        this.inlineQueryId = page.queryId;
        this.inlineResults = page.rows.slice(0, 24);
        for (const row of this.inlineResults) { this.downloadInlineThumb(row, seq); }
      }).catch((): void => {
        if (seq !== this.inlineSeq) { return; }
        this.inlineResults = [];
        this.inlineQueryId = '';
      });
    }, 320);
  }

  downloadInlineThumb(row: InlineResultRow, seq: number): void {
    if (row.thumbFileId === 0) { return; }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = row.thumbFileId;
    req['priority'] = 2;
    req['synchronous'] = true;
    this.host.client().send(req, 15000).then((file: TdObject): void => {
      if (seq !== this.inlineSeq) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      this.inlineResults = this.inlineResults.map(
        (it: InlineResultRow): InlineResultRow => it.resultId === row.resultId
          ? {
            resultId: it.resultId, title: it.title, description: it.description,
            thumbFileId: it.thumbFileId, thumbPath: path, kind: it.kind
          } : it);
    }).catch((): void => {});
  }

  // pickInlineResult（留页面，涉及 sendInlineResult 与 composer.clearReply）
  // 判断"当前是否有一个内联查询结果集在展示"要读这个私有字段：原
  // `if (this.inlineQueryId === '') { return; }`。
  queryId(): string {
    return this.inlineQueryId;
  }

  // pickInlineResult 发送成功回调里原样两行 `this.inlineResults = [];
  // this.inlineQueryId = '';`——现状全仓**没有**其余外部调用点会清这两个字段
  // （resetComposerSession 等 7 个"clear 调用点"从未碰过 inline 簇，见 B14
  // 侦察报告 2/3）。refreshInlineQuery 内部两处早退分支（未命中 `@bot query`
  // 格式、以及请求失败）做的是同样的两行赋值，但那是同一方法内部的逐字搬迁，
  // 不改写成调用本方法，以免被误读成"顺手重构"。
  clear(): void {
    this.inlineResults = [];
    this.inlineQueryId = '';
  }

  // 原 aboutToDisappear 全链路对 inlineResults/inlineQueryId/inlineSeq/
  // inlineTimer 没有任何清理动作——包括那个眼看着像该清的 320ms 防抖定时器，
  // 见文件头「为什么四个 dispose() 都是空实现」。
  dispose(): void {
  }
}

// ============================================================================
// StickerSuggestionState — 纯 emoji 草稿的贴纸建议
// ============================================================================

// 本簇搬进控制器的两个方法（refreshStickerSuggestions/downloadSuggestionThumb）
// 都不读页面任何字段——getStickersForEmoji 只吃草稿文本本身，不需要 chatId/
// store。sendSuggestedSticker 才用得到 store，但它调用 store.sendSticker，
// 按方案点名留在页面，不进本类。Host 接口因此暂时没有任何取值器，仍然按其余
// 三个类同样的 bind()/host 字段结构声明，保持四个类形状一致、便于未来若真的
// 需要什么再加。
export interface StickerSuggestionHost {
  // TDLib 客户端。搬之前这几个方法体里写的是模块级单例 `getTdClient()`；
  // 改经宿主取值器是本批唯一一处刻意的偏离逐字搬迁（同 B12 把
  // `getContext(this)` 改成 `host.context()` 的先例）。
  //
  // 【为什么非改不可】本簇四个 seq 守卫（丢弃陈旧响应）全部活在
  // `.then()/.catch()` 回调里。本地单测从不跑 initTdKit()，`getTdClient()`
  // 返回的是 undefined，`client.send(...)` 那一行同步抛错——异步回调**永远**
  // 进不去，这四个守卫因此一条用例都写不出来。方案 §3 早就写了"异步用注入的
  // fake"，这条缝就是补上那个约定。有了它，测试注入一个 FakeBridge 撑起来的
  // 真 TdClient，回调就走得通，守卫才钉得住。
  //
  // 页面侧实现恒为 `() => getTdClient()`，取值不缓存，与搬之前逐字等价。
  client: () => TdClient;
}

@ObservedV2
export class StickerSuggestionState {
  // ——— 显示态：StickerSuggestionBar 直接读这个 @Trace ———
  @Trace stickerSuggestions: StickerSuggestion[] = []; // emoji-typed sticker hints

  // ——— 内部机件：一律不加 @Trace ———
  private stickerSuggestSeq: number = 0;

  private host: StickerSuggestionHost = {
    // 未 bind 时的默认桩：直接回落到模块级单例，也就是搬迁前的原行为。
    // bind() 在 aboutToAppear 里、早于任何输入，正常路径上不会走到这里。
    client: (): TdClient => getTdClient()
  };

  bind(host: StickerSuggestionHost): void {
    this.host = host;
  }

  // Typing a bare emoji offers matching stickers above the composer, as the
  // official clients do.
  refreshStickerSuggestions(v: string): void {
    const text = v.trim();
    // Only a short pure-emoji draft qualifies (no letters/digits/spaces).
    const isEmojiOnly = text.length > 0 && text.length <= 8 &&
      !/[A-Za-z0-9\s]/.test(text);
    if (!isEmojiOnly) {
      if (this.stickerSuggestions.length > 0) { this.stickerSuggestions = []; }
      return;
    }
    const seq = ++this.stickerSuggestSeq;
    getStickersForEmoji(text).then((raw: TdObject[]): void => {
      if (seq !== this.stickerSuggestSeq) { return; }
      const items: StickerSuggestion[] = [];
      for (const st of raw.slice(0, 12)) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        const thumb = st['thumbnail'] as TdObject | undefined;
        const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
        const thumbId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) { continue; }
        items.push({ fileId, thumbId, thumbPath: '' });
      }
      this.stickerSuggestions = items;
      for (const item of items) { this.downloadSuggestionThumb(item, seq); }
    }).catch((): void => {});
  }

  downloadSuggestionThumb(item: StickerSuggestion, seq: number): void {
    if (item.thumbId === 0) { return; }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = item.thumbId;
    req['priority'] = 2;
    req['synchronous'] = true;
    this.host.client().send(req, 15000).then((file: TdObject): void => {
      if (seq !== this.stickerSuggestSeq) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      this.stickerSuggestions = this.stickerSuggestions.map(
        (row: StickerSuggestion): StickerSuggestion => row.fileId === item.fileId
          ? { fileId: row.fileId, thumbId: row.thumbId, thumbPath: path } : row);
    }).catch((): void => {});
  }

  // 现状全仓没有外部调用点会单独清 stickerSuggestions（resetComposerSession
  // 等 7 个"clear 调用点"从未碰过 sticker 簇）。保留这个方法是为了与另外三个
  // 类的结构一致，并原样覆盖 refreshStickerSuggestions 内部"非纯 emoji 早退"
  // 分支的语义（该分支仍按逐字搬迁保留字面赋值，不改写成调用本方法）。
  clear(): void {
    this.stickerSuggestions = [];
  }

  // sendSuggestedSticker（留页面，调用 this.store?.sendSticker(...)）发送后
  // 原样两行：`this.stickerSuggestions = []; this.stickerSuggestSeq++;`——
  // 清空展示的建议，并让任何仍在途的旧缩略图下载在回调里 seq 比对失败从而
  // 失效（这次自增不是为了开一轮新查询，是主动作废，注释保留这层意图）。
  // stickerSuggestSeq 私有，页面拿不到，因此打包成这一个方法供 sendSuggestedSticker
  // 调用。
  clearAfterSend(): void {
    this.stickerSuggestions = [];
    this.stickerSuggestSeq++;
  }

  // 原 aboutToDisappear 全链路对 stickerSuggestions/stickerSuggestSeq 没有
  // 任何清理动作，见文件头「为什么四个 dispose() 都是空实现」。
  dispose(): void {
  }
}
