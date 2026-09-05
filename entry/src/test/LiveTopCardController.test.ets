import { describe, expect, it } from '@ohos/hypium';
import {
  LiveTopCardController, LiveTopCardHost
} from '../main/ets/pages/chat/LiveTopCardController';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { MessageStore } from '../main/ets/store/MessageStore';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import {
  KEY_POWER_ACTIVE, KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS
} from '../main/ets/store/AppSettings';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import { TOP_CARD_LOADING_DELAY_MS } from '../main/ets/util/chatPageTuning';

// 顶栏下挂那张浮卡（置顶条 + 直播条）的状态机，B5 把它从 ChatPage 整体搬进
// pages/chat/LiveTopCardController.ets 之后补的第一组断言。
//
// 搬之前这簇是 ChatPage 的 14 个 @Local，任何一条判据都只能靠上机点一遍来验；
// 现在它是个可以直接 new 的 @ObservedV2 类（先例：ChatEnvMirror.test.ets），
// 这些规则第一次能被钉住。钉的不是"值等于多少"，而是几条一旦被改写就会在真机上
// 表现成"横幅抖一下 / 永远点不动 / 两个会话页串味"的规则。
//
// 【两条环境限制，读用例前先看】
// 1. 本地测试跑不起 TDLib：Globals 里的 client 从没初始化过，getTdClient() 返回
//    的是 undefined，`getChat` / `getGroupCall` 那一句会同步抛。凡是会走到发请求
//    的用例都用 untilTdlibSend() 包一层——被断言的是"发请求之前"那段同步字段
//    变更（重置了没有、loading 了没有），吞掉的是环境缺失而不是被测逻辑。
// 2. liveChatResolveSeq / liveGroupResolveSeq 是私有字段，测试读不到；响应回调
//    本身也进不来（见第 1 条），所以"迟到响应被 seq 判成过期"没法直接断言。
//    dispose 的守卫在这里拆成两半验：定时器那一半是实测的（哨兵 + 等待，见
//    「dispose 之后…」两条），在途记账那一半靠去重守卫的可观测副作用验。要把
//    seq 那一半也直接断言，需要 Globals 提供可注入的 TdClient。

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

// 宿主（ChatPage）那一小片接口的替身：6 个取值器读下面的 …Value 字段，5 个动作
// 回调只记账。控制器不许缓存宿主的值，所以改 …Value 就等于"页面那边变了"。
class FakeHost implements LiveTopCardHost {
  chatIdValue: number = 0;
  threadRootIdValue: number = 0;
  titleValue: string = '';
  storeValue: MessageStore | null = null;
  groupsValue: AlbumGroup[] = [];
  curStartIdxValue: number = -1;
  prepareUserJumpCount: number = 0;
  scrollToLatestCount: number = 0;
  scrollToIndexArgs: number[] = [];
  flashAtIndexArgs: number[] = [];
  jumpToPinnedArgs: number[] = [];

  chatId: () => number = (): number => this.chatIdValue;
  threadRootId: () => number = (): number => this.threadRootIdValue;
  title: () => string = (): string => this.titleValue;
  store: () => MessageStore | null = (): MessageStore | null => this.storeValue;
  groups: () => AlbumGroup[] = (): AlbumGroup[] => this.groupsValue;
  curStartIdx: () => number = (): number => this.curStartIdxValue;
  prepareUserJump: () => void = (): void => { this.prepareUserJumpCount++; };
  scrollToLatest: () => void = (): void => { this.scrollToLatestCount++; };
  scrollToIndex: (index: number) => void = (index: number): void => {
    this.scrollToIndexArgs.push(index);
  };
  flashAtIndex: (index: number) => void = (index: number): void => {
    this.flashAtIndexArgs.push(index);
  };
  jumpToPinned: (messageId: number) => void = (messageId: number): void => {
    this.jumpToPinnedArgs.push(messageId);
  };

  // 五个动作回调一共被调了多少次——"控制器一个字都没让页面动"用它断言。
  actionCalls(): number {
    return this.prepareUserJumpCount + this.scrollToLatestCount +
      this.scrollToIndexArgs.length + this.flashAtIndexArgs.length +
      this.jumpToPinnedArgs.length;
  }
}

function controllerOn(host: FakeHost): LiveTopCardController {
  const controller: LiveTopCardController = new LiveTopCardController();
  controller.bind(host);
  return controller;
}

// 见文件头限制 1。若哪天 Globals 真被初始化了，send 是异步的，本函数照样什么都
// 不改——用例断言的都是同步段。
function untilTdlibSend(action: () => void): void {
  try {
    action();
  } catch (e) {
    // getTdClient() 未初始化，吞掉。
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

// 干净的 MessageStore：getPinnedIds() 是空数组、refreshPinned() 只往假 bridge 里
// 塞一条 json。onPinnedTap 只需要它这两点。
function storeOf(): MessageStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  return new MessageStore(client, new UserStore(client), 5);
}

function groupCallOf(active: boolean, rtmp: boolean, participants: number): TdObject {
  const call: TdObject = { '@type': 'groupCall' };
  call['is_active'] = active;
  call['is_rtmp_stream'] = rtmp;
  call['participant_count'] = participants;
  return call;
}

// 只填 syncLiveFromChatEntry 读得到的三个字段，其余取占位值。
function entryOf(groupCallId: number, isLive: boolean, isRtmp: boolean): ChatEntry {
  return {
    id: 5, revision: 0, title: 't', isMuted: false, usesDefaultMute: true,
    unreadCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: '', lastMessageDate: 0, lastMessageId: 0, lastSenderName: '',
    photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'supergroup', isMarkedUnread: false, isSavedMessages: false,
    background: null, themeName: '',
    liveGroupCallId: groupCallId, isLive: isLive, isRtmpLive: isRtmp,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false
  };
}

// 省电开关决定脉冲翻不翻、骨架延迟是 180ms 还是 0ms（powerFeatureEnabled 默认为
// true，但 powerSavingActive 一票否决，而整套用例共用一个 AppStorage）。用到时序
// 的用例先把这三个键摆成确定值，做法照抄 ChatEffects.test.ets。
function armPowerKeys(): void {
  AppStorage.setOrCreate(KEY_POWER_ACTIVE, false);
  AppStorage.setOrCreate(KEY_POWER_PARTICLES, true);
  AppStorage.setOrCreate(KEY_POWER_SMOOTH_TRANSITIONS, true);
}

export default function liveTopCardControllerTest() {
  describe('LiveTopCardController', () => {

    // 防的回归：把重置那一坨从 changed 判定里提出来。setLiveGroupCallId 是 2s
    // 轮询 + updateGroupCall + syncLiveFromChatEntry 的共同入口，同一个 id 会被
    // 反复喂进来；一旦每次都重置，正在直播的横幅就会每两秒抖一下——人数归零、
    // "直播中"闪回 loading、脉冲呼吸断一拍。
    it('group call id 没变时不重置直播态（防的回归：2s 轮询把横幅抖成闪烁）', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: LiveTopCardController = controllerOn(host);
      controller.liveGroupCallId = 7;
      controller.liveCallIsActive = true;
      controller.liveCallIsRtmp = true;
      controller.liveParticipantCount = 12;
      controller.liveLoadState = 'ready';
      controller.livePulseExpanded = true;

      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });

      expect(controller.liveGroupCallId).assertEqual(7);
      expect(controller.liveCallIsActive).assertTrue();
      expect(controller.liveCallIsRtmp).assertTrue();
      expect(controller.liveParticipantCount).assertEqual(12);
      // 已经确认在直播时连 loading 都不许闪：这是 `if (!liveCallIsActive)` 那道守卫。
      expect(controller.liveLoadState).assertEqual('ready');
      expect(controller.livePulseExpanded).assertTrue();
      controller.dispose();
    });

    // 防的回归：换了 id 却留着上一场的人数/RTMP 位。两场通话之间的身份切换如果
    // 只改 id 不清残值，横幅会拿上一场的在线人数去描述新的一场。
    it('group call id 变了要连人数/RTMP/脉冲一起重置（防的回归：新通话沿用上一场的人数）', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: LiveTopCardController = controllerOn(host);
      controller.liveGroupCallId = 7;
      controller.liveCallIsActive = true;
      controller.liveCallIsRtmp = true;
      controller.liveParticipantCount = 12;
      controller.liveLoadState = 'ready';
      controller.livePulseExpanded = true;

      untilTdlibSend((): void => { controller.setLiveGroupCallId(9); });

      expect(controller.liveGroupCallId).assertEqual(9);
      expect(controller.liveCallIsActive).assertFalse();
      expect(controller.liveCallIsRtmp).assertFalse();
      expect(controller.liveParticipantCount).assertEqual(0);
      expect(controller.livePulseExpanded).assertFalse();
      // 新身份还没确认活跃，横幅进 loading 等 getGroupCall 回来。
      expect(controller.liveLoadState).assertEqual('loading');
      controller.dispose();
    });

    // 防的回归：通话结束（id 归零）时还去发一趟 getGroupCall，或者把 loadState
    // 停在 loading——那样直播条会挂着骨架不走。
    it('id 归零＝通话结束：直接算 ready 收掉，不再发请求（防的回归：骨架挂着不走）', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: LiveTopCardController = controllerOn(host);
      controller.liveGroupCallId = 7;
      controller.liveCallIsActive = true;
      controller.liveParticipantCount = 5;
      controller.liveLoadState = 'ready';

      // 不包 untilTdlibSend：这一支在碰 getTdClient() 之前就 return 了，真抛出来
      // 就说明有人把 `groupCallId <= 0` 的短路删了。
      controller.setLiveGroupCallId(0);

      expect(controller.liveGroupCallId).assertEqual(0);
      expect(controller.liveCallIsActive).assertFalse();
      expect(controller.liveParticipantCount).assertEqual(0);
      expect(controller.liveLoadState).assertEqual('ready');
      expect(controller.shouldShow()).assertFalse();
      controller.dispose();
    });

    // 防的回归：置顶条数变少（管理员取消了几条置顶）之后 pinnedCycle 还停在旧
    // 下标，下一次点条会拿越界下标去索引 pinnedIds，取到 undefined。
    it('applyPinned 把 pinnedCycle 夹进 [0, count-1]（防的回归：取消置顶后轮转下标越界）', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());
      controller.pinnedCycle = 5;
      controller.pinnedJumpBusy = true;

      controller.applyPinned('第三条置顶', 3, 'ready');

      expect(controller.pinnedPreview).assertEqual('第三条置顶');
      expect(controller.pinnedCount).assertEqual(3);
      expect(controller.pinnedLoadState).assertEqual('ready');
      expect(controller.pinnedCycle).assertEqual(2);
      // count > 0 时不碰跳转守卫：正在进行的那一次跳转不能被一条订阅更新打断。
      expect(controller.pinnedJumpBusy).assertTrue();

      // 没越界的原样留着，别把用户翻到的位置顶回最新那条。
      controller.pinnedCycle = 1;
      controller.applyPinned('还是第三条置顶', 5, 'ready');
      expect(controller.pinnedCycle).assertEqual(1);
      controller.dispose();
    });

    // 防的回归：置顶被全部取消时 cycle 留着非零值、或者 pinnedJumpBusy 没人解——
    // 前者让下次有置顶时直接从中间那条开始转，后者把置顶条钉成"点不动"。
    it('置顶清空时 cycle 归零并解掉跳转守卫（防的回归：清空后置顶条永远点不动）', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());
      controller.pinnedCycle = 2;
      controller.pinnedJumpBusy = true;

      controller.applyPinned('', 0, 'ready');

      expect(controller.pinnedPreview).assertEqual('');
      expect(controller.pinnedCount).assertEqual(0);
      expect(controller.pinnedCycle).assertEqual(0);
      expect(controller.pinnedJumpBusy).assertFalse();
      controller.dispose();
    });

    // 防的回归：把"有 group call id"当成"在直播"。计划中的、以及刚结束的通话 id
    // 仍然挂在 chat.video_chat 上，只认 id 会让直播条常驻。
    it('shouldShow 真值表：置顶文案／已确认活跃的通话／骨架，三者之一才挂卡片', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());
      // 全新状态：什么都没有。
      expect(controller.shouldShow()).assertFalse();

      controller.pinnedPreview = '置顶了一条';
      expect(controller.shouldShow()).assertTrue();
      controller.pinnedPreview = '';
      expect(controller.shouldShow()).assertFalse();

      // 有 id 但没确认活跃（计划中的通话）→ 不显示。
      controller.liveGroupCallId = 3;
      expect(controller.shouldShow()).assertFalse();
      controller.liveCallIsActive = true;
      expect(controller.shouldShow()).assertTrue();
      // 通话结束把 id 抹掉，光留 isActive 也不显示。
      controller.liveGroupCallId = 0;
      expect(controller.shouldShow()).assertFalse();
      controller.liveCallIsActive = false;

      // 两边都还在拉的时候，卡片位置先由骨架占着。
      controller.topCardLoadingVisible = true;
      expect(controller.shouldShow()).assertTrue();
      controller.topCardLoadingVisible = false;
      expect(controller.shouldShow()).assertFalse();
      controller.dispose();
    });

    // 防的回归：评论区/话题视图根本没有置顶条，如果照普通会话那样先摆成
    // 'loading'，pinnedLoadState 就永远等不到那次 subscribePinned 回调，骨架会一直
    // 亮着（settleTopCardLoading 的两个条件里有一个永远不落定）。
    it('话题视图里置顶态直接算 ready，不先转一圈 loading（防的回归：评论区骨架不落定）', 0, (): void => {
      const threadHost: FakeHost = new FakeHost();
      threadHost.threadRootIdValue = 99;
      const inThread: LiveTopCardController = controllerOn(threadHost);
      inThread.pinnedPreview = '上一个会话的置顶';
      inThread.pinnedCount = 4;
      inThread.pinnedCycle = 3;
      inThread.liveGroupCallId = 7;
      inThread.liveCallIsActive = true;
      inThread.liveParticipantCount = 8;

      inThread.resetTopCardState();

      expect(inThread.pinnedLoadState).assertEqual('ready');
      // 顺带钉住 reset 是一次彻底清场：换会话时不许留上一间房的东西。
      expect(inThread.pinnedPreview).assertEqual('');
      expect(inThread.pinnedCount).assertEqual(0);
      expect(inThread.pinnedCycle).assertEqual(0);
      expect(inThread.liveGroupCallId).assertEqual(0);
      expect(inThread.liveCallIsActive).assertFalse();
      expect(inThread.liveParticipantCount).assertEqual(0);
      expect(inThread.liveLoadState).assertEqual('loading');

      const plainHost: FakeHost = new FakeHost();
      const inChat: LiveTopCardController = controllerOn(plainHost);
      inChat.resetTopCardState();
      expect(inChat.pinnedLoadState).assertEqual('loading');

      // reset 排了一个骨架定时器，用例结束前收掉，别漏给后面的测试。
      inThread.dispose();
      inChat.dispose();
    });

    // 防的回归：把 settleTopCardLoading 写成"只要有一边好了就收骨架"。那样置顶先
    // 回、直播还在拉的时候骨架会先塌一下再被直播条顶开，卡片高度抖两次。
    it('两边都落定才收骨架，error 也算落定（防的回归：卡片高度抖两次）', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());
      controller.topCardLoadingVisible = true;
      controller.pinnedLoadState = 'ready';
      controller.liveLoadState = 'loading';

      controller.settleTopCardLoading();
      expect(controller.topCardLoadingVisible).assertTrue();

      controller.liveLoadState = 'error';
      controller.settleTopCardLoading();
      expect(controller.topCardLoadingVisible).assertFalse();
      controller.dispose();
    });

    // 防的回归：给 applyLiveGroupCall 的缺失字段兜一个"保持原值"的底。TDLib 的
    // groupCall 在通话结束时不是把字段填成 false，是整个字段不出现——不兜成 false
    // 就等于结束之后横幅还亮着。
    it('applyLiveGroupCall 缺字段按"没有"算，不活跃时收掉脉冲与对话框忙标志', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());

      controller.applyLiveGroupCall(groupCallOf(true, true, 3));
      expect(controller.liveCallIsActive).assertTrue();
      expect(controller.liveCallIsRtmp).assertTrue();
      expect(controller.liveParticipantCount).assertEqual(3);
      expect(controller.liveLoadState).assertEqual('ready');

      controller.livePulseExpanded = true;
      controller.liveDialogOpening = true;
      const ended: TdObject = { '@type': 'groupCall' }; // 三个字段全缺
      controller.applyLiveGroupCall(ended);
      expect(controller.liveCallIsActive).assertFalse();
      expect(controller.liveCallIsRtmp).assertFalse();
      expect(controller.liveParticipantCount).assertEqual(0);
      // 通话没了，正在呼吸的脉冲和"正在弹确认框"的忙标志都要跟着落地。
      expect(controller.livePulseExpanded).assertFalse();
      expect(controller.liveDialogOpening).assertFalse();
      controller.dispose();
    });

    // 防的回归：把"ChatStore 缓存里这个会话没有通话"当成"通话结束了"。缓存未命中
    // 只是还没同步到，照它清一遍会把刚由 getChat 确认的直播抹掉。
    it('ChatEntry 快路径：缓存没通话不代表结束，同 id 已确认活跃则免一次往返', 0, (): void => {
      const missed: LiveTopCardController = controllerOn(new FakeHost());
      missed.liveGroupCallId = 42;
      missed.liveCallIsActive = true;
      missed.liveCallIsRtmp = true;
      missed.liveLoadState = 'ready';

      missed.syncLiveFromChatEntry(entryOf(0, false, false));

      expect(missed.liveGroupCallId).assertEqual(42);
      expect(missed.liveCallIsActive).assertTrue();
      expect(missed.liveLoadState).assertEqual('ready');

      // 同一个 id、ChatStore 那边已经确认 is_active：直接点亮，不等
      // getChat/getGroupCall 那一轮往返，否则进会话时直播条会先缺一拍。
      const fast: LiveTopCardController = controllerOn(new FakeHost());
      fast.liveGroupCallId = 42;
      fast.liveLoadState = 'loading';
      fast.syncLiveFromChatEntry(entryOf(42, true, true));
      expect(fast.liveCallIsActive).assertTrue();
      expect(fast.liveCallIsRtmp).assertTrue();
      expect(fast.liveLoadState).assertEqual('ready');

      missed.dispose();
      fast.dispose();
    });

    // 防的回归：把 chatId 的判空删掉。open() 排的那条 2s 轮询在路由还没落地时照样
    // 会 tick，没有这道短路就是每两秒一次 chat_id=0 的 getChat。
    it('chatId 还没落地时 refreshVideoChat 判 error 且不碰 TDLib（防的回归：chat_id=0 的轮询）', 0, (): void => {
      const host: FakeHost = new FakeHost(); // chatIdValue 仍是 0
      const controller: LiveTopCardController = controllerOn(host);

      // 不包 untilTdlibSend：真走到 getTdClient() 会抛，用例就红——这正是要钉的。
      controller.refreshVideoChat();

      expect(controller.liveLoadState).assertEqual('error');
      controller.dispose();
    });

    // 防的回归：进直播页前置上的两个忙标志没人清。它们是在离开页面前置上的，从
    // 直播页返回时那次导航早就结束了，不清就把横幅永久钉成"点不动"。
    // 注意今天只有"回到前台"这一侧清（handleShown 的 clearLiveNavigationBusy），
    // handleHidden / handleWillHide 一个字都不碰——所以控制器没有 onPageHidden()。
    it('onPageShown 清掉进直播页留下的忙标志（防的回归：返回后直播条永久点不动）', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());
      controller.liveDialogOpening = true;
      controller.liveNavigationBusy = true;

      controller.onPageShown();

      expect(controller.liveDialogOpening).assertFalse();
      expect(controller.liveNavigationBusy).assertFalse();
      controller.dispose();
    });

    // 防的回归：点置顶条时守卫没生效（连点两下发两次跳转），或者置顶已经空了还去
    // 发跳转。两支都不许惊动页面——host 的 5 个动作回调一次都不该被调到。
    it('点置顶条：守卫期内一动不动，置顶已空则只清横幅不跳转', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.storeValue = storeOf(); // 干净 store：getPinnedIds() 为空
      const controller: LiveTopCardController = controllerOn(host);
      controller.pinnedPreview = '旧的置顶';
      controller.pinnedCount = 1;
      controller.pinnedLoadState = 'ready';
      controller.pinnedJumpBusy = true;

      controller.onPinnedTap();
      expect(controller.pinnedPreview).assertEqual('旧的置顶');
      expect(controller.pinnedCount).assertEqual(1);
      expect(host.actionCalls()).assertEqual(0);

      controller.pinnedJumpBusy = false;
      controller.onPinnedTap();
      expect(controller.pinnedPreview).assertEqual('');
      expect(controller.pinnedCount).assertEqual(0);
      expect(host.actionCalls()).assertEqual(0);

      // 路由切换途中 store 可能为 null，这时候点一下也不能炸。
      host.storeValue = null;
      controller.pinnedPreview = '还没换完';
      controller.onPinnedTap();
      expect(controller.pinnedPreview).assertEqual('还没换完');
      expect(host.actionCalls()).assertEqual(0);
      controller.dispose();
    });

    // 防的回归：dispose 漏清 topCardLoadingTimer。这条是"先 ++seq 再清定时器"里
    // 定时器那一半的实测：resetTopCardState 排下的回调如果活过 dispose，就会往一个
    // 已经销毁的页面的 @Trace 上写字段（真机表现是返回后骨架又亮一下）。
    it('dispose 之后骨架定时器的回调写不进 @Trace（防的回归：销毁后回调仍写字段）', 0,
      async (): Promise<void> => {
        armPowerKeys();
        const controller: LiveTopCardController = controllerOn(new FakeHost());
        controller.resetTopCardState(); // 排下 TOP_CARD_LOADING_DELAY_MS 的骨架定时器
        controller.dispose();

        // 哨兵：回调若还活着，会算出 pinnedLoadState === 'loading' 而把它写回 true。
        controller.topCardLoadingVisible = false;
        await sleep(TOP_CARD_LOADING_DELAY_MS + 260);

        expect(controller.topCardLoadingVisible).assertFalse();
        expect(controller.pinnedLoadState).assertEqual('loading'); // 哨兵成立的前提没变
      });

    // 防的回归：780ms 脉冲的 clearInterval 漏了。这条心跳每翻一次就是一轮 @Trace
    // 通知，页面销毁后还在跳＝导航栈里每回退一层就多留一个心跳。
    // 前半段是阳性对照：不先证明它确实在跳，后半段的"没跳"就是句空断言。
    it('open 的 780ms 脉冲在 dispose 后停跳（防的回归：每回退一层多留一个心跳）', 0,
      async (): Promise<void> => {
        armPowerKeys();
        const host: FakeHost = new FakeHost(); // chatId 仍是 0：2s 那条 tick 碰不到 TDLib
        const controller: LiveTopCardController = controllerOn(host);
        controller.liveCallIsActive = true; // 脉冲只在直播亮着时翻转
        controller.open();

        await sleep(900);
        expect(controller.livePulseExpanded).assertTrue(); // 阳性对照：翻过一次

        controller.dispose();
        controller.livePulseExpanded = true; // 哨兵：心跳还活着就会把它翻成 false
        await sleep(900);
        expect(controller.livePulseExpanded).assertTrue();
      });

    // 防的回归：dispose 只清定时器、不动在途记账。两个 seq 是私有的（见文件头限制
    // 2），这里验的是它们的同伴 liveGroupRefreshInFlight / liveGroupRequestId：
    // dispose 之后不该还留着一趟"在途请求"的记账，否则同一个 id 的新请求会被去重
    // 守卫吃掉，直播条再也不刷新。
    it('dispose 清空在途记账，旧的那趟请求认领不了这个控制器', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: LiveTopCardController = controllerOn(host);
      controller.liveGroupCallId = 7;

      // 第一趟：发出去了（loadState 被写成 loading 就是它走完了同步段的证据）。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });
      expect(controller.liveLoadState).assertEqual('loading');

      // 第二趟同 id：去重守卫直接 return，什么都不写。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });
      expect(controller.liveLoadState).assertEqual('ready');

      // dispose 之后同 id 再来：记账已清空，重新发得出去。
      controller.dispose();
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });
      expect(controller.liveLoadState).assertEqual('loading');
      controller.dispose();
    });

    // 【B5 复盘补的两条】搬迁时这两个入口一度被拆散：页面侧只留了"应用推送内容"
    // 那半截，而 seq 自增与 in-flight 复位（作废在途请求的那半截）因为字段变成了
    // 控制器 private 而被删成注释。编译过、单测全绿、静态检查也看不出来——它只在
    // "推送先到、请求后回"的时序下才发作。这两条就是钉住这个时序的。
    // seq 那一半（迟到响应被判过期）受限于文件头限制 2 断言不到；in-flight 那一半
    // 可以，判据是「在途标志会挡掉下一次请求」这条可观测副作用：refreshVideoChat
    // 在 liveChatRefreshInFlight 为真时直接 return，什么都不写。
    it('updateChatVideoChat 到达时放开在途的 getChat 记账', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: LiveTopCardController = controllerOn(host);

      // 第一趟发出去：showLoading 且通话未确认活跃 → 写 loading，记上在途。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.refreshVideoChat(true); });
      expect(controller.liveLoadState).assertEqual('loading');

      // 第二趟被在途标志挡住：一个字都不写，loadState 停在原地。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.refreshVideoChat(true); });
      expect(controller.liveLoadState).assertEqual('ready');

      // 推送到达。id 传 0 走「通话结束」那支，不会再发请求。
      untilTdlibSend((): void => { controller.applyVideoChatUpdate(0); });
      expect(controller.liveGroupCallId).assertEqual(0);

      // 记账被放开的证据：现在还发得出去。**这条就是回退检测器**——搬迁时
      // liveChatRefreshInFlight = false 曾被删成注释，那时这里会停在 'ready'。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.refreshVideoChat(true); });
      expect(controller.liveLoadState).assertEqual('loading');
      controller.dispose();
    });

    it('updateGroupCall 到达时放开在途的 getGroupCall 记账，并应用推送内容', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: LiveTopCardController = controllerOn(host);

      // 第一趟：换 id 会走完同步段并记上在途（liveGroupRequestId = 7）。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });
      expect(controller.liveLoadState).assertEqual('loading');

      // 同 id 再来：被 (in-flight && requestId === id) 去重守卫挡住。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });
      expect(controller.liveLoadState).assertEqual('ready');

      // 推送到达：内容照单全收，同时放开在途记账。这里刻意用「通话已结束」的
      // 快照——留着 liveCallIsActive=false，下一步才观测得到 loading。
      untilTdlibSend((): void => {
        controller.applyGroupCallUpdate(groupCallOf(false, false, 0));
      });
      expect(controller.liveCallIsActive).assertFalse();
      expect(controller.liveLoadState).assertEqual('ready');

      // 记账被放开的证据：**同一个 id**（changed 为假，走不到那条重置路径）现在
      // 重新发得出去，不再被 (in-flight && requestId === id) 挡住。
      // **这条就是回退检测器**——搬迁时 liveGroupRefreshInFlight = false 与
      // liveGroupRequestId = 0 曾被删成注释，那时这里会停在 'ready'。
      controller.liveLoadState = 'ready';
      untilTdlibSend((): void => { controller.setLiveGroupCallId(7); });
      expect(controller.liveGroupCallId).assertEqual(7);
      expect(controller.liveLoadState).assertEqual('loading');

      // 顺带钉住推送内容确实被应用了（活跃的那一支）。
      untilTdlibSend((): void => {
        controller.applyGroupCallUpdate(groupCallOf(true, true, 12));
      });
      expect(controller.liveCallIsActive).assertTrue();
      expect(controller.liveCallIsRtmp).assertTrue();
      expect(controller.liveParticipantCount).assertEqual(12);
      controller.dispose();
    });

    // 防的回归：dispose 漏掉某个忙标志。它们全是"某次异步动作正在进行"的记号，只有
    // 对应的回调会清；页面销毁时那些回调已经作废了，不在这里清就没人清。
    it('dispose 把忙标志清成静止值，且允许重复调用', 0, (): void => {
      const controller: LiveTopCardController = controllerOn(new FakeHost());
      controller.liveDialogOpening = true;
      controller.liveNavigationBusy = true;
      controller.pinnedJumpBusy = true;
      controller.topCardLoadingVisible = true;

      controller.dispose();
      expect(controller.liveDialogOpening).assertFalse();
      expect(controller.liveNavigationBusy).assertFalse();
      expect(controller.pinnedJumpBusy).assertFalse();
      expect(controller.topCardLoadingVisible).assertFalse();

      // aboutToDisappear 可能与别的清理路径撞上，第二次调用必须是无害的。
      controller.dispose();
      expect(controller.liveDialogOpening).assertFalse();
      expect(controller.topCardLoadingVisible).assertFalse();
    });

    // 防的回归：有人把控制器做成模块级单例。平板分栏、导航栈多层时同时活着多个
    // ChatPage，共用一份状态就是 A 会话的置顶条出现在 B 会话头上、B 的 dispose 把
    // A 的横幅一起清掉。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份横幅）', 0, (): void => {
      const hostA: FakeHost = new FakeHost();
      hostA.chatIdValue = 100;
      const hostB: FakeHost = new FakeHost();
      hostB.chatIdValue = 200;
      const a: LiveTopCardController = controllerOn(hostA);
      const b: LiveTopCardController = controllerOn(hostB);

      a.pinnedPreview = '会话 A 的置顶';
      a.pinnedCount = 2;
      a.pinnedCycle = 1;
      a.liveGroupCallId = 11;
      a.liveCallIsActive = true;
      a.livePulseExpanded = true;

      expect(b.pinnedPreview).assertEqual('');
      expect(b.pinnedCount).assertEqual(0);
      expect(b.pinnedCycle).assertEqual(0);
      expect(b.liveGroupCallId).assertEqual(0);
      expect(b.liveCallIsActive).assertFalse();
      expect(b.livePulseExpanded).assertFalse();
      expect(a.shouldShow()).assertTrue();
      expect(b.shouldShow()).assertFalse();

      // 一页销毁不能把另一页的状态一起清掉。
      b.liveNavigationBusy = true;
      b.pinnedJumpBusy = true;
      a.dispose();
      expect(b.liveNavigationBusy).assertTrue();
      expect(b.pinnedJumpBusy).assertTrue();
      expect(b.pinnedPreview).assertEqual('');
      expect(a.liveNavigationBusy).assertFalse();
      b.dispose();
    });
  });
}
