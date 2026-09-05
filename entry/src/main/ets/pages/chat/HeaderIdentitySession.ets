// 顶栏身份解析与展示态（标题/头像/静音/密聊副标题/表情状态/资料跳转/Mini App
// 入口）的状态机。从 ChatPage 整体搬出（B8 批）。
//
// 【为什么要搬】
// 对方在线/输入中每次翻转 subtitle，搬之前都要重跑一遍页面的 chatTitleBar
// 闭包 + 12 个 @Param 比较 + headerText() 算两遍——subtitle 只是顶栏里一行文字，
// 代价却是整页一轮依赖重算。搬进 @ObservedV2 之后，ChatHeader 直接持有本控制器
// 的引用、在自己的 build() 里读 @Trace 并自己拼 subtitleTextOf()，翻转只刷新
// 那一个 Text 节点，ChatPage 一个字都不读。
//
// 只把字段搬走、读点还留在页面，收益就只有行数——所以 titleTextOf()/
// subtitleTextOf() 必须拆成两半，让 ChatHeader 能自己合成副标题、页面 build 不再
// 订阅 subtitle，这是 B8 唯一真正缩小重渲染半径的地方（同 B5 TopBanners、
// B6 SearchHeader/SearchBottomBar 的教训）。
//
// 【为什么仍有 6 个字段搬不进来】
// isGroup / isChannel / isBotChat / isTranslatable / membershipState /
// unreadBadge 被 cacheKey、成员资格状态机、翻译驱动、ScrollFab 未读徽标等多个
// 与身份簇无关的域共同读写（refreshMembership/applyMembershipStatus 是另一条
// 完全独立、本批不动的写入链），留在页面。本类算出新值后经 host.onChatKindResolved
// 一次性回传，页面写完这 6 个字段后自己决定要不要接着调 refreshAdminLabels——
// 早年的 bug 正是"refreshAdminLabels 读 isGroup 时它还没被赋新值"，回调形状把
// "先写 isGroup 再调 refreshAdminLabels"这条顺序钉死在页面那一侧。
// refreshHeader（本类 refresh()）对 unreadBadge 的写入**不**经 onChatKindResolved，
// 单独走 host.onUnreadCount()——refresh() 由 MessageStore/ChatStore 更新驱动，
// 触发远比一次身份解析频繁；如果也塞进 onChatKindResolved，页面那侧"写完
// isGroup 就调 refreshAdminLabels"的回调形状会被逼着在每次消息到达时都空转一次
// 早退检查，量级不一样，就不获取这点"接口统一"的便宜了。
//
// 【为什么 headerResolveSeq 的全部读写必须钉在本类里】
// resolveIdentity() 发出的 getChat、refreshIsBot() 发出的 getUser、
// fetchEmojiStatus() 发出的 getUser、以及 chatTypeSecret 分支订阅的
// watchSecretChat 推送，全部是异步的；换会话/页面隐藏时只有让"当时发出的那一趟
// 请求"回来后自己判成过期，才不会用旧会话的数据覆盖新会话。这枚序号只要有第二份
// （比如页面自己也留一份），两份各自作废各自的，就会有请求明明该被判过期却被判
// 成"仍然当前"。所以它是 private，不出现在任何 host getter 里；host 只在
// subscribeSecretChat() 里*转发*一次调用方给的 seq，检查仍在本类内部完成
// （applySecretChat 自己比对）。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，每个都有自己的 chatId、自己的
// 顶栏身份解析进度。做成单例会让两页互相改对方的标题/头像。页面用字段初始化器
// new 一个：首帧前就已存在、引用全生命周期稳定、类型非空。
//
// 【为什么 dispose() 里先 ++resolveSeq 再清定时器】
// resolveSeq 是 getChat/getUser 的在途响应守卫：响应回来时先比对，对不上就整个
// 丢掉。先 ++resolveSeq 再 clearTimeout(navigationTimer)，是为了让「已经发出、
// 还没回来」的那趟 TDLib 请求在 then/catch 里被判成过期，而不是回来往一个已经
// dispose 的对象上写字段——与 LiveTopCardController/SearchSession 的 dispose
// 顺序一致，是本仓所有 @ObservedV2 控制器的通用约定。
//
// 【不在本类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。本簇的所有联动都用
// 显式方法调用表达。

import { promptAction } from '@kit.ArkUI';
import { getTdClient, getChatStore } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { MessageStore } from '../../store/MessageStore';
import { ChatEntry, computeInitials, isMutedFrom } from '../../store/ChatEntry';
import { MUTE_LONG, setMute } from '../../store/ChatActions';
// botMiniAppUrl 与本类的 @Trace botMiniAppUrl 字段同名，按仓库惯例（控制器内与
// util/ 同名纯函数冲突时用别名）导入。
import { botMiniAppUrl as fetchBotMiniAppUrl } from '../../store/BotApi';
import { resolveEmojiStatus } from '../../util/emojiStatus';
import { membershipLosesComposer } from '../../util/membershipState';
import { SecretChatInfo, secretHeaderKey, secretMembershipState } from '../../util/secretChat';
import {
  ChatHeaderInput, ChatHeaderPresentation, ChatHeaderTitleInput,
  chatHeaderPresentation, chatHeaderTitle
} from '../../util/chatHeaderPresentation';
import { CHAT_HEADER_NAV_GUARD_MS } from '../../util/chatPageTuning';
import { navigateToChatProfile, navigateToProfile } from '../../util/profileNav';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// applyResolvedChat/refreshIsBot/applySecretChat 算出的新值，一次性回传给页面
// 写进这 6 个页面字段（所有权裁决：被 cacheKey/成员资格/翻译多域读写，留页面）。
export interface ResolvedChatKind {
  isGroup: boolean;
  isChannel: boolean;
  isBotChat: boolean;
  isTranslatable: boolean;
  membershipState: string;
  unreadBadge: number;
}

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读页面
// 当下的真值，动作回调把副作用交回页面执行。仿 LiveTopCardController 的
// LiveTopCardHost / SearchSession 的 SearchSessionHost。
//
// 两条纪律：
// 1. 这里只放**取值器**，不放页面的 @Local 引用。控制器不缓存页面的值，每次要
//    用就现取——否则页面改了字段、控制器手里还是旧的。
// 2. isGroup/isChannel/isBotChat/isTranslatable/membershipState/unreadBadge 这
//    6 个字段本身留在页面，本类只经 onChatKindResolved 回传新值；本类需要「这一次
//    没变、维持原样」的那几个字段时，用下面的取值器现取页面当下的值，不在本类里
//    存一份影子拷贝。
export interface HeaderIdentityHost {
  // 当前会话 id。0 表示路由还没落地。
  chatId: () => number;
  // 当前 MessageStore；路由切换途中可能为 null。
  store: () => MessageStore | null;
  // 话题/评论区标题与三个作用域 id——chatHeaderTitleNow 只在这四个都为"未进入
  // 子视图"时才用会话本身的标题，否则显示话题/评论区自己的名字。
  topicName: () => string;
  forumTopicId: () => number;
  directMessagesTopicId: () => number;
  threadRootId: () => number;
  // 翻译总开关驱动的会话级判定；本类只在算出新值时覆盖它，其余时候原样传回。
  isTranslatable: () => boolean;
  // 成员资格状态机的当前值；只有 applySecretChat 会算出新值，其余调用点原样
  // 传回，交给页面写回同一个字段。
  membershipState: () => string;
  // 滚动到底部悬浮按钮的未读徽标；本类不改它，只在 onChatKindResolved 的载荷里
  // 原样带一份（配合"这 6 个字段合起来一次性回传"这条约定，避免调用点各自拼
  // 半份载荷）。refresh() 对未读数的真正写入走 onUnreadCount，不走这里。
  unreadBadge: () => number;
  // isGroup/isChannel/isBotChat/isTranslatable/membershipState/unreadBadge 六
  // 个字段的一次性回传。页面写完之后自己决定是否接着调 refreshAdminLabels——
  // 早年的 bug 正是"refreshAdminLabels 读 isGroup 时它还没被赋新值"（普通群的
  // 管理员标签从来没取到过），页面回调必须保持"先写 isGroup 再调
  // refreshAdminLabels"，refreshAdminLabels 自己开头 !isGroup 早退，多来几次
  // 无害（refreshIsBot 只在私聊分支触发，isGroup 恒为 false，早退不发请求）。
  onChatKindResolved: (k: ResolvedChatKind) => void;
  // refresh()（原 refreshHeader）对未读徽标的写入，单独一条通道、不进
  // onChatKindResolved——refresh() 由消息/会话列表更新驱动，触发频率远高于一次
  // 身份解析，不值得让页面回调里那句 refreshAdminLabels 早退检查跟着空转。
  onUnreadCount: (count: number) => void;
  // refresh() 里原样转发给 B5 LiveTopCardController 的那一段：
  // this.topCard.syncLiveFromChatEntry(e)。
  onLiveEntry: (entry: ChatEntry) => void;
  // refresh() 里原样转发给背景簇的那一段：this.bgStore?.applyKnownBackground(e.background)。
  // 只在 e.background !== null 时调用，入参因此是非空的 TdObject。
  onKnownBackground: (background: TdObject) => void;
  // applyResolvedChat 分支收尾时原来直接调用的 this.commitTimelineSnapshot()——
  // 时间线快照机制完全在页面（不变量 1），本类只负责在原来的调用点触发它。
  commitTimelineSnapshot: () => void;
  // applySecretChat 里 membershipLosesComposer(...) 命中时原来直接调用的
  // this.applyComposerMode(idleComposer())——composerMode 是 composer 域唯一写
  // 入口（B9 才搬），本类只负责在原来的调用点触发这一次清空。
  onMembershipLosesComposer: () => void;
  // reset()（原 resetHeaderState）里原样保留的 this.closeHeaderMenu()——头部菜单
  // 域本轮不动，仍由页面自己关。
  closeHeaderMenu: () => void;
  // reset() 里原样保留的 this.subscriptions.clear('secretChat')——订阅表是页面
  // 字段，本类不持有。
  clearSecretChatSubscription: () => void;
  // applyResolvedChat 的 chatTypeSecret 分支：把 watchSecretChat 的注册转交给
  // 页面（订阅要进页面的 subscriptions 表，由 disposeSubscriptionsInOrder 按既定
  // 顺序摘除）。页面侧实现形状：
  //   subscribeSecretChat: (secretChatId, seq) => {
  //     this.subscriptions.set('secretChat', watchSecretChat(secretChatId,
  //       (info) => { this.header.applySecretChat(seq, info); }));
  //   }
  // seq 由调用方（本类）传出、页面原样存进闭包，推送到达时连同 info 一起交回
  // applySecretChat，过期比对仍在本类内部完成——resolveSeq 本身不出户。
  subscribeSecretChat: (secretChatId: number, seq: number) => void;
}

@ObservedV2
export class HeaderIdentitySession {
  // ——— 显示态：ChatHeader 直接读这些 @Trace ———

  @Trace title: string = '';
  @Trace avatarPath: string = '';
  // 聊天页头部的动态头像（MP4 循环）。issue #63：资料页会动、对话里不动——
  // 头部一直只拿静态图。动画文件挂在 full info 的 chatPhoto.animation 里，
  // getChat 的 chatPhotoInfo 只有 has_animation 标志，必须多要一次。
  @Trace avatarAnimPath: string = '';
  @Trace initials: string = '?';
  @Trace subtitle: string = '';
  // 密聊未就绪时顶栏显示什么。**单独一个字段**：subtitle 由 MessageStore 推
  // （成员数/最后上线），两边抢同一个字段的话谁后到谁赢。
  @Trace secretSubtitle: string = '';
  // 密聊是不是自己发起的——等待期两侧话术不同。
  @Trace secretOutbound: boolean = false;
  // Header state is kept separate from message-history state. getChat can
  // resolve before history, fail independently, or arrive after a cached row.
  @Trace state: string = 'loading'; // loading | ready | error
  @Trace loadError: string = '';
  @Trace profileOpening: boolean = false;
  @Trace muteUpdating: boolean = false;
  @Trace isMuted: boolean = false;
  // Peer's premium emoji status (private chats) shown beside the header title.
  @Trace emojiPath: string = '';
  @Trace emojiFormat: string = '';
  // bot menu-button Mini App ('' = none)
  @Trace botMiniAppUrl: string = '';

  // ——— 内部机件：一律**不加 @Trace** ———
  // 序号守卫、一次性标记、定时器句柄都不驱动任何 UI，加了 @Trace 只会在每次
  // 自增/清标志时白发一轮通知。

  private peerUserId: number = 0;
  private kind: string = '';
  private identityResolved: boolean = false;
  private resolveSeq: number = 0;
  private emojiFetched: boolean = false;
  private navigationTimer: number = -1;

  // ——— 两个只读取值器：给页面里两处**留在页面**的方法用 ———
  //
  // 【为什么要开这两个口子】
  // openBotMiniApp 要 peerUserId 当 Mini App 的目标用户，rebuildTypingLabel 要
  // kind 分「私聊/密聊」与「群/频道」两档文案。这两个方法都不属于身份簇，按
  // 所有权裁决留在页面；但字段迁进来之后就成了 private，页面读不到。
  //
  // B8 迁移时一度用近似值顶替——peerUserId 换成 store.getPeerUserId()、kind 换成
  // `isGroup ? 'group' : 'private'`——两处各有自己的初值窗口差异：前者在「控制器
  // 自己那趟 getChat 已回、store 还没跟上」的窗口里会误判成 0 而挡掉 Mini App；
  // 后者在 identity 首次解析之前，原判据落在「群」档、替代判据落在「私聊」档。
  // 实践中两个窗口都很难触达，但那是**运气**不是**保证**。开两个取值器，页面按
  // 原样读，把运气换回保证。
  //
  // 不加 @Trace：它们不驱动 UI（读点在两个普通方法里，不在任何 build 链上），
  // 加了只会白发通知。
  currentPeerUserId(): number {
    return this.peerUserId;
  }

  currentKind(): string {
    return this.kind;
  }

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的值，
  // 与页面同名字段的初值一致。
  private host: HeaderIdentityHost = {
    chatId: (): number => 0,
    store: (): MessageStore | null => null,
    topicName: (): string => '',
    forumTopicId: (): number => 0,
    directMessagesTopicId: (): number => 0,
    threadRootId: (): number => 0,
    isTranslatable: (): boolean => false,
    membershipState: (): string => 'writable',
    unreadBadge: (): number => 0,
    onChatKindResolved: (_k: ResolvedChatKind): void => {},
    onUnreadCount: (_count: number): void => {},
    onLiveEntry: (_entry: ChatEntry): void => {},
    onKnownBackground: (_background: TdObject): void => {},
    commitTimelineSnapshot: (): void => {},
    onMembershipLosesComposer: (): void => {},
    closeHeaderMenu: (): void => {},
    clearSecretChatSubscription: (): void => {},
    subscribeSecretChat: (_secretChatId: number, _seq: number): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: HeaderIdentityHost): void {
    this.host = host;
  }

  // ——— 会话重置 ———

  // ChatPage.applyRouteParams 里换会话时调用，紧跟着调 resolveIdentity()。
  reset(cached: ChatEntry | undefined): void {
    this.resolveSeq++;
    this.state = 'loading';
    this.loadError = '';
    this.peerUserId = 0;
    this.kind = '';
    this.identityResolved = false;
    this.emojiPath = '';
    this.emojiFormat = '';
    this.emojiFetched = false;
    this.host.closeHeaderMenu();
    this.profileOpening = false;
    this.muteUpdating = false;
    this.subtitle = '';
    // 换会话时把上一条密聊的订阅退掉：新会话不是密聊的话，没有任何一处会
    // 再 set 同名订阅，它会一直挂着（回调里的 seq 闸让它无害，但仍是泄漏）。
    this.host.clearSecretChatSubscription();
    this.secretSubtitle = '';
    this.secretOutbound = false;
    this.avatarPath = '';
    this.initials = '?';
    this.title = this.chatHeaderTitleNow('');
    this.isMuted = false;
    if (cached !== undefined) {
      this.title = this.chatHeaderTitleNow(cached.title);
      this.initials = cached.initials;
      this.avatarPath = cached.avatarPath;
      this.isMuted = cached.isMuted;
      if (cached.kind === 'private') {
        // TDLib private-chat identifiers equal the peer user identifier.
        this.kind = 'private';
        this.peerUserId = cached.id;
        this.identityResolved = true;
      } else if (cached.kind === 'basicGroup' || cached.kind === 'supergroup' ||
        cached.kind === 'channel') {
        this.kind = cached.kind === 'channel' ? 'channel' : 'group';
        this.identityResolved = true;
      } else {
        this.kind = 'secret';
      }
      if (cached.title !== '') {
        this.state = 'ready';
      }
    }
  }

  // ——— 身份解析：getChat 一趟 ———

  resolveIdentity(): void {
    if (this.host.chatId() === 0) {
      this.state = 'error';
      this.loadError = str('cp_chat_params_invalid');
      return;
    }
    const seq = ++this.resolveSeq;
    if (this.title === '') {
      this.state = 'loading';
      this.loadError = '';
    }
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = this.host.chatId();
    getTdClient().send(request).then((chat: TdObject): void => {
      this.applyResolvedChat(chat, seq);
    }).catch((error: TdError): void => {
      if (seq !== this.resolveSeq) {
        return;
      }
      if (this.title === '') {
        this.state = 'error';
        this.loadError = str('cp_chat_load_failed');
      }
      logE(`HeaderIdentitySession.resolveIdentity failed: ${error.message}`);
    });
  }

  private applyResolvedChat(chat: TdObject, seq: number): void {
    if (seq !== this.resolveSeq) {
      return;
    }
    const resolvedTitle = (chat['title'] as string | undefined) ?? '';
    if (resolvedTitle !== '') {
      if (this.host.threadRootId() === 0 && this.host.forumTopicId() === 0 &&
        this.host.directMessagesTopicId() === 0) {
        this.title = this.headerTitleFor(resolvedTitle);
      }
      this.initials = computeInitials(resolvedTitle);
    }
    const settings = chat['notification_settings'] as TdObject | undefined;
    // isTranslatable 只在这里可能拿到新值；拿不到（settings 缺失）或乐观锁按着
    // （muteUpdating）就维持页面当下的值——用 host 取值器现取，不在本类里存一份。
    let isTranslatable: boolean = this.host.isTranslatable();
    if (settings !== undefined && !this.muteUpdating) {
      this.isMuted = isMutedFrom(settings);
      isTranslatable = (chat['is_translatable'] as boolean | undefined) ?? false;
    }
    const photo = chat['photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    const local = small !== undefined ? (small['local'] as TdObject | undefined) : undefined;
    const localPath = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    const localReady = local !== undefined
      ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    if (localReady && localPath !== '') {
      this.avatarPath = localPath;
    }
    const type = chat['type'] as TdObject | undefined;
    const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
    if (typeName === 'chatTypePrivate') {
      this.kind = 'private';
      this.peerUserId = (type!['user_id'] as number | undefined) ?? this.host.chatId();
      this.identityResolved = this.peerUserId > 0;
      // isGroup/isChannel/isBotChat 三个字段的回传折进了 refreshIsBot()：它的第一
      // 步就是同步调一次 onChatKindResolved(isGroup=false, isChannel=false,
      // isBotChat=false)（对应原来这里的 isGroup=false; isChannel=false; 两行 +
      // refreshIsBot 内部自己的 isBotChat=false），之后才异步解析出真正的
      // isBotChat。私聊分支不会再单独发一次。isTranslatable 通过局部变量原样
      // 带过去，避免 refreshIsBot 内部还要用 host.isTranslatable() 现取一次可能
      // 尚未提交的新值。
      this.refreshBotMiniApp(this.peerUserId);
      this.refreshIsBot(this.peerUserId, seq, isTranslatable);
      this.refreshAvatarAnimation(type);
    } else if (typeName === 'chatTypeBasicGroup') {
      this.kind = 'group';
      this.identityResolved = true;
      // 【B8 搬迁点】原来这里是 isBotChat=false; headerKind=...; isGroup=true;
      // isChannel=false; 四行分开赋值，紧跟着 refreshHeaderAvatarAnimation(type)
      // 与 refreshAdminLabels()——注释原文："必须在 isGroup 赋值之后：
      // refreshAdminLabels 开头就按 !isGroup 早退，原来这行在赋值之前，普通群
      // （非超级群）的管理员标签从来没取到过。"isGroup/isChannel/isBotChat 三个
      // 字段现在只能由页面写（所有权裁决），这里改成一次 onChatKindResolved 回传，
      // "先写 isGroup 再调 refreshAdminLabels"这条顺序钉在页面的回调实现里
      // （见 HeaderIdentityHost.onChatKindResolved 的文档注释）。
      this.host.onChatKindResolved(this.resolvedChatKind(true, false, false, isTranslatable));
      this.refreshAvatarAnimation(type);
    } else if (typeName === 'chatTypeSupergroup') {
      const isChannel = (type!['is_channel'] as boolean | undefined) ?? false;
      this.kind = isChannel ? 'channel' : 'group';
      this.identityResolved = true;
      this.host.onChatKindResolved(this.resolvedChatKind(true, isChannel, false, isTranslatable));
      this.refreshAvatarAnimation(type);
    } else if (typeName === 'chatTypeSecret') {
      // 密聊对面不可能是机器人。
      this.kind = 'secret';
      this.host.onChatKindResolved(this.resolvedChatKind(false, false, false, isTranslatable));
      // 盯住状态而不是取一次：密聊建立是异步的，pending → ready 只由
      // updateSecretChat 推（理由见 store/SecretChatWatch）。这一个订阅同时
      // 喂三样：对方 user id、顶栏副标题、输入区形态。订阅登记转交页面（订阅表是
      // 页面字段），seq 闸的比对仍在 applySecretChat 内部完成。
      const secretId = (type!['secret_chat_id'] as number | undefined) ?? 0;
      this.host.subscribeSecretChat(secretId, seq);
    }
    this.host.commitTimelineSnapshot();
    this.state = resolvedTitle !== '' || this.title !== '' ? 'ready' : 'error';
    this.loadError = this.state === 'error' ? str('cp_chat_unavailable') : '';
    this.fetchEmojiStatus();
  }

  // 密聊状态落到三处 UI。判定全在 util/secretChat（有单测），这里只搬运。
  // seq 由 subscribeSecretChat() 转交给页面、页面存进 watchSecretChat 回调的
  // 闭包，推送到达时原样带回来——这里做的正是原来嵌在 watchSecretChat 回调里的
  // `if (seq !== this.headerResolveSeq) return;` 那一次比对。
  applySecretChat(seq: number, info: SecretChatInfo): void {
    if (seq !== this.resolveSeq) {
      return;
    }
    this.peerUserId = info.userId;
    this.identityResolved = info.userId > 0;
    this.secretOutbound = info.isOutbound;
    const headerKey: string = secretHeaderKey(info);
    this.secretSubtitle = headerKey !== '' ? str(headerKey) : '';
    const bar: string = secretMembershipState(info);
    const nextMembershipState: string = bar !== '' ? bar : 'writable';
    const k: ResolvedChatKind = {
      isGroup: false,
      isChannel: false,
      isBotChat: false,
      isTranslatable: this.host.isTranslatable(),
      membershipState: nextMembershipState,
      unreadBadge: this.host.unreadBadge()
    };
    this.host.onChatKindResolved(k);
    if (membershipLosesComposer(nextMembershipState)) {
      this.host.onMembershipLosesComposer();
    }
    this.fetchEmojiStatus();
  }

  // ——— 会话列表推来的增量刷新 ———

  // ChatStore 每次广播时调用（原 ChatPage.refreshHeader）。
  refresh(): void {
    const e: ChatEntry | undefined = getChatStore().entryOf(this.host.chatId());
    // A topic/thread view keeps its own name; the rest of the header still
    // shows the underlying chat's avatar and mute state.
    this.title = this.chatHeaderTitleNow(e !== undefined ? e.title : this.title);
    if (e === undefined) {
      return;
    }
    // Don't clobber a MessageStore-resolved avatar (channels/folders) with an empty one.
    if (e.avatarPath !== '') { this.avatarPath = e.avatarPath; }
    this.initials = e.initials;
    if (!this.muteUpdating) {
      this.isMuted = e.isMuted;
    }
    this.host.onUnreadCount(e.unreadCount); // live unread count for the scroll-to-bottom badge
    if (e.title !== '') {
      this.state = 'ready';
      this.loadError = '';
    }
    if (!this.identityResolved) {
      if (e.kind === 'private') {
        this.kind = 'private';
        this.peerUserId = e.id;
        this.identityResolved = true;
      } else if (e.kind === 'basicGroup' || e.kind === 'supergroup' || e.kind === 'channel') {
        this.kind = e.kind === 'channel' ? 'channel' : 'group';
        this.identityResolved = true;
      }
    }
    if (e.background !== null) {
      this.host.onKnownBackground(e.background);
    }
    this.host.onLiveEntry(e);
  }

  // ——— 三路订阅回调（订阅本身留在页面，进 subscriptions 表）———

  // store.subscribeSubtitle 的回调体。
  applySubtitle(s: string): void {
    this.subtitle = s;
    this.fetchEmojiStatus();
  }

  // store.subscribeHeaderTitle 的回调体（原样保留"话题/评论区不覆盖标题"这条判据）。
  applyTitle(t: string): void {
    if (t === '') {
      return;
    }
    if (this.host.threadRootId() === 0 && this.host.forumTopicId() === 0 &&
      this.host.directMessagesTopicId() === 0) {
      this.title = this.headerTitleFor(t);
    }
    this.initials = computeInitials(t);
    this.state = 'ready';
    this.loadError = '';
  }

  // store.subscribeHeaderAvatar 的回调体，含旁路写 ChatStore 那一行
  // （MessageStore 解析头像独立于 ChatStore/FileService，backfill 一下列表项，
  // 让会话列表不必再单独走一条下载路径）。
  applyAvatar(p: string): void {
    if (p === '') {
      return;
    }
    this.avatarPath = p;
    getChatStore().setAvatarPath(this.host.chatId(), p);
  }

  // 和自己的私聊就是「我的收藏」。TDLib 对它没有任何标记，标题是自己的昵称、
  // 头像是自己的头像；判据只能是 chat.id === 自己的 user id（见 ChatStore）。
  isSavedMessages(): boolean {
    const entry = getChatStore().entryOf(this.host.chatId());
    return entry !== undefined && entry.isSavedMessages;
  }

  // 标题的统一出口：三处赋值都先过这里，「我的收藏」在这一处换掉就够了。
  private headerTitleFor(chatTitle: string): string {
    return this.isSavedMessages() ? str('cl_saved_messages') : chatTitle;
  }

  private chatHeaderTitleNow(chatTitle: string): string {
    const input: ChatHeaderTitleInput = {
      chatTitle: this.headerTitleFor(chatTitle),
      topicName: this.host.topicName(),
      forumTopicId: this.host.forumTopicId(),
      directMessagesTopicId: this.host.directMessagesTopicId(),
      threadRootId: this.host.threadRootId()
    };
    return chatHeaderTitle(input);
  }

  // Header title/subtitle wording lives in chatHeaderPresentation, where the
  // "cached title beats a pending load" and error-fallback rules are tested.
  private presentation(): ChatHeaderPresentation {
    const input: ChatHeaderInput = {
      title: this.title,
      subtitle: this.secretSubtitle !== '' ? this.secretSubtitle : this.subtitle,
      state: this.state,
      loadError: this.loadError,
      kind: this.kind
    };
    return chatHeaderPresentation(input);
  }

  // 页面用：openDeleteConfirm/confirmLeaveChat 等簇外读者要的是顶栏此刻显示的
  // 标题文案（含"正在加载…"/"无法打开"兜底），不是原始 title 字段。
  titleTextOf(): string {
    return this.presentation().titleText;
  }

  // 给子组件（ChatHeader）用：内部读本类的 subtitle/secretSubtitle 自己合成，
  // 页面 build 不再需要读这两个字段才能拼出 ChatHeader 的 subtitleText 入参——
  // 这是本批性能收益的全部来源。
  subtitleTextOf(): string {
    return this.presentation().subtitleText;
  }

  // ——— 头像/标题点击 → 资料页 ———

  // Header avatar/title tap → detail page: users/bots get the personal
  // profile, groups/channels the chat profile.
  openProfile(): void {
    if (this.profileOpening) {
      return;
    }
    if (this.state === 'error') {
      this.resolveIdentity();
      return;
    }
    const store: MessageStore | null = this.host.store();
    const storeUid = store !== null ? store.getPeerUserId() : 0;
    const uid = this.peerUserId > 0 ? this.peerUserId : storeUid;
    // 曾经是一个 url 字符串变量 + 末尾一次 router.pushUrl；两张资料页都迁成了
    // NavDestination，改成用 openUserProfile 记住该开哪一张，末尾分发到对应
    // 漏斗。分支条件与参数一字未改。
    let openUserProfile: boolean = false;
    let params: Record<string, Object>;
    if (uid > 0) {
      openUserProfile = true;
      params = { 'userId': uid };
    } else if (this.identityResolved || (store !== null && store.getIsGroup())) {
      openUserProfile = false;
      params = { 'chatId': this.host.chatId() };
    } else {
      promptAction.showToast({ message: $r('app.string.cp_profile_loading'), duration: 1200 });
      this.resolveIdentity();
      return;
    }
    this.profileOpening = true;
    if (this.navigationTimer !== -1) {
      clearTimeout(this.navigationTimer);
    }
    this.navigationTimer = setTimeout((): void => {
      this.navigationTimer = -1;
      this.profileOpening = false;
    }, CHAT_HEADER_NAV_GUARD_MS);
    // 迁移前这里是 router.pushUrl(...).catch(...)：失败时提前解掉防连点闸门并
    // 弹「打不开资料页」。漏斗是同步 void，推进一个已注册的栈不会失败，那个
    // catch 分支因此不再可达——闸门仍由上面那个 CHAT_HEADER_NAV_GUARD_MS 的
    // 定时器按时解掉，行为与「跳转成功」那一路完全一致。栈没注册时的回退路径
    // 由 profileNav 内部记日志。
    if (openUserProfile) {
      navigateToProfile(params);
    } else {
      navigateToChatProfile(params);
    }
  }

  // ——— 静音开关（头部 ⋮ 菜单调用） ———

  toggleMute(): void {
    if (this.muteUpdating) {
      return;
    }
    const previous = this.isMuted;
    const next = !previous;
    this.muteUpdating = true;
    this.isMuted = next;
    // setMute 会先读取完整通知设置，所以在 TDLib 接受修改前保持更新锁；
    // 否则任意一次聊天刷新都会立刻用 ChatStore 的旧值覆盖乐观状态。
    setMute(this.host.chatId(), next ? MUTE_LONG : 0).then((success: boolean): void => {
      if (!success) {
        this.isMuted = previous;
      }
      this.muteUpdating = false;
    });
  }

  // ——— Emoji Status（私聊，顶栏标题旁边那个小图标） ———

  // Private chat: the peer's emoji status appears beside the header title.
  fetchEmojiStatus(): void {
    if (this.emojiFetched) {
      return;
    }
    const store: MessageStore | null = this.host.store();
    const uid = this.peerUserId > 0 ? this.peerUserId : (store !== null ? store.getPeerUserId() : 0);
    if (uid <= 0) {
      return;
    }
    const resolveSeq = this.resolveSeq;
    this.emojiFetched = true;
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = uid;
    getTdClient().send(req).then((user: TdObject): void => {
      resolveEmojiStatus(user['emoji_status'] as TdObject | undefined, (path: string, format: string): void => {
        const currentStore: MessageStore | null = this.host.store();
        const currentUid = this.peerUserId > 0
          ? this.peerUserId : (currentStore !== null ? currentStore.getPeerUserId() : 0);
        if (resolveSeq !== this.resolveSeq || uid !== currentUid) {
          return;
        }
        this.emojiPath = path;
        this.emojiFormat = format;
      });
    }).catch((e: TdError): void => {
      if (resolveSeq === this.resolveSeq) {
        this.emojiFetched = false;
      }
      logE(`HeaderIdentitySession.fetchEmojiStatus failed: ${e.message}`);
    });
  }

  // ——— 头部动态头像 ———

  // 头部动态头像。full info 的 photo 是 chatPhoto，可选的 animation 是一小段
  // MP4；有就下下来交给 AvatarView（它自己看省电开关决定放不放）。
  refreshAvatarAnimation(type: TdObject | undefined): void {
    this.avatarAnimPath = '';
    const chatId: number = this.host.chatId();
    const typeName: string = type !== undefined
      ? ((type['@type'] as string | undefined) ?? '') : '';
    let req: TdRequest | null = null;
    if (typeName === 'chatTypePrivate') {
      req = { '@type': 'getUserFullInfo' };
      req['user_id'] = (type!['user_id'] as number | undefined) ?? 0;
    } else if (typeName === 'chatTypeSupergroup') {
      req = { '@type': 'getSupergroupFullInfo' };
      req['supergroup_id'] = (type!['supergroup_id'] as number | undefined) ?? 0;
    } else if (typeName === 'chatTypeBasicGroup') {
      req = { '@type': 'getBasicGroupFullInfo' };
      req['basic_group_id'] = (type!['basic_group_id'] as number | undefined) ?? 0;
    }
    if (req === null) {
      return;
    }
    getTdClient().send(req, 15000).then((full: TdObject): void => {
      if (this.host.chatId() !== chatId) {
        return; // 期间换了会话
      }
      const photo = (full['photo'] as TdObject | undefined)
        ?? (full['personal_photo'] as TdObject | undefined)
        ?? (full['public_photo'] as TdObject | undefined);
      const anim = photo !== undefined ? (photo['animation'] as TdObject | undefined) : undefined;
      const file = anim !== undefined ? (anim['file'] as TdObject | undefined) : undefined;
      const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      if (fileId <= 0) {
        return;
      }
      const dl: TdRequest = { '@type': 'downloadFile' };
      dl['file_id'] = fileId;
      dl['priority'] = 2;
      dl['synchronous'] = true;
      getTdClient().send(dl, 30000).then((f: TdObject): void => {
        if (this.host.chatId() !== chatId) {
          return;
        }
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.avatarAnimPath = path;
        }
      }).catch((e: TdError): void => {
        logE(`HeaderIdentitySession.refreshAvatarAnimation download failed: ${e.message}`);
      });
    }).catch((e: TdError): void => {
      // 拿不到 full info 就保持静态头像，不打扰。
      logE(`HeaderIdentitySession.refreshAvatarAnimation fullInfo failed: ${e.message}`);
    });
  }

  // ——— 私聊对面是不是机器人 ———

  // 只在私聊分支触发（chatTypePrivate），isGroup/isChannel 因此恒为 false——
  // 两次 onChatKindResolved（同步重置 + 异步解析结果）都不会影响页面那侧
  // "先写 isGroup 再调 refreshAdminLabels" 的早退判断。isTranslatable 由调用方
  // （applyResolvedChat）把刚算出的新值原样带进来，只用于这第一次同步回传；
  // 异步回调里改用 host.isTranslatable() 现取——那时可能已经隔了一段时间，
  // 页面上的值可能已经被别处更新过，不能用这里捕获的旧值覆盖回去。
  refreshIsBot(userId: number, seq: number, isTranslatable: boolean): void {
    this.host.onChatKindResolved(this.resolvedChatKind(false, false, false, isTranslatable));
    if (userId <= 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = userId;
    getTdClient().send(req).then((user: TdObject): void => {
      if (seq !== this.resolveSeq) {
        return;
      }
      const type = user['type'] as TdObject | undefined;
      const typeName: string = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      const isBot: boolean = typeName === 'userTypeBot';
      this.host.onChatKindResolved(this.resolvedChatKind(false, false, isBot, this.host.isTranslatable()));
    }).catch((error: TdError): void => {
      logE(`HeaderIdentitySession.refreshIsBot getUser failed: ${error.message}`);
    });
  }

  // ——— 机器人 Mini App 入口 ———

  refreshBotMiniApp(userId: number): void {
    this.botMiniAppUrl = '';
    if (userId <= 0) {
      return;
    }
    fetchBotMiniAppUrl(userId).then((url: string): void => {
      if (this.peerUserId === userId) { this.botMiniAppUrl = url; }
    }).catch((): void => {});
  }

  // isGroup/isChannel/isBotChat/isTranslatable 四个新值 + membershipState/
  // unreadBadge 的现取值，拼成一次 onChatKindResolved 回传的完整载荷。
  // membershipState 只有 applySecretChat 会算出新值，那条调用点不走这个
  // helper（它需要传一个新的 membershipState，不是现取）。
  private resolvedChatKind(
    isGroup: boolean, isChannel: boolean, isBotChat: boolean, isTranslatable: boolean
  ): ResolvedChatKind {
    return {
      isGroup: isGroup,
      isChannel: isChannel,
      isBotChat: isBotChat,
      isTranslatable: isTranslatable,
      membershipState: this.host.membershipState(),
      unreadBadge: this.host.unreadBadge()
    };
  }

  // ChatPage.aboutToDisappear 调用，放在原来清 header*/isMuted 相关字段的位置
  // （disposeTimersAndSeqGuards）。
  //
  // 顺序照搬 aboutToDisappear：++resolveSeq 在最前（作废在途的 getChat/getUser），
  // 再清定时器句柄，最后复位两个忙标志——与 LiveTopCardController/SearchSession
  // 的 dispose 顺序约定一致。closeHeaderMenu() 不在这里：头部菜单域本轮不动，
  // 仍由页面自己在 disposeTimersAndSeqGuards 里直接调用。
  dispose(): void {
    this.resolveSeq++;
    if (this.navigationTimer !== -1) {
      clearTimeout(this.navigationTimer);
      this.navigationTimer = -1;
    }
    this.profileOpening = false;
    this.muteUpdating = false;
  }
}
