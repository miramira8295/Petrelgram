// 成员资格状态机：refresh()（原 refreshMembership@4629-4696）+ applyStatus()
// （原 applyMembershipStatus@4698-4727）+ bind/dispose。从 ChatPage 整体搬出
// （第二轮 R2-A 批）。这是方案 §6 表格里"明确推迟到第二轮"的那一行——当初
// 推迟的理由是 applyMembershipStatus 直接改写 composer/emoji/命令面板/录音
// 四域字段，要等 B9/B12/B14/B15 把那四个域都收成控制器之后才谈得上设计回调
// 接口；现在它们分别是 this.composer/this.mention/this.command/
// this.recording 四个页面控制器，回调接口这才设计得出来。
//
// 【为什么这里不是 @ObservedV2】
// 本类的三个字段（membershipSupergroupId/membershipBasicGroupId/
// membershipSeq）没有一个是 `@Local`，也没有任何 build()/@Builder 直接读
// 它们——三者纯粹是"当前在跟踪哪个群组对象"+"三层异步的取消令牌"这两组内部
// 记账，从不参与渲染。真正驱动 UI 的 `membershipState` 按下面【甲】的裁决
// 留在页面，不进本类。与 AttachActions（B12）/MediaSaveState（B15）同一个
// 判断：本类是**普通类**，不写 @ObservedV2，字段不加 @Trace，类里不声明
// @Monitor。
//
// 【甲：membershipState 为什么留在页面，不搬进本类】
// 方案 §6 原表格那句"membershipState...被 cacheKey/成员资格状态机/翻译
// 总开关/ScrollFab 未读徽标等身份簇之外的多个域共同读写"，逐行核对
// ChatPage.prepareMessageBubble 的 cacheKey 拼接（原 1234-1246 行）后需要
// 更正一处：cacheKey 字符串本身只拼了 `isGroup`/`isChannel`
// （`|g${this.isGroup?1:0}${this.isChannel?1:0}`），并不直接拼
// membershipState。真正的裁决依据是 B8 定的所有权归属——membershipState
// 与 isGroup/isChannel/isBotChat/isTranslatable/unreadBadge 同属一簇"身份/
// 会话类型"状态，簇内多个域（含 B8 的 HeaderIdentitySession 经
// onChatKindResolved 回调）共同读写，且它有 5 处直接落在 build()/@Builder
// 里（bottomDrawer 的表情面板显示条件、ChatTimelineHost 入参、
// SuggestionPanel/InlineResultsBar/StickerSuggestionBar 三处显示条件），
// 按 B8 的所有权裁决，这一类字段留在页面，不随本批搬迁。本类只经
// `host.setMembershipState(next)` 这一个 setter 写它，从不读它、不缓存它。
//
// 【乙：membershipSeq 是三层异步的取消令牌，方向不能反，一处都不能少】
// `refresh()` 入口自增一次并捕获快照 `seq`；随后有且仅有 6 处比较，全部
// "seq 与 this.membershipSeq 当前值相等则继续，不等则放弃"（唯一一处写成
// `!==` 提前 return 的是最外层 `getChat().then` 开头，逻辑等价，方向没有
// 反）：
//   1. 最外层 getChat().then 开头（早退）
//   2. chatTypeSupergroup 分支：getSupergroup().then
//   3. chatTypeSupergroup 分支：getSupergroup().catch
//   4. chatTypeBasicGroup 分支：getBasicGroup().then
//   5. chatTypeBasicGroup 分支：getBasicGroup().catch
//   6. 最外层 getChat().catch
// 三层各自独立比较、各自早退，不存在"内层信任外层已经比过就不比"的情况——
// 即使外层 `.then` 通过了第 1 处比较，等待 getSupergroup/getBasicGroup 的
// 异步期间 seq 仍可能再变，内层必须重新比一次。换会话时 `refresh()` 会
// 再次被调用（`this.membershipSeq` 再自增一次），旧响应无论卡在哪一层，
// 回来时都会被对应那一层的比较挡住，不会把旧会话的成员资格结果写进新会话
// 的 `membershipState`。
// 页面销毁时的兜底自增（原 disposeSubscriptionsInOrder@3718 行，紧邻退订
// 'membershipSupergroup'/'membershipBasicGroup' 两个推送监听器之前）不属于
// `refresh()` 内部这三层，见下方 dispose() 一节。
//
// 【密聊特例：typeName !== 'chatTypeSecret' 那道判据】
// `refresh()` 走到"既非 supergroup 也非 basicGroup"的兜底分支时，密聊
// （chatTypeSecret）会顺路落到这里，但密聊的输入区形态由 applySecretChat
// （另一条独立通道，不属于本簇）决定，本方法在这里无条件写 'writable'
// 就会把 applySecretChat 刚设好的"待建立/已关闭故不可发"状态冲掉。因此这
// 里保留原判据把密聊摘出去。外层 `.catch`（getChat 请求本身失败）没有这道
// 判断——那时连 type 都没拿到，无法区分是不是密聊，原样保留无条件写
// 'writable'（受第 6 处比较保护），这是两条独立的道理，原注释照抄，不合并。
//
// 【client() 注入缝：本批一开始就走宿主取值器，不等验收再补】
// `refresh()` 里两层 `getTdClient().send(...)` 全部改成
// `this.host.client().send(...)`——**这是对逐字搬迁的一处刻意偏离**，与
// B14/15（ComposerSuggestionState 等）后来补的那道缝、以及 B12 把
// `getContext(this)` 改成 `host.context()` 是同一个先例：本簇三层 seq
// 守卫全部活在 `.then()/.catch()` 回调里，本地单测从不跑 initTdKit()，
// `getTdClient()` 返回 undefined，`client.send(...)` 同步抛错，异步回调
// 永远进不去，这些守卫因此一条用例都写不出来。页面侧实现恒为
// `() => getTdClient()`，取值不缓存，与搬之前逐字等价。
//
// 【另一处刻意偏离：三条 logE 的前缀改名】
// `ChatPage.getChat/getSupergroup/getBasicGroup membership failed` 三条改成了
// `MembershipSession.…`。跟随 B8/B12/B14/B15 的先例（那几批都把 logE 前缀换成
// 了各自的类名）；但仓库里这条惯例其实是分裂的——LiveTopCardController 与
// ComposerSuggestionState 至今仍留着 `ChatPage.` 前缀。
//
// **对第二轮特别要紧的一点**：方案 §5 的 hilog 黄金样本 diff 是逐字比对标签行
// 的。日志文本每改一次，下一次录样本就多一处噪声。第二轮后面几批（锚点复位、
// 翻页闸、JumpLatest）要靠黄金样本当主要证据，**从那几批起 logE 前缀一律不动**，
// 需要统一的话另开一批集中做，不要夹在时序批次里。
// 【closeComposerSurfaces：确认连续才打包，joiningChat=false 不在其中】
// 原 applyMembershipStatus 尾部"关掉所有输入区界面"那一段（原 4719-4726
// 行）逐行核对过连续性：`this.joiningChat = false` 之后紧接
// `setEmojiPanel(false)` → `mention.clear()` → `command.closePanel()` →
// `composer.reset()` → `if (recording.isRecording) recording.cancel()`，
// 中间没有夹杂任何非本簇/非跨域收尾的语句，确认可以整段打包成一个跨域
// 回调。但 `this.joiningChat = false` 本身是成员资格簇自己的字段（是
// membershipState 的姊妹标志，不是别的簇），且它在"不关闭直接 return"
// 分支（`!membershipLosesComposer(next)` 为真）里也独立写了一次——两处
// `joiningChat = false` 不能合并成一处，因此 `setJoiningChat(false)` 单独
// 经 host 调用两次，`closeComposerSurfaces()` 只打包 setEmojiPanel 起的
// 那五行。
//
// 【supergroupId()/basicGroupId()：私有化后补的两个只读取值器，读点不丢】
// `subscribeMembershipUpdates`（原 2614-2629 行）未随本批迁移，仍留在
// ChatPage——它的 `updateSupergroup`/`updateBasicGroup` 两个推送监听器要用
// `supergroup['id'] === this.membershipSupergroupId`/
// `basicGroup['id'] === this.membershipBasicGroupId` 做匹配过滤，这是两条
// 与 `refresh()` 内部三层 Promise 链完全不同的独立通道（服务器主动推送，
// 不经过 membershipSeq 比较）。`membershipSupergroupId`/
// `membershipBasicGroupId` 私有化进本类之后，页面这两处读点如果不补取值器
// 就会丢（B5/B8 栽过的坑）——因此本类公开这两个只读方法，供接线时页面
// 原样取回，不用近似值顶替。
//
// 【dispose()：只做侦察报告证实原代码里确实有的那一行】
// ChatPage.aboutToDisappear 全链路对 membershipSeq 唯一的清理是
// disposeSubscriptionsInOrder（原 3718 行）里紧挨着退订
// 'membershipSupergroup'/'membershipBasicGroup' 两个推送监听器**之前**的
// 一行 `this.membershipSeq++`。该方法本身未随本批迁移（它还退订着好几个
// 不属于本簇的订阅），接线时页面应在原来那一行位置改调
// `this.membership.dispose()`。membershipState/membershipSupergroupId/
// membershipBasicGroupId 三者在 aboutToDisappear 全链路里原本就从未被复位
// （逐行核对过 disposeTimersAndSeqGuards 等七个子方法，没有第二处），
// dispose() 不新增对它们的清零——补上就是没有原文支持的"顺手优化"。
//
// 【本批未迁移的两处，明确留给接线批次】
// `subscribeMembershipUpdates()`（原 2614-2629 行）与 `joinCurrentChat()`
// （原 4729-4746 行）都不在本批范围——前者理由见上一节；后者是因为它除了
// 读/写 `membershipState`/`joiningChat` 之外，还调用页面自己的
// `showClientJoinNotice()`，且调用 `refreshMembership()` 只是它众多副作用
// 之一，不是"整方法体搬迁"的候选，方法本身留在页面。接线时**只**把其中的
// `this.refreshMembership()` 改调 `this.membership.refresh()`。
//
// 【给后续批次：joinCurrentChat 里的 membershipState/joiningChat 保持页面直写】
// 这两个是页面自留的 @Local（membershipState 的所有权裁决见上文）。
// `setMembershipState` 只是**本类回调页面**的入口，页面自己写自己的字段没有
// 理由绕道控制器；绕了反而推翻这一批赖以成立的所有权归属。HEAD 里就是页面
// 直写，逐字搬迁的结果也应当是页面直写。
//
// 【与其余控制器同款约定】
// per-ChatPage 字段初始化器 new，绝非模块级单例；宿主接口全是箭头函数
// 取值器/动作回调，现取不缓存（`client()` 见上方专项说明）；类中不声明
// @Monitor；未 bind 时的空宿主字段类型非空，占位值在页面 bind() 完成前
// 不会被真正用到。

import { TdClient } from '../../tdkit/TdClient';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { logE } from '../../util/log';
import { membershipLosesComposer, membershipStateOf } from '../../util/membershipState';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，动作回调把跨簇副作用交回页面执行。仿 ChatOverlayState 的
// ChatOverlayStateHost / AttachActions 的 AttachActionsHost。
export interface MembershipSessionHost {
  // 当前会话 id。refresh() 拼 getChat 请求体用它。
  chatId: () => number;
  // 页面当前的 `this.isChannel`。refresh() 的 chatTypeSupergroup 分支读它
  // 作为 `is_channel` 缺省时的回退值（原文 `?? this.isChannel`）；
  // applyStatus() 拼 membershipStateOf 的入参也读它——两处都不是本类自己
  // 存的状态，每次现取。
  isChannel: () => boolean;
  // membershipState 按方案裁决留在页面（见文件头【甲】），本类只经这一个
  // setter 写它，从不读、不缓存。
  setMembershipState: (next: string) => void;
  // refresh() 两个分支里紧跟着写的 `this.isGroup = true`。
  setIsGroup: (value: boolean) => void;
  // refresh() 里写的 `this.isChannel = ...`（chatTypeSupergroup 分支按
  // `is_channel` 字段写，chatTypeBasicGroup 分支无条件写 false）。
  setIsChannel: (value: boolean) => void;
  // refresh() 两个分支里，写 `membershipState = 'checking'` **之前**先调用
  // 的 `this.commitTimelineSnapshot()`（时间线域的方法，与本簇字段顺序固定，
  // 不可颠倒）。
  commitTimelineSnapshot: () => void;
  // applyStatus() 两个分支（早退 return 前、以及跨域收尾前）各自独立写一次
  // 的 `this.joiningChat = false`——membershipState 的姊妹标志，页面自留
  // 字段，两处调用不合并（见文件头专项说明）。
  setJoiningChat: (value: boolean) => void;
  // applyStatus() 尾部"关掉所有输入区界面"那五行（setEmojiPanel(false) →
  // mention.clear() → command.closePanel() → composer.reset() →
  // 有条件的 recording.cancel()）打包成的一个跨域回调——确认连续才打包，
  // 见文件头专项说明。页面侧实现应逐字对应这五行，顺序不变。
  closeComposerSurfaces: () => void;
  // TDLib 客户端。搬之前 refresh() 里两处写的是模块级单例 `getTdClient()`；
  // 改经宿主取值器是本批刻意偏离逐字搬迁的一处，见文件头【client() 注入缝】
  // 一节。页面侧实现恒为 `() => getTdClient()`，取值不缓存，与搬之前逐字
  // 等价。
  client: () => TdClient;
}

export class MembershipSession {
  // ——— 内部机件：普通类，字段都不加装饰器 ———

  // 当前正在跟踪哪个超级群/普通群的 id；同一时刻只有其中一个非零
  // （原 ChatPage 1578-1579 行）。
  private membershipSupergroupId: number = 0;
  private membershipBasicGroupId: number = 0;
  // 三层异步（getChat 的 .then/.catch，内层 getSupergroup/getBasicGroup 的
  // .then/.catch 各一层）的取消令牌，见文件头【乙】一节
  // （原 ChatPage 1580 行）。
  private membershipSeq: number = 0;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经
  // 被构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」
  // 的值。
  private host: MembershipSessionHost = {
    chatId: (): number => 0,
    isChannel: (): boolean => false,
    setMembershipState: (_next: string): void => {},
    setIsGroup: (_value: boolean): void => {},
    setIsChannel: (_value: boolean): void => {},
    commitTimelineSnapshot: (): void => {},
    setJoiningChat: (_value: boolean): void => {},
    closeComposerSurfaces: (): void => {},
    // 未 bind 时的默认桩：直接回落到模块级单例，也就是搬迁前的原行为。
    // bind() 在 aboutToAppear 里、早于任何调用，正常路径上不会走到这里。
    client: (): TdClient => getTdClient()
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: MembershipSessionHost): void {
    this.host = host;
  }

  // 原 refreshMembership（原 4629-4696 行）方法体逐字搬迁，getTdClient()→
  // this.host.client()、this.chatId→this.host.chatId()、
  // this.isGroup/isChannel/membershipState 的读写全部经宿主转发，逻辑分支、
  // 判据、语句顺序未改一处。
  // 群的默认权限（chat.permissions.can_send_basic_messages），由 refresh() 从
  // getChat 的应答里存一份。
  //
  // **为什么要存**：applyStatus 还有另外两个调用点在 ChatPage 的 updateSupergroup
  // 推送监听里，那里只拿得到 supergroup、拿不到 chat。不存的话，一次成员状态推送
  // 就会把锁群又翻回可写——用户重新看到那个发不出去的输入框。
  private chatCanSendBasic: boolean = true;

  refresh(): void {
    const seq: number = ++this.membershipSeq;
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.host.chatId();
    this.host.client().send(req).then((chat: TdObject): void => {
      if (seq !== this.membershipSeq) {
        return;
      }
      const type = chat['type'] as TdObject | undefined;
      const typeName = (type?.['@type'] as string | undefined) ?? '';
      // 群的**默认权限**，管的是普通成员。"只有管理员能发言"的锁群把它设成
      // false，而成员状态仍然是 chatMemberStatusMember——只看状态判不出来。
      const chatPerms = chat['permissions'] as TdObject | undefined;
      this.chatCanSendBasic =
        (chatPerms?.['can_send_basic_messages'] as boolean | undefined) ?? true;
      if (typeName === 'chatTypeSupergroup') {
        this.membershipSupergroupId = (type?.['supergroup_id'] as number | undefined) ?? 0;
        this.membershipBasicGroupId = 0;
        this.host.setIsGroup(true);
        this.host.setIsChannel((type?.['is_channel'] as boolean | undefined) ?? this.host.isChannel());
        this.host.commitTimelineSnapshot();
        this.host.setMembershipState('checking');
        const groupReq: TdRequest = { '@type': 'getSupergroup' };
        groupReq['supergroup_id'] = this.membershipSupergroupId;
        this.host.client().send(groupReq).then((supergroup: TdObject): void => {
          if (seq === this.membershipSeq) {
            this.applyStatus(supergroup['status'] as TdObject | undefined);
          }
        }).catch((e: TdError): void => {
          if (seq === this.membershipSeq) {
            this.host.setMembershipState('writable');
          }
          logE(`MembershipSession.getSupergroup membership failed: ${e.message}`);
        });
        return;
      }
      if (typeName === 'chatTypeBasicGroup') {
        this.membershipBasicGroupId = (type?.['basic_group_id'] as number | undefined) ?? 0;
        this.membershipSupergroupId = 0;
        this.host.setIsGroup(true);
        this.host.setIsChannel(false);
        this.host.commitTimelineSnapshot();
        this.host.setMembershipState('checking');
        const groupReq: TdRequest = { '@type': 'getBasicGroup' };
        groupReq['basic_group_id'] = this.membershipBasicGroupId;
        this.host.client().send(groupReq).then((basicGroup: TdObject): void => {
          if (seq === this.membershipSeq) {
            this.applyStatus(basicGroup['status'] as TdObject | undefined);
          }
        }).catch((e: TdError): void => {
          if (seq === this.membershipSeq) {
            this.host.setMembershipState('writable');
          }
          logE(`MembershipSession.getBasicGroup membership failed: ${e.message}`);
        });
        return;
      }
      this.membershipSupergroupId = 0;
      this.membershipBasicGroupId = 0;
      // 密聊的输入区形态由 applySecretChat 定（待建立/已关闭都不能发），
      // 这里一律写 writable 会把它冲掉。
      if (typeName !== 'chatTypeSecret') {
        this.host.setMembershipState('writable');
      }
    }).catch((e: TdError): void => {
      if (seq === this.membershipSeq) {
        // Don't leave private/secret chats with a permanently hidden composer
        // if the supplementary status request fails.
        this.host.setMembershipState('writable');
      }
      logE(`MembershipSession.getChat membership failed: ${e.message}`);
    });
  }

  // 原 applyMembershipStatus（原 4698-4727 行）方法体逐字搬迁，
  // this.isChannel→this.host.isChannel()、membershipState 的写、
  // joiningChat 的写、以及尾部跨域收尾五行分别经宿主转发，判据、早退、
  // 语句顺序未改一处（含"两处 joiningChat=false 不合并"，见文件头专项
  // 说明）。
  applyStatus(status: TdObject | undefined): void {
    const type: string = (status?.['@type'] as string | undefined) ?? '';
    if (type === '') {
      return;
    }
    const rights = status?.['rights'] as TdObject | undefined;
    // 判定本身在 util/membershipState（有单测）：几条规则都不直观——被限制但
    // 仍在群里照样能发言、频道订阅者只读、频道管理员还要看有没有发帖权。
    // 被禁言者自己那份权限（chatMemberStatusRestricted 才有）。
    const selfPerms = status?.['permissions'] as TdObject | undefined;
    const next: string = membershipStateOf({
      statusType: type,
      isMember: (status?.['is_member'] as boolean | undefined) ?? false,
      isChannel: this.host.isChannel(),
      canPostMessages: (rights?.['can_post_messages'] as boolean | undefined) ?? false,
      // 两个权限字段**缺失时一律按放行**：兜底方向与本文件其余分支一致
      // （查不到就别把输入框藏了，最多发送时报错）。
      chatCanSendBasic: this.chatCanSendBasic,
      restrictedCanSendBasic:
        (selfPerms?.['can_send_basic_messages'] as boolean | undefined) ?? true
    });
    this.host.setMembershipState(next);
    if (!membershipLosesComposer(next)) {
      this.host.setJoiningChat(false);
      return;
    }
    // A membership update can arrive while the cached page still has composer
    // UI open. Close every composer-owned surface before replacing the bar.
    this.host.setJoiningChat(false);
    this.host.closeComposerSurfaces();
  }

  // subscribeMembershipUpdates（未随本批迁移，仍留在 ChatPage）的
  // updateSupergroup 推送监听器用它比对 `supergroup['id']` 是否等于当前
  // 正在跟踪的这个超级群——原文 `this.membershipSupergroupId` 的直接读点，
  // 私有化后补的只读取值器，读点不丢（见文件头专项说明）。
  supergroupId(): number {
    return this.membershipSupergroupId;
  }

  // 同上，对应 updateBasicGroup 推送监听器的比对，原文
  // `this.membershipBasicGroupId` 的读点。
  basicGroupId(): number {
    return this.membershipBasicGroupId;
  }

  // ChatPage.aboutToDisappear 全链路对本簇字段唯一的清理是
  // disposeSubscriptionsInOrder（原 3718 行）里紧挨着退订
  // 'membershipSupergroup'/'membershipBasicGroup' 两个推送监听器**之前**
  // 的一行 `this.membershipSeq++`——见文件头【dispose()】一节。
  // membershipState/membershipSupergroupId/membershipBasicGroupId 三者在
  // 这条路径上原本就从未被复位，不新增清零。
  dispose(): void {
    this.membershipSeq++;
  }
}
