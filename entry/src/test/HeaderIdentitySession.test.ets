import { describe, expect, it } from '@ohos/hypium';
import {
  HeaderIdentitySession, HeaderIdentityHost, ResolvedChatKind
} from '../main/ets/pages/chat/HeaderIdentitySession';
import { ChatEntry, computeInitials } from '../main/ets/store/ChatEntry';
import { MessageStore } from '../main/ets/store/MessageStore';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { SecretChatInfo } from '../main/ets/util/secretChat';
import { CHAT_HEADER_NAV_GUARD_MS } from '../main/ets/util/chatPageTuning';

// 顶栏身份解析与展示态（标题/头像/静音/密聊副标题/表情状态/资料跳转/Mini App
// 入口）的状态机，B8 把它从 ChatPage 整体搬进 pages/chat/HeaderIdentitySession.ets
// 之后补的第一组断言。写法照抄 SearchSession.test.ets / LiveTopCardController.test.ets
// （FakeHost、untilXxx 吞异常的包装函数、文件头先说环境限制）。
//
// 【三条环境限制，读用例前先看】
//
// 1. 本地测试跑不起 TDLib：Globals 里的 client 从没初始化过，getTdClient() 返回
//    的是 undefined，任何一条真会碰到 `.send(...)` 的路径都会在那一行同步抛错。
//    凡是会走到这一步的用例都用 untilUnavailableGlobal() 包一层——被断言的是
//    "发请求之前"那段同步字段变更，吞掉的是环境缺失而不是被测逻辑。这条和
//    SearchSession/LiveTopCardController 两个文件头的限制 1 完全一样。
//
// 2. 本文件独有、比限制 1 更狠的一条：本地测试同样跑不起全局 ChatStore
//    单例——Globals 里的 chats 同样从没初始化过，getChatStore() 返回 undefined。
//    问题在于 isSavedMessages()/refresh()/applyAvatar() 直接调用模块级单例
//    getChatStore()（不像 MessageStore 那样经 host.store() 现取，这与 ChatPage
//    本身访问 ChatStore 的方式一致，不是本控制器专属的设计问题），而且这三处
//    调用**没有"发请求之前"那段可断言的同步前缀**——isSavedMessages() 整个方法
//    体只有一行，那一行就是 getChatStore().entryOf(...)，refresh() 的第一条语句
//    同样是它。这意味着：
//      - isSavedMessages() 本身**没有写测试**：本地环境下调用它必然同步抛出，
//        没有任何可观测的"抛错之前"的状态可断言，写一条"包一层 try/catch、什么
//        都不断言"的用例只会是恒真断言，按纪律不写。
//      - refresh()（原 refreshHeader）**同样没有写测试**：第一条语句就抛，
//        6 个后续字段写入、host.onUnreadCount/onLiveEntry/onKnownBackground 三个
//        回调全部不可达。
//      - reset()（原 resetHeaderState）**只测得到"抛错之前"那一段前缀**：
//        `this.title = this.chatHeaderTitleNow('')`（源文件第 255 行，经
//        headerTitleFor → isSavedMessages → getChatStore）在 `if (cached !==
//        undefined)` 分支**之前**执行，无论 cached 传不传都会在这一行同步抛出，
//        这个分支内"缓存命中时 title/initials/avatarPath/isMuted/kind 取自
//        cached"这一整段——也就是"至少覆盖"清单第 4 条真正想测的东西——本地
//        完全测不到。下面的 reset 用例只钉住"抛错之前"确实执行到、且与 cached
//        是否传入无关的那一段前缀清空 + 两个 host 回调，不对 title/initials/
//        avatarPath/isMuted/kind 做任何断言（那些要么没被这段前缀碰过、要么在
//        抛错点之后，两种情况断言出来都是在钉"这套本地 harness 摸到哪就停在
//        哪"这个环境产物，不是在钉真实产品行为，按纪律不写）。
//      - applyTitle() 有一条分支**不会**触达 getChatStore()：host 的
//        threadRootId/forumTopicId/directMessagesTopicId 三者有一个非零时，
//        原文件的判据直接跳过 headerTitleFor(t) 那一行——这条分支测得到，见
//        下面单独一条用例，顺带钉住"评论区/话题视图不覆盖会话本身标题"这条
//        1572 附近注释记录过的规则。
//    上述几条只是记录当前这套本地单测 harness 的天花板，不代表生产环境有问题——
//    生产环境里 chats 单例在 ChatPage 挂树前就已经初始化好，这三个方法在真机
//    上从未观测到过这里说的"同步抛错"。
//
// 3. resolveSeq 是私有字段，测试读不到；applyResolvedChat 同样是 private，
//    只能由 resolveIdentity() 的 .then 回调触发——而 resolveIdentity() 一旦
//    chatId 非零就会在 getTdClient().send(...) 那一行同步抛错（见限制 1），
//    .then 回调因此永远不会被注册、更不会被调用。"至少覆盖"清单第 2 条字面上
//    问的是 applyResolvedHeaderChat（本类里叫 applyResolvedChat）的旧 seq 守卫，
//    这条本地测不到。但 resolveSeq 的比较逻辑（`if (seq !== this.resolveSeq)
//    return;`）在 applySecretChat() 里逐字重复了一遍，而 applySecretChat 是
//    public、纯同步、除末尾 fetchEmojiStatus() 外不碰任何全局单例——下面用它
//    验证同一枚 resolveSeq 守卫，不是原样测 applyResolvedChat，但测的是同一套
//    "旧 seq 请求回来时整个丢掉"机制，而不是摆设。

// 宿主（ChatPage）那一小片接口的替身：9 个取值器读下面的 …Value 字段，
// 9 个动作/回调只记账（onChatKindResolved 额外记下整份载荷，供字段级比对）。
class FakeHost implements HeaderIdentityHost {
  chatIdValue: number = 0;
  storeValue: MessageStore | null = null;
  topicNameValue: string = '';
  forumTopicIdValue: number = 0;
  directMessagesTopicIdValue: number = 0;
  threadRootIdValue: number = 0;
  isTranslatableValue: boolean = false;
  membershipStateValue: string = 'writable';
  unreadBadgeValue: number = 0;

  onChatKindResolvedCalls: ResolvedChatKind[] = [];
  onUnreadCountCalls: number[] = [];
  onLiveEntryCalls: ChatEntry[] = [];
  onKnownBackgroundCalls: TdObject[] = [];
  commitTimelineSnapshotCount: number = 0;
  onMembershipLosesComposerCount: number = 0;
  closeHeaderMenuCount: number = 0;
  clearSecretChatSubscriptionCount: number = 0;
  subscribeSecretChatIds: number[] = [];
  subscribeSecretChatSeqs: number[] = [];

  chatId: () => number = (): number => this.chatIdValue;
  store: () => MessageStore | null = (): MessageStore | null => this.storeValue;
  topicName: () => string = (): string => this.topicNameValue;
  forumTopicId: () => number = (): number => this.forumTopicIdValue;
  directMessagesTopicId: () => number = (): number => this.directMessagesTopicIdValue;
  threadRootId: () => number = (): number => this.threadRootIdValue;
  isTranslatable: () => boolean = (): boolean => this.isTranslatableValue;
  membershipState: () => string = (): string => this.membershipStateValue;
  unreadBadge: () => number = (): number => this.unreadBadgeValue;
  onChatKindResolved: (k: ResolvedChatKind) => void = (k: ResolvedChatKind): void => {
    this.onChatKindResolvedCalls.push(k);
  };
  onUnreadCount: (count: number) => void = (count: number): void => {
    this.onUnreadCountCalls.push(count);
  };
  onLiveEntry: (entry: ChatEntry) => void = (entry: ChatEntry): void => {
    this.onLiveEntryCalls.push(entry);
  };
  onKnownBackground: (background: TdObject) => void = (background: TdObject): void => {
    this.onKnownBackgroundCalls.push(background);
  };
  commitTimelineSnapshot: () => void = (): void => { this.commitTimelineSnapshotCount++; };
  onMembershipLosesComposer: () => void = (): void => { this.onMembershipLosesComposerCount++; };
  closeHeaderMenu: () => void = (): void => { this.closeHeaderMenuCount++; };
  clearSecretChatSubscription: () => void = (): void => { this.clearSecretChatSubscriptionCount++; };
  subscribeSecretChat: (secretChatId: number, seq: number) => void =
    (secretChatId: number, seq: number): void => {
      this.subscribeSecretChatIds.push(secretChatId);
      this.subscribeSecretChatSeqs.push(seq);
    };
}

function controllerOn(host: FakeHost): HeaderIdentitySession {
  const controller: HeaderIdentitySession = new HeaderIdentitySession();
  controller.bind(host);
  return controller;
}

// 见文件头限制 1/2。本地环境下 getTdClient()/getChatStore() 都是未初始化的模块
// 单例，摸到它们中任何一个都会同步抛错——这个函数把"环境缺失导致的抛错"和
// "被测逻辑本身的错误"分开，只吞前者。
function untilUnavailableGlobal(action: () => void): void {
  try {
    action();
  } catch (e) {
    // getTdClient()/getChatStore() 未初始化，吞掉。
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

// reset() 的第二个用例要证明"传不传 cached 都一样测不到缓存分支"，随手给一个
// 私聊形状的缓存条目——字段取值本身在本文件里不重要（缓存分支本地不可达，见
// 文件头限制 2），形状对齐 LiveTopCardController.test.ets 的 entryOf()。
function cachedPrivateEntry(): ChatEntry {
  return {
    id: 900, revision: 0, title: '缓存的标题', isMuted: true, usesDefaultMute: false,
    unreadCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: '', lastMessageDate: 0, lastMessageId: 0, lastSenderName: '',
    photoFileId: 0, avatarPath: '缓存的头像路径', initials: 'C', autoDeleteTime: 0,
    kind: 'private', isMarkedUnread: false, isSavedMessages: false,
    background: null, themeName: '',
    liveGroupCallId: 0, isLive: false, isRtmpLive: false,
    canDeleteOnlyForSelf: true, canDeleteForAllUsers: false
  };
}

function secretInfo(userId: number, outbound: boolean, state: string): SecretChatInfo {
  return { id: 1, userId: userId, state: state, isOutbound: outbound, layer: 1 };
}

export default function headerIdentitySessionTest() {
  describe('HeaderIdentitySession', () => {

    // 防的回归：subtitle 与 secretSubtitle 相互覆盖。两个字段本来就是分开的
    // （类里 1572 一带的注释：subtitle 由 MessageStore 推、secretSubtitle 由密聊
    // 状态机写，抢同一个字段谁后到谁赢），presentation() 里必须让 secretSubtitle
    // 非空时优先，否则密聊等待期一条普通的成员数广播就能把"正在建立加密连接"
    // 那句话顶掉。
    it('subtitleTextOf() 在 secretSubtitle 非空时优先于 subtitle', 0, (): void => {
      const controller: HeaderIdentitySession = controllerOn(new FakeHost());
      controller.subtitle = '3 位成员';
      controller.secretSubtitle = '正在建立加密连接';

      expect(controller.subtitleTextOf()).assertEqual('正在建立加密连接');

      // secretSubtitle 清空后应该让位，不是被锁死。
      controller.secretSubtitle = '';
      expect(controller.subtitleTextOf()).assertEqual('3 位成员');
      controller.dispose();
    });

    // 防的回归：resolveSeq 竞态守卫被删掉。字面意义上"applyResolvedChat 对旧 seq
    // 不写字段"本地测不到（见文件头限制 3），这里测的是同一枚 resolveSeq 守卫在
    // applySecretChat 里的重复实现——两处共用同一条 `seq !== this.resolveSeq`
    // 比较，删掉任何一处都是同一类回归：迟到的响应/推送用旧数据覆盖了新会话。
    it('旧 seq 的 applySecretChat 不写任何 @Trace（resolveSeq 竞态守卫）', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: HeaderIdentitySession = controllerOn(host);

      // resolveIdentity() 同步把 resolveSeq 从 0 自增到 1，随后在
      // getTdClient().send() 那一行抛错——被吞掉的只是环境缺失，
      // resolveSeq 的自增在抛错之前已经发生。
      untilUnavailableGlobal((): void => { controller.resolveIdentity(); });

      // 用旧 seq=0 调用：应该被判过期，一个字段都不写，onChatKindResolved
      // 也不该被调用。
      untilUnavailableGlobal((): void => {
        controller.applySecretChat(0, secretInfo(55, true, 'pending'));
      });
      expect(controller.secretSubtitle).assertEqual('');
      expect(controller.secretOutbound).assertFalse();
      expect(host.onChatKindResolvedCalls.length).assertEqual(0);

      // 用当前 seq=1 调用：应该正常生效。
      untilUnavailableGlobal((): void => {
        controller.applySecretChat(1, secretInfo(55, true, 'pending'));
      });
      expect(controller.secretOutbound).assertTrue();
      expect(controller.secretSubtitle).assertEqual('chat_header_secret_pending');
      expect(host.onChatKindResolvedCalls.length).assertEqual(1);
      controller.dispose();
    });

    // 防的回归：refreshIsBot 的同步首调（对应 chatTypePrivate 分支折进来的那次
    // "isGroup=false/isChannel=false/isBotChat=false"回传）被删掉，或者被多调
    // 一次——两种情况这条用例都会抓到。userId<=0 让方法在同步首调之后立刻返回，
    // 不碰 TDLib（真正的私聊分支永远传正数 userId，这里传 0 只是为了让用例在
    // 本地环境里干净地停在"只调了一次"这个点上）。
    it('refreshIsBot(userId<=0) 只调用一次 onChatKindResolved，字段与入参/host 现值一致', 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        host.membershipStateValue = 'writable';
        host.unreadBadgeValue = 5;
        const controller: HeaderIdentitySession = controllerOn(host);

        controller.refreshIsBot(0, 0, true);

        expect(host.onChatKindResolvedCalls.length).assertEqual(1);
        const k: ResolvedChatKind = host.onChatKindResolvedCalls[0];
        expect(k.isGroup).assertFalse();
        expect(k.isChannel).assertFalse();
        expect(k.isBotChat).assertFalse();
        expect(k.isTranslatable).assertTrue();
        expect(k.membershipState).assertEqual('writable');
        expect(k.unreadBadge).assertEqual(5);
        controller.dispose();
      });

    // 防的回归：dispose() 漏清 navigationTimer。openProfile() 排的这个
    // CHAT_HEADER_NAV_GUARD_MS 防连点定时器如果活过 dispose，就会往一个已经
    // 销毁的页面的 @Trace 上写 profileOpening=false——真机表现是"刚离开这个
    // 会话页，另一处东西还在悄悄改状态"。
    it('dispose() 之后 openProfile 的延迟回调不改 profileOpening', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.chatIdValue = 42;
        const controller: HeaderIdentitySession = controllerOn(host);
        // 把 peerUserId 弄成正数，越过 openProfile 的两个早退分支
        // （profileOpening 已经是 true / state==='error'）；applySecretChat
        // 是唯一一条不碰 getTdClient 也不碰 getChatStore 的公开赋值路径。
        untilUnavailableGlobal((): void => {
          controller.applySecretChat(0, secretInfo(77, false, 'ready'));
        });

        // openProfile 末尾会调 navigateToProfile → pushInto，本地环境没有任何
        // 页签栈注册（stackOf 恒返回 undefined），落到 router.pushUrl(...).catch()
        // 那条回退分支——按其实现不会同步抛错，但用 untilUnavailableGlobal 包一层
        // 仍然是无害的：profileOpening=true 与定时器调度都在这一句之前完成，
        // 就算这条假设有误，也不影响下面要断言的东西。
        untilUnavailableGlobal((): void => { controller.openProfile(); });
        // 阳性对照：确实进了防连点状态，不是本来就是 true。
        expect(controller.profileOpening).assertTrue();

        controller.dispose();
        // 哨兵：延迟回调若还活着，会在下面这段 sleep 期间把它写回 false。
        controller.profileOpening = true;
        await sleep(CHAT_HEADER_NAV_GUARD_MS + 260);
        expect(controller.profileOpening).assertTrue();
      });

    // 防的回归：评论区/话题视图里一条新的 subscribeHeaderTitle 推送把会话本身的
    // 标题挤掉话题名——判据是 host 的 threadRootId/forumTopicId/
    // directMessagesTopicId 三者有一个非零时跳过 headerTitleFor(t) 那一行。
    // 这条分支恰好也是 applyTitle 里唯一不触达 getChatStore() 的路径（见文件头
    // 限制 2），本地环境测得到；initials/state/loadError 三个字段仍然按输入的
    // 会话标题更新，不受这条早退影响。
    it('applyTitle 在话题/评论区视图里不覆盖 title，只更新 initials/state', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.threadRootIdValue = 99; // 正在评论区里
      const controller: HeaderIdentitySession = controllerOn(host);
      controller.title = '评论区自己的标题';
      controller.state = 'error';
      controller.loadError = '之前的错误';

      controller.applyTitle('会话本身的新标题');

      expect(controller.title).assertEqual('评论区自己的标题'); // 没被挤掉
      expect(controller.initials).assertEqual(computeInitials('会话本身的新标题'));
      expect(controller.state).assertEqual('ready');
      expect(controller.loadError).assertEqual('');

      // 空字符串按早退处理，什么都不碰。
      controller.applyTitle('');
      expect(controller.initials).assertEqual(computeInitials('会话本身的新标题'));
      controller.dispose();
    });

    // 防的回归：reset() 漏清某个字段，或者漏调两个 host 回调之一（头部菜单
    // 域/密聊订阅表都是页面字段，本类只负责在原来的调用点触发一次）。只钉住
    // "抛错之前"确实执行到、且与 cached 是否传入无关的那段前缀——见文件头限制
    // 2，title/initials/avatarPath/isMuted/kind 的"缓存命中"分支本地不可达，
    // 不在这里断言。
    it('reset() 在触达 getChatStore 之前清空一批字段并各调一次两个 host 回调', 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        const controller: HeaderIdentitySession = controllerOn(host);

        const dirty: () => void = (): void => {
          controller.state = 'error';
          controller.loadError = '之前的错误';
          controller.emojiPath = '之前的表情';
          controller.emojiFormat = 'webp';
          controller.profileOpening = true;
          controller.muteUpdating = true;
          controller.subtitle = '之前的副标题';
          controller.secretSubtitle = '之前的密聊副标题';
          controller.secretOutbound = true;
          controller.avatarPath = '之前的头像路径';
          controller.initials = 'Z';
        };

        const assertPrefixReset: () => void = (): void => {
          expect(controller.state).assertEqual('loading');
          expect(controller.loadError).assertEqual('');
          expect(controller.emojiPath).assertEqual('');
          expect(controller.emojiFormat).assertEqual('');
          expect(controller.profileOpening).assertFalse();
          expect(controller.muteUpdating).assertFalse();
          expect(controller.subtitle).assertEqual('');
          expect(controller.secretSubtitle).assertEqual('');
          expect(controller.secretOutbound).assertFalse();
          expect(controller.avatarPath).assertEqual('');
          expect(controller.initials).assertEqual('?');
        };

        dirty();
        untilUnavailableGlobal((): void => { controller.reset(undefined); });
        assertPrefixReset();
        expect(host.closeHeaderMenuCount).assertEqual(1);
        expect(host.clearSecretChatSubscriptionCount).assertEqual(1);

        // 传一个缓存条目进去：抛错点在 `if (cached !== undefined)` 分支之前，
        // 结果与不传 cached 时完全一样——这正是文件头限制 2 说的"本地测不到
        // 缓存分支"，这里只是确认"测不到"这件事本身是稳定的，不是随机的。
        dirty();
        untilUnavailableGlobal((): void => { controller.reset(cachedPrivateEntry()); });
        assertPrefixReset();
        expect(host.closeHeaderMenuCount).assertEqual(2);
        expect(host.clearSecretChatSubscriptionCount).assertEqual(2);
        controller.dispose();
      });

    // 防的回归：有人把控制器做成模块级单例，或者 dispose 波及了别的实例。
    // 平板分栏、导航栈多层时同时活着多个 ChatPage，各自的顶栏标题/头像/静音态
    // 不该串到一起。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份顶栏状态）', 0,
      (): void => {
        const hostA: FakeHost = new FakeHost();
        const hostB: FakeHost = new FakeHost();
        const a: HeaderIdentitySession = controllerOn(hostA);
        const b: HeaderIdentitySession = controllerOn(hostB);

        a.title = '会话 A';
        a.avatarPath = 'A 的头像';
        a.subtitle = 'A 的副标题';
        a.isMuted = true;
        a.profileOpening = true;

        expect(b.title).assertEqual('');
        expect(b.avatarPath).assertEqual('');
        expect(b.subtitle).assertEqual('');
        expect(b.isMuted).assertFalse();
        expect(b.profileOpening).assertFalse();

        // 一页销毁不能把另一页的状态一起清掉。
        b.title = '会话 B';
        b.muteUpdating = true;
        a.dispose();
        expect(b.title).assertEqual('会话 B');
        expect(b.muteUpdating).assertTrue();
        expect(a.title).assertEqual('会话 A'); // dispose 不清 title，顺带确认没被误清
        b.dispose();
      });
  });
}
