// 输入框上方那一条在做什么（普通输入 / 回复某条 / 编辑某条）的状态机。
// 从 ChatPage 整体搬出（B9 批）。
//
// 【为什么要搬】
// 这三种状态共用输入框上方那一条，而它们此前是**两组互相独立的字段**
// （replyToId/Name/Text/Thumb/ThumbSticker 与 editingId/Kind/Preview），谁都能
// 单独改。util/composerMode.ets 开篇写明了真实发生过的那个 bug：进入编辑态
// 时没人清掉待回复，编辑条把回复条盖住，回复却仍然生效——用户看不见也取消
// 不掉，发出去时 replyToId 还在。做成状态机之后，"进编辑就没有待回复"不再是
// 某个函数里的一行，而是转换函数的后置条件，能被单测钉住；`apply()` 是这
// 9 个字段的**唯一写入口**，源码原文写过"不要再单独改那七个字段"——搬迁后
// 全仓 grep `mode =`/`replyToId =` 之类，只允许在本类的 `apply()` 内出现一次。
//
// 【为什么 draft/composerSending/composerFocused/composerEditorReady/
// pendingMedia/bottomSlot 都不搬】
// draft 有 42 处引用、每键入一次写、ChatComposerInput 的 `editorHeight()` 在
// 它自己的 build 里量它（第二轮第 9 项之前这一句量在 ChatPage.build 里）；
// composerSending 是 4 条发送路径共享的一把锁（withSendLock），单独复制一份
// 会打破"同一时刻只有一次在途发送"这条不变量；pendingMedia/bottomSlot 分别是
// 相册暂存与底部面板互斥槽两个不相关的域，各自已有自己的唯一写入口。这些字段
// 留在页面，本类只经 host 的取值器/setter 读写它们当下的真值，不缓存、不复制。
//
// 【commitEdit 为什么整个不搬】
// commitEdit 依赖 withSendLock/store（页面留存的发送闸门与 TDLib 客户端），
// 按所有权裁决整个留页面；它只经本类的 editingId/editingKind 两个 @Trace
// 直读，成功回调里改调 `this.composer.apply(cancelEditMode(this.composer.mode))`
// 走回本类唯一写入口。
//
// 【与 util/composerMode 同名函数冲突】
// util/composerMode.ets 导出的 `clearReply()`/`cancelEdit()` 是纯函数（旧状态
// → 新状态），本类的同名方法是"摊到字段上"的那一步——两者角色不同、名字却
// 一样，import 时用别名 `clearReply as clearReplyMode`/`cancelEdit as
// cancelEditMode`，类内一律只调别名，不与本类方法混淆。
//
// 【headerTitle 为什么是 host 回调而不是直接读 header 字段】
// startReply 找不到发送者名字时，退回顶栏当前标题——原代码是
// `this.header.title`。header 是 HeaderIdentitySession（B8）的实例，控制器之间
// 不允许互相持有引用，只能各自经宿主（ChatPage）中转；host.headerTitle() 由
// 页面实现为 `(): string => this.header.title`。
//
// 【为什么 startReply 末尾的 setTimeout 现在有句柄】（B9 有意加固）
// 原来是裸 `setTimeout(() => { focusControl.requestFocus('chat_composer'); }, 0)`，
// 没有句柄可清：若页面在这 0ms 延迟内已经 dispose（理论窗口很窄，但存在），
// 回调仍会对一个已经不该再关心焦点的输入框发一次 requestFocus。搬进控制器后
// 给它一个 focusTimer 句柄，dispose() 里 clear 掉——与 B6 SearchSession 给
// entryTimer 开句柄是同一类加固，属于**行为变更**，不是纯搬迁。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，各自的回复/编辑态互不相干。
// 做成单例会让一个会话的编辑草稿冒到另一个会话的输入框里。页面用字段初始化器
// new 一个：首帧前就已存在、引用全生命周期稳定、类型非空。
//
// 【为什么没有 …Seq】
// 本簇没有异步在途请求需要序号守卫——回复/编辑都是同步的用户操作或同步的
// TDLib 编辑请求由页面的 commitEdit（留页面）自己管。dispose() 仍然提供，
// 只清 focusTimer 这一个句柄，是为了和其余控制器统一的 bind/dispose 生命周期。
//
// 【不在本类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。本簇的所有联动都
// 用显式方法调用表达。

import { promptAction } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import { PendingMediaItem, hasPendingMedia } from '../../util/pendingMedia';
import { replySnippetOf } from '../../util/replySnippet';
import { replyThumbIsSticker, replyThumbOf } from '../../util/replyThumb';
import { str } from '../../util/strings';
import {
  ComposerMode, cancelEdit as cancelEditMode, clearReply as clearReplyMode,
  draftToRestore, enterEdit, enterReply, idleComposer
} from '../../util/composerMode';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，动作回调把副作用交回页面执行。仿 LiveTopCardController 的
// LiveTopCardHost / SearchSession 的 SearchSessionHost。
//
// 两条纪律（与其余控制器一致）：
// 1. 这里只放**取值器**，不放页面的 @Local 引用。控制器不缓存页面的值，每次
//    要用就现取——否则页面改了字段、控制器手里还是旧的。
// 2. draft/composerSending/pendingMedia/bottomSlot 等留页面的字段，本类只经
//    这里的取值器/setter 读写，不在本类里存一份影子拷贝。
export interface ComposerSessionHost {
  // 顶栏当前标题（HeaderIdentitySession 的 title）——startReply 在消息没有
  // senderName 时的回退文案。控制器之间不互相持有引用，只经宿主中转。
  headerTitle: () => string;
  // 当前 MessageStore；路由切换途中可能为 null。startEdit 用它按 id 找到要
  // 编辑的那条消息（原实现读 `this.store?.getMessages()`，不是 findMsg 那份
  // `this.messages`——两份列表来源不同，不能互相替代）。
  store: () => MessageStore | null;
  // 按 id 在页面当前消息列表（`this.messages`）里查一条，找不到返回 null。
  // startReply 用它取被回复消息的摘要/缩略图。
  findMsg: (messageId: number) => MessageEntry | null;
  // 暂存待发送的媒体（相册域，与本簇无关）。startEdit 用它挡住"有待发媒体时
  // 进编辑"——编辑改的是旧消息，发媒体是发新消息，发送键做哪件事说不清，
  // 宁可拒绝也不静默丢掉用户刚选好的图。
  pendingMedia: () => PendingMediaItem[];
  // 输入框当下的草稿文本（页面 @Local，42 处引用，留页面）。startEdit 进入
  // 编辑时把它当"当前草稿"传给 enterEdit（换算成 draftBeforeEdit 存进本类），
  // 随后覆盖成被编辑消息的原文；cancelEdit 把 draftBeforeEdit 还回来时也经
  // 这个 setter 写回页面。
  draft: () => string;
  setDraft: (value: string) => void;
  // startReply 里原来直接调用的 this.closeReactionSheet()——反应面板域本轮
  // 不动（B11 才搬），仍由页面处理。
  closeReactionSheet: () => void;
  // startReply 里原来直接调用的 this.setEmojiPanel(false)——表情/贴纸抽屉域
  // 与本簇无关，仍由页面处理。
  setEmojiPanel: (show: boolean) => void;
  // startReply 里原来直接调用的
  // `this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB))`——
  // bottomSlot 是底部面板互斥槽，applyBottomSlot 是它唯一写入口，本轮不动，
  // 仍由页面处理这一次收起。
  closeReplyKeyboardSlot: () => void;
}

@ObservedV2
export class ComposerSession {
  // ——— 显示态：ChatComposerInput 直接读这些 @Trace ———

  @Trace mode: ComposerMode = idleComposer();
  @Trace replyToId: number = 0;      // message being replied to (0 = none)
  @Trace replyToName: string = '';
  @Trace replyToText: string = '';
  @Trace replyToThumb: string = '';
  @Trace replyToThumbSticker: boolean = false;
  @Trace editingId: number = 0;      // message being edited (0 = none)
  @Trace editingPreview: string = '';
  // 'text' | 'caption'。**注意**：这个初值与 idleComposer().editingKind（''）
  // 不一致，只在本类构造之后、第一次 apply() 调用之前的这一小段窗口里存在
  // 差异——原页面字段的初值就是 'text'（ChatPage 旧 @Local 声明原文），这里
  // 原样保留，不趁搬迁顺手"统一"成 ''，避免引入未经验证的行为变化。目前没有
  // 任何读者会在首次 apply() 之前读它，窗口无害，但值得留一条单测钉住。
  @Trace editingKind: string = 'text';

  // ——— 内部机件：一律**不加 @Trace** ———
  // 进入编辑前的草稿只在 apply() 里整体写入，不驱动任何 UI；定时器句柄同理。

  // 进入编辑前的草稿，取消编辑时要还回去。只由 apply() 写。
  private draftBeforeEdit: string = '';
  // startReply 末尾"请求输入框焦点"那次 setTimeout(0) 的句柄（B9 加固，见
  // 文件头说明）；-1 = 没有在途的那一次。
  private focusTimer: number = -1;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的值。
  private host: ComposerSessionHost = {
    headerTitle: (): string => '',
    store: (): MessageStore | null => null,
    findMsg: (_messageId: number): MessageEntry | null => null,
    pendingMedia: (): PendingMediaItem[] => [],
    draft: (): string => '',
    setDraft: (_value: string): void => {},
    closeReactionSheet: (): void => {},
    setEmojiPanel: (_show: boolean): void => {},
    closeReplyKeyboardSlot: (): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: ComposerSessionHost): void {
    this.host = host;
  }

  // ——— 唯一写入口 ———

  // 输入框上方那一条的状态机在 util/composerMode（有单测）。所有写入都经过
  // 这里：转换函数算出新状态，这里摊到字段上。**不要再单独改那七个字段**——
  // 回复和编辑共用同一条，分开改必然出现"编辑条盖住回复条、回复却仍生效"
  // 那类互相不知道的状态。
  // 【B9 更正】原注释数的"七个字段"是历史遗留数字：本方法实际摊开的是
  // replyToId/replyToName/replyToText/replyToThumb/replyToThumbSticker/
  // editingId/editingKind/editingPreview/draftBeforeEdit 共 9 个（另加 mode
  // 本身）。原文照抄未改数字，这里指出但不擅自"纠正成 9"去改写历史注释的
  // 用词——保留"七"是尊重原文，此处旁注真实字段数。
  apply(next: ComposerMode): void {
    this.mode = next;
    this.replyToId = next.replyToId;
    this.replyToName = next.replyName;
    this.replyToText = next.replyText;
    this.replyToThumb = next.replyThumb;
    this.replyToThumbSticker = next.replyThumbSticker;
    this.editingId = next.editingId;
    this.editingKind = next.editingKind;
    this.editingPreview = next.editingPreview;
    this.draftBeforeEdit = next.draftBeforeEdit;
  }

  clearReply(): void {
    this.apply(clearReplyMode(this.mode));
  }

  replySnippet(m: MessageEntry): string {
    return replySnippetOf({
      text: m.text, placeholderLabel: m.placeholderLabel,
      contentType: m.contentType, paidMediaLocked: m.paidMediaLocked
    });
  }

  // Long-press menu: reply. Populates the reply preview above the input bar;
  // doSend() then attaches reply_to.
  startReply(messageId: number): void {
    const m = this.host.findMsg(messageId);
    if (m === null) {
      return;
    }
    ContextMenu.close();
    this.host.closeReactionSheet();
    this.apply(enterReply(this.mode, messageId,
      m.senderName !== '' ? m.senderName : this.host.headerTitle(), this.replySnippet(m),
      replyThumbOf({
        contentType: m.contentType, photoPath: m.photoPath,
        paidMediaLocked: m.paidMediaLocked
      }),
      replyThumbIsSticker(m.contentType)));
    this.host.setEmojiPanel(false);
    this.host.closeReplyKeyboardSlot();
    if (this.focusTimer !== -1) {
      clearTimeout(this.focusTimer);
    }
    this.focusTimer = setTimeout((): void => {
      this.focusTimer = -1;
      focusControl.requestFocus('chat_composer');
    }, 0);
  }

  startEdit(messageId: number): void {
    // 编辑改的是旧消息，发媒体是发新消息，发送键做哪件事说不清。宁可拒绝，
    // 也不静默丢掉用户刚挑好的九张图（对照 enterEdit 会清掉待回复——那里
    // 丢的只是一个引用）。
    if (hasPendingMedia(this.host.pendingMedia())) {
      promptAction.showToast({
        message: $r('app.string.cp_pending_media_blocks_edit'), duration: 2000
      });
      return;
    }
    const store = this.host.store();
    const msg = store?.getMessages().find(
      (m: MessageEntry): boolean => m.id === messageId);
    const captionTypes: string[] = ['photo', 'video', 'file', 'audio', 'voice'];
    if (msg === undefined || !msg.isOutgoing ||
      (msg.contentType !== 'text' && captionTypes.indexOf(msg.contentType) < 0)) {
      return;
    }
    const editKind: string = msg.contentType === 'text' ? 'text' : 'caption';
    const preview: string = msg.text !== '' ? msg.text
      : (editKind === 'caption' ? str('cp_no_caption') : '');
    this.apply(enterEdit(this.mode, messageId, editKind, preview, this.host.draft()));
    this.host.setDraft(msg.text);
  }

  cancelEdit(): void {
    if (this.editingId === 0) {
      return;
    }
    const restored: string = draftToRestore(this.mode);
    this.apply(cancelEditMode(this.mode));
    this.host.setDraft(restored);
  }

  // resetComposerSession 里 composerMode 七字段 + draftBeforeEdit 那半的搬迁
  // 落点（B9）。整体清成 idle，而不是只 clearReply()——clearReply 按设计只
  // 处理回复态，编辑态下是空操作，换会话时编辑态会跨会话残留、editingId 还
  // 指着上一个会话的消息，下一次提交就编辑到别的会话去了。resetComposerSession
  // 其余约 25 行（草稿/暂存媒体/发送锁/录音/表情面板/@提及与命令面板/回复
  // 键盘等页面自有的输入区状态）与本簇无关，仍留在页面自己清。
  reset(): void {
    this.apply(idleComposer());
  }

  // persistDraftAndViewport（aboutToDisappear 路径）用：编辑进行中真正的草稿
  // 是编辑前暂存的那份，不是输入框此刻显示的文本——页面把自己的 `this.draft`
  // 当 current 传进来，这里只做二选一判定，不持有 draft 本身。
  draftToPersist(current: string): string {
    return this.editingId !== 0 ? this.draftBeforeEdit : current;
  }

  // prepareMessageBubble 的 cacheKey 读（行渲染热路径，不变量 1）：
  // `this.editingId !== 0` 原样搬来，只改个名字方便调用点读成一句判断而不是
  // 裸比较。
  isEditing(): boolean {
    return this.editingId !== 0;
  }

  // ChatPage.aboutToDisappear 调用。本簇没有异步在途请求要守（commitEdit 的
  // TDLib 请求留在页面，由页面自己的生命周期管），只清 startReply 那一次
  // setTimeout 的句柄——顺序上无所谓先后，这里保持与其余控制器一致的形状。
  dispose(): void {
    if (this.focusTimer !== -1) {
      clearTimeout(this.focusTimer);
      this.focusTimer = -1;
    }
  }
}
