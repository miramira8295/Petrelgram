import { describe, expect, it } from '@ohos/hypium';
import { MembershipSession, MembershipSessionHost } from '../main/ets/pages/chat/MembershipSession';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';

// 成员资格状态机控制器（R2-A 从 ChatPage 整体搬出）的断言。写法照抄
// ComposerSuggestionState.test.ets：FakeHost、一个 FakeBridge 撑起来的**真**
// TdClient（控制器已经留了 client 注入缝，见 MembershipSession.ets 文件头
// 【client() 注入缝】一节，本批一开始就这么写，不是验收时补的）。
//
// 本文件的核心是 membershipSeq 三层取消令牌（refresh() 文件头【乙】一节列的
// 6 处比较）：换会话会让 membershipSeq 再自增一次，无论旧响应卡在哪一层，
// 回来时都应该被对应那一层的比较挡住。下面每条守卫用例都配一段"阳性对照"——
// 先证明同一轮的响应确实会写，再证明换轮之后旧响应不会写。理由见任务说明：
// 光有守卫生效的那一半，删掉整段守卫也可能全绿。
//
// 覆盖不到的部分记在文件尾 skippedAreas 对应的注释里（本文件只用注释标记，
// 不引入新概念）：
//   - subscribeMembershipUpdates 的 updateSupergroup/updateBasicGroup 推送
//     监听器不属于本批范围（未随本批迁移，仍在 ChatPage），因此
//     supergroupId()/basicGroupId() 只测"refresh() 写对了值"，不测推送匹配。
//   （验收更正：原来这里还写着一条“chatTypeBasicGroup 分支与 supergroup 分支
//   逐字对称，故不重复镜像”的跳过理由。那个理由不成立——方案 §2 不变量 4 明文
//   写着“镜像判据不是重复代码”，而镜像分支恰恰是复制粘贴错误唯一的栖息地。
//   cmp-4/cmp-5 两条已补齐，见下方 basicGroup 那两条用例。）

// 用一个假桥撑起一个**真** TdClient，形状照抄 ComposerSuggestionState.test.ets
// 的 FakeBridge/WiredClient。
class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

class WiredClient {
  bridge: FakeBridge = new FakeBridge();
  client: TdClient;

  constructor() {
    this.client = new TdClient(this.bridge);
    this.client.start();
  }

  // 按 @extra 把第 index 条在途请求应答掉。payload 是响应体（不含 @extra）。
  respond(index: number, payload: TdObject): void {
    const sent: TdObject = JSON.parse(this.bridge.sent[index]) as TdObject;
    payload['@extra'] = sent['@extra'] as Object;
    this.bridge.onReceive(JSON.stringify(payload));
  }

  // 第 index 条在途请求发的是什么方法。
  methodOf(index: number): string {
    const sent: TdObject = JSON.parse(this.bridge.sent[index]) as TdObject;
    return sent['@type'] as string;
  }

  // 第 index 条在途请求的完整请求体。验收时补的：三处 id 装填
  // （req['chat_id'] / groupReq['supergroup_id'] / groupReq['basic_group_id']）
  // 原本一条断言都没有——methodOf 只读 @type，把 chat_id 改成 0 全部用例照样绿。
  // 而"拿 chat 找 group、拿 group id 发第二跳、再拿它匹配推送"正是这一簇的
  // 全部工作内容。
  payloadOf(index: number): TdObject {
    return JSON.parse(this.bridge.sent[index]) as TdObject;
  }
}

class MembershipFakeHost implements MembershipSessionHost {
  chatIdValue: number = 0;
  chatIdCalls: number = 0;
  isChannelValue: boolean = false;
  isChannelCalls: number = 0;
  membershipStateValue: string = 'initial';
  setMembershipStateCalls: string[] = [];
  isGroupValue: boolean = false;
  setIsGroupCalls: boolean[] = [];
  isChannelSetValue: boolean = false;
  setIsChannelCalls: boolean[] = [];
  commitTimelineSnapshotCalls: number = 0;
  joiningChatValue: boolean = true;
  setJoiningChatCalls: boolean[] = [];
  closeComposerSurfacesCalls: number = 0;
  // 共享调用顺序日志。验收时从"只记四个"扩到记全部六个回调：applyStatus 里
  // setMembershipState → setJoiningChat(false) → closeComposerSurfaces() 这条
  // 次序原本没有任何断言钉住（三条计数断言与顺序无关，把三步颠倒过来照样绿），
  // 而 HEAD 那句英文注释 "Close every composer-owned surface before replacing
  // the bar" 描述的正是这条时序契约。
  orderLog: string[] = [];

  chatId: () => number = (): number => {
    this.chatIdCalls++;
    return this.chatIdValue;
  };
  isChannel: () => boolean = (): boolean => {
    this.isChannelCalls++;
    return this.isChannelValue;
  };
  setMembershipState: (next: string) => void = (next: string): void => {
    this.setMembershipStateCalls.push(next);
    this.membershipStateValue = next;
    this.orderLog.push(`setMembershipState:${next}`);
  };
  setIsGroup: (value: boolean) => void = (value: boolean): void => {
    this.setIsGroupCalls.push(value);
    this.isGroupValue = value;
    this.orderLog.push(`setIsGroup:${value}`);
  };
  setIsChannel: (value: boolean) => void = (value: boolean): void => {
    this.setIsChannelCalls.push(value);
    this.isChannelSetValue = value;
    this.orderLog.push(`setIsChannel:${value}`);
  };
  commitTimelineSnapshot: () => void = (): void => {
    this.commitTimelineSnapshotCalls++;
    this.orderLog.push('commitTimelineSnapshot');
  };
  setJoiningChat: (value: boolean) => void = (value: boolean): void => {
    this.setJoiningChatCalls.push(value);
    this.joiningChatValue = value;
    this.orderLog.push(`setJoiningChat:${value}`);
  };
  closeComposerSurfaces: () => void = (): void => {
    this.closeComposerSurfacesCalls++;
    this.orderLog.push('closeComposerSurfaces');
  };
  wired: WiredClient = new WiredClient();
  clientCalls: number = 0;
  client: () => TdClient = (): TdClient => {
    this.clientCalls++;
    return this.wired.client;
  };
}

function membershipControllerOn(host: MembershipFakeHost): MembershipSession {
  const controller: MembershipSession = new MembershipSession();
  controller.bind(host);
  return controller;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

// ——— getChat 响应体构造：只需要 type['@type'] 这一层，其余字段按分支需要现搭 ———

function supergroupChat(supergroupId: number, isChannel: boolean = false): TdObject {
  const type: TdObject = { '@type': 'chatTypeSupergroup' };
  type['supergroup_id'] = supergroupId;
  type['is_channel'] = isChannel;
  const chat: TdObject = { '@type': 'chat' };
  chat['type'] = type;
  return chat;
}

function basicGroupChat(basicGroupId: number): TdObject {
  const type: TdObject = { '@type': 'chatTypeBasicGroup' };
  type['basic_group_id'] = basicGroupId;
  const chat: TdObject = { '@type': 'chat' };
  chat['type'] = type;
  return chat;
}

function privateChat(): TdObject {
  const type: TdObject = { '@type': 'chatTypePrivate' };
  const chat: TdObject = { '@type': 'chat' };
  chat['type'] = type;
  return chat;
}

function secretChat(): TdObject {
  const type: TdObject = { '@type': 'chatTypeSecret' };
  const chat: TdObject = { '@type': 'chat' };
  chat['type'] = type;
  return chat;
}

// getSupergroup/getBasicGroup 响应体：只需要 status 这一层。
function groupResponseWithStatus(statusType: string, isMember: boolean = false, canPost: boolean = false): TdObject {
  const rights: TdObject = { '@type': 'chatAdministratorRights' };
  rights['can_post_messages'] = canPost;
  const status: TdObject = { '@type': statusType };
  status['is_member'] = isMember;
  status['rights'] = rights;
  const res: TdObject = { '@type': 'supergroupFullInfoIsh' };
  res['status'] = status;
  return res;
}

// applyStatus() 直接测试用的 status 对象（与上面 groupResponseWithStatus 内层
// 的 status 同一形状，单独抽出来是因为直接调 applyStatus 不需要外层 res 包装）。
function statusOf(statusType: string, isMember: boolean = false, canPost: boolean = false): TdObject {
  const rights: TdObject = { '@type': 'chatAdministratorRights' };
  rights['can_post_messages'] = canPost;
  const status: TdObject = { '@type': statusType };
  status['is_member'] = isMember;
  status['rights'] = rights;
  return status;
}

function tdError(code: number, message: string): TdObject {
  const err: TdObject = { '@type': 'error' };
  err['code'] = code;
  err['message'] = message;
  return err;
}

export default function membershipSessionTest() {
  describe('MembershipSession', () => {

    // ========================================================================
    // membershipSeq —— 三层取消令牌（refresh() 文件头【乙】一节，6 处比较）
    // ========================================================================

    // 钉 cmp-1：最外层 getChat().then 开头的 `if (seq !== this.membershipSeq) return;`
    // （MembershipSession.ets:212）。
    // 阳性对照在同一条用例里：先证明"当前那轮"的响应确实会写 writable
    // （chatTypePrivate 落进兜底分支，typeName!=='chatTypeSecret' 时写 writable），
    // 再证明"陈旧那轮"的同款响应被丢弃。
    it('refresh()：外层 getChat().then——连发两次，只应答先发的那条，陈旧响应被 membershipSeq 丢弃', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        controller.refresh(); // seq=1，getChat idx0（这条将成为陈旧的那个）
        controller.refresh(); // seq=2，getChat idx1（当前有效）
        expect(host.wired.bridge.sent.length).assertEqual(2);

        host.membershipStateValue = 'sentinel'; // 哨兵：面板当前显示的值

        host.wired.respond(0, privateChat()); // 只应答第 1 次（已过期）
        await sleep(0);

        // 守卫在：哨兵原样留着（cmp-1 挡住，连 typeName 分支都没进去）。
        expect(host.membershipStateValue).assertEqual('sentinel');

        // 阳性对照：应答第 2 次（当前），确实会写 writable——证明上面那句
        // "哨兵没变"不是因为响应本身天生不会写，而是守卫真的生效了。
        host.wired.respond(1, privateChat());
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('writable');
      });

    // 钉 cmp-6：最外层 getChat().catch 里的 `if (seq === this.membershipSeq)`
    // （MembershipSession.ets:267）。同样先给阳性对照，再给守卫用例。
    it('refresh()：外层 getChat().catch——换会话后，旧的失败响应不该写 writable', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 阳性对照：单独一轮，getChat 本身失败，确实会写 writable。
        controller.refresh(); // seq=1, idx0
        host.wired.respond(0, tdError(500, 'boom'));
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('writable');

        // 换两轮：第 2 次 refresh 还没等到响应，就因为换会话触发第 3 次。
        controller.refresh(); // seq=2, idx1（这条将成为陈旧的那个）
        controller.refresh(); // seq=3, idx2（当前，不在本用例里应答）
        host.membershipStateValue = 'sentinel';

        host.wired.respond(1, tdError(500, 'boom')); // 陈旧的失败响应
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 守卫在，未被覆盖
      });

    // 钉 cmp-2/cmp-3：chatTypeSupergroup 分支内层 getSupergroup().then/.catch
    // 的 `if (seq === this.membershipSeq)`（MembershipSession.ets:227/231）。
    it('refresh()：内层 getSupergroup().then——getChat 应答后换会话，旧的 getSupergroup 成功响应不该写', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 阳性对照：完整走一轮，证明 getSupergroup().then 确实会经 applyStatus
        // 写 membershipState。
        controller.refresh(); // seq=1, getChat idx0
        host.wired.respond(0, supergroupChat(10));
        await sleep(0);
        expect(host.wired.methodOf(1)).assertEqual('getSupergroup');
        expect(host.membershipStateValue).assertEqual('checking');
        host.wired.respond(1, groupResponseWithStatus('chatMemberStatusMember', true));
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('writable'); // 阳性对照成立

        // 换一轮：getChat 应答后进入 supergroup 分支、getSupergroup 还没回来，
        // 此时换会话（再 refresh 一次）。旧的 getSupergroup 响应现在应该作废。
        controller.refresh(); // seq=2, getChat idx2
        host.wired.respond(2, supergroupChat(20));
        await sleep(0);
        expect(host.wired.methodOf(3)).assertEqual('getSupergroup');

        host.membershipStateValue = 'sentinel'; // 哨兵：这轮 checking 之后的当前值
        controller.refresh(); // seq=3，换会话——idx3 归属的 seq=2 已过期，不应答它的 getChat

        host.wired.respond(3, groupResponseWithStatus('chatMemberStatusMember', true)); // 陈旧
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 守卫在：哨兵未被覆盖
      });

    it('refresh()：内层 getSupergroup().catch——getChat 应答后换会话，旧的 getSupergroup 失败响应不该写 writable', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 阳性对照：完整走一轮，证明 getSupergroup().catch 确实会写 writable。
        controller.refresh(); // seq=1, getChat idx0
        host.wired.respond(0, supergroupChat(10));
        await sleep(0);
        host.wired.respond(1, tdError(404, 'no such supergroup'));
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('writable'); // 阳性对照成立

        // 换一轮，制造同样的"内层还没回来就换会话"局面，这次用失败响应。
        controller.refresh(); // seq=2, getChat idx2
        host.wired.respond(2, supergroupChat(20));
        await sleep(0);
        expect(host.wired.methodOf(3)).assertEqual('getSupergroup');

        host.membershipStateValue = 'sentinel';
        controller.refresh(); // seq=3，换会话

        host.wired.respond(3, tdError(404, 'no such supergroup')); // 陈旧的失败响应
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 守卫在：未被写成 writable
      });


    // 钉 cmp-4/cmp-5：chatTypeBasicGroup 分支内层 getBasicGroup().then/.catch
    // 的两道 `if (seq === this.membershipSeq)`。
    //
    // 【为什么非镜像不可——验收时补的】原来这两条被写进 skippedAreas，理由是
    // "与 supergroup 分支代码逐字对称，判断为同构风险，不重复镜像"。这个理由
    // 不成立，而且正是方案 §2 不变量 4 明文否掉的那种推理（"2625–2666 与
    // 2680–2719 是**镜像判据不是重复代码**，不合并"）。镜像分支恰恰是复制粘贴
    // 错误唯一的栖息地：basicGroup 分支里若把 `basic_group_id` 误写成
    // `this.membershipSupergroupId`，或两道守卫漏掉一道，supergroup 那两条
    // 用例一条都不会红。而且这不是环境限制——注入缝已经开好、basicGroupChat()
    // 辅助函数就摆在上面。
    it('refresh()：内层 getBasicGroup().then——getChat 应答后换会话，旧的成功响应不该写', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 阳性对照：完整走一轮。
        controller.refresh(); // seq=1, getChat idx0
        host.wired.respond(0, basicGroupChat(10));
        await sleep(0);
        expect(host.wired.methodOf(1)).assertEqual('getBasicGroup');
        expect(host.membershipStateValue).assertEqual('checking');
        host.wired.respond(1, groupResponseWithStatus('chatMemberStatusMember', true));
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('writable'); // 阳性对照成立

        // 换一轮：getBasicGroup 还没回来时换会话。
        controller.refresh(); // seq=2, getChat idx2
        host.wired.respond(2, basicGroupChat(20));
        await sleep(0);
        expect(host.wired.methodOf(3)).assertEqual('getBasicGroup');

        host.membershipStateValue = 'sentinel';
        controller.refresh(); // seq=3，把 idx3 那一轮作废

        host.wired.respond(3, groupResponseWithStatus('chatMemberStatusMember', true)); // 陈旧
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 守卫在
      });

    it('refresh()：内层 getBasicGroup().catch——换会话后旧的失败响应不该写 writable', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 阳性对照：自己那一轮的失败响应确实会写 writable。
        controller.refresh(); // seq=1
        host.wired.respond(0, basicGroupChat(10));
        await sleep(0);
        host.wired.respond(1, tdError(404, 'no such basic group'));
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('writable'); // 阳性对照成立

        controller.refresh(); // seq=2
        host.wired.respond(2, basicGroupChat(20));
        await sleep(0);

        host.membershipStateValue = 'sentinel';
        controller.refresh(); // seq=3，作废上一轮

        host.wired.respond(3, tdError(404, 'no such basic group')); // 陈旧的失败响应
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 守卫在：未被写成 writable
      });

    // ========================================================================
    // 密聊特例：typeName !== 'chatTypeSecret'（MembershipSession.ets:263）
    // ========================================================================

    // 防的回归：这道判据被删掉或反过来——密聊会被无条件写 writable，冲掉
    // applySecretChat 刚设好的"待建立/已关闭故不可发"状态。阳性对照见上面
    // 「外层 getChat().then」用例：同样的兜底分支，privateChat() 确实会写
    // writable；这里换成 secretChat() 验证它被摘出去、不写。
    it('refresh()：chatTypeSecret 分支不写 writable，把 supergroupId/basicGroupId 清零但不动 membershipState', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);
        host.membershipStateValue = 'sentinel'; // 模拟 applySecretChat 刚设好的值

        // 先跑一轮把 supergroupId 写成非零——否则下面那两条清零断言是空的
        // （字段从构造起就是 0，删掉清零赋值也一样绿）。
        controller.refresh();
        host.wired.respond(0, supergroupChat(42));
        await sleep(0);
        expect(controller.supergroupId()).assertEqual(42); // 前提已建立
        host.membershipStateValue = 'sentinel'; // 上一轮把它写成了 checking，重置

        controller.refresh();
        host.wired.respond(2, secretChat());
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 未被冲掉
        expect(controller.supergroupId()).assertEqual(0); // 这一轮真的清掉了
        expect(controller.basicGroupId()).assertEqual(0);
      });

    // ========================================================================
    // refresh() 的分支细节：supergroupId/basicGroupId 互斥写、host 回调顺序
    // ========================================================================

    // 防的回归：私有化后 subscribeMembershipUpdates 的推送匹配读点丢失
    // （B5/B8 栽过的坑）——补的两个只读取值器必须原样取回 refresh() 写的值。
    // 【验收时改过：原来这三条"互斥清零"断言是表演性的】
    // 断言的那个字段在用例里从没被置成非零，所以它们声称要防的清零赋值删掉
    // 之后照样全绿（真破验证过）。互斥这件事是有语义的：残留的旧 id 会让
    // subscribeMembershipUpdates 的 updateSupergroup/updateBasicGroup 推送
    // 继续匹配上**旧群**，把别的群的 status 喂进 applyStatus。
    // 改法：先跑一轮把对侧 id 写成非零，再验它被清掉。
    it('refresh()：chatTypeSupergroup 分支写 supergroupId，清掉上一轮的 basicGroupId（互斥）', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 前提：先让 basicGroupId 非零。
        controller.refresh();
        host.wired.respond(0, basicGroupChat(99));
        await sleep(0);
        expect(controller.basicGroupId()).assertEqual(99);

        controller.refresh();
        host.wired.respond(2, supergroupChat(42));
        await sleep(0);

        expect(controller.supergroupId()).assertEqual(42);
        expect(controller.basicGroupId()).assertEqual(0); // 上一轮那个真的被清了

        // 出站请求体的 id 装填：methodOf 只读 @type，这三处原本零覆盖。
        expect(host.wired.payloadOf(2)['chat_id']).assertEqual(1);
        expect(host.wired.payloadOf(3)['supergroup_id']).assertEqual(42);
      });

    it('refresh()：chatTypeBasicGroup 分支写 basicGroupId，清掉上一轮的 supergroupId（互斥）', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        // 前提：先让 supergroupId 非零（理由见上一条用例上方的说明）。
        controller.refresh();
        host.wired.respond(0, supergroupChat(42));
        await sleep(0);
        expect(controller.supergroupId()).assertEqual(42);

        controller.refresh();
        host.wired.respond(2, basicGroupChat(99));
        await sleep(0);

        expect(controller.basicGroupId()).assertEqual(99);
        expect(controller.supergroupId()).assertEqual(0); // 上一轮那个真的被清了
        expect(host.isGroupValue).assertTrue();
        expect(host.isChannelSetValue).assertFalse(); // basicGroup 分支无条件写 false

        // 第二跳的 id 装填。
        expect(host.wired.payloadOf(3)['basic_group_id']).assertEqual(99);
      });

    // 防的回归：写 membershipState='checking' 之前先调用 commitTimelineSnapshot()
    // 这条固定顺序被打乱（MembershipSession.ets:220-223，文件头注释明确"顺序
    // 固定，不可颠倒"）。用共享的 orderLog 钉住四次 host 回调的相对次序。
    it('refresh()：chatTypeSupergroup 分支里 host 回调顺序固定为 setIsGroup→setIsChannel→commitTimelineSnapshot→setMembershipState(checking)', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        controller.refresh();
        host.wired.respond(0, supergroupChat(10, false)); // 显式带 is_channel:false，不触发 ?? 回退
        await sleep(0);

        expect(host.orderLog).assertDeepEquals([
          'setIsGroup:true',
          'setIsChannel:false',
          'commitTimelineSnapshot',
          'setMembershipState:checking'
        ]);
      });

    // 阳性对照：supergroup 分支 is_channel 缺省时回退读 host.isChannel()
    // （`?? this.host.isChannel()`）。不给 chat.type 带 is_channel 字段，
    // 观察写回去的值等于 host 当时的 isChannel()。
    it('refresh()：chatTypeSupergroup 分支 is_channel 缺省时，回退读 host.isChannel() 当前值', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        host.isChannelValue = true;
        const controller: MembershipSession = membershipControllerOn(host);

        const type: TdObject = { '@type': 'chatTypeSupergroup' };
        type['supergroup_id'] = 10; // 故意不写 is_channel
        const chat: TdObject = { '@type': 'chat' };
        chat['type'] = type;

        controller.refresh();
        host.wired.respond(0, chat);
        await sleep(0);

        expect(host.isChannelSetValue).assertTrue(); // 回退到了 host.isChannel()==true
      });

    // ========================================================================
    // applyStatus()：type==='' 早退 + membershipStateOf 的结果被写给 host
    // （membershipStateOf 本身的各档判定已在 util/MembershipState 有单测，
    // 这里只钉"控制器把结果转交给了 host.setMembershipState"这一层转发）
    // ========================================================================

    // 防的回归：早退判据（status 为 undefined，或 status['@type'] 为空串）被
    // 削弱——不该在没有真实状态时改写 membershipState 或碰 composer 四域。
    it('applyStatus：status 为 undefined 或 @type 为空串时早退，不碰 membershipState/joiningChat/composer', 0, (): void => {
      const host: MembershipFakeHost = new MembershipFakeHost();
      const controller: MembershipSession = membershipControllerOn(host);
      host.membershipStateValue = 'sentinel';

      const emptyType: TdObject = { '@type': '' };
      controller.applyStatus(undefined);
      controller.applyStatus(emptyType);

      expect(host.membershipStateValue).assertEqual('sentinel');
      expect(host.setMembershipStateCalls).assertDeepEquals([]);
      expect(host.setJoiningChatCalls).assertDeepEquals([]);
      expect(host.closeComposerSurfacesCalls).assertEqual(0);
    });

    // 防的回归：writable 分支（!membershipLosesComposer）本该早退，却仍然
    // 调用了 closeComposerSurfaces——早退是为了不必要地打断组合面板。
    it("applyStatus：判定为 'writable' 时早退——只置 joiningChat=false，不调用 closeComposerSurfaces", 0, (): void => {
      const host: MembershipFakeHost = new MembershipFakeHost();
      const controller: MembershipSession = membershipControllerOn(host);
      host.joiningChatValue = true;

      // chatMemberStatusCreator 落进 membershipStateOf 的兜底分支 → writable。
      controller.applyStatus(statusOf('chatMemberStatusCreator'));

      expect(host.setMembershipStateCalls).assertDeepEquals(['writable']);
      expect(host.setJoiningChatCalls).assertDeepEquals([false]);
      expect(host.closeComposerSurfacesCalls).assertEqual(0);
    });

    // 防的回归：非 writable 分支忘了调用 closeComposerSurfaces，或者把
    // setJoiningChat(false) 漏掉/调用了两次（两处调用点独立，各自只应触发一次）。
    it("applyStatus：判定为非 'writable' 时，置 joiningChat=false 且调用一次 closeComposerSurfaces", 0, (): void => {
      const host: MembershipFakeHost = new MembershipFakeHost();
      const controller: MembershipSession = membershipControllerOn(host);

      // chatMemberStatusLeft → joinable（丢composer）。
      controller.applyStatus(statusOf('chatMemberStatusLeft'));

      expect(host.setMembershipStateCalls).assertDeepEquals(['joinable']);
      expect(host.setJoiningChatCalls).assertDeepEquals([false]);
      expect(host.closeComposerSurfacesCalls).assertEqual(1);
      // 三步的**次序**：上面三条都是计数/内容断言，与顺序无关，把三步颠倒过来
      // 照样绿。HEAD 那句英文注释 “Close every composer-owned surface before
      // replacing the bar” 描述的正是这条时序契约，用 orderLog 钉住。
      expect(host.orderLog).assertDeepEquals(
        ['setMembershipState:joinable', 'setJoiningChat:false', 'closeComposerSurfaces']);
    });

    // 防的回归：applyStatus 拼 membershipStateOf 入参时，isChannel 用的是缓存值
    // 而不是每次现取 host.isChannel()——这里在同一个 controller 上先后用两种
    // isChannelValue 各调一次，证明两次读到的是当时的真值，不是构造时的快照。
    it('applyStatus：isChannel 现取 host.isChannel()，不缓存', 0, (): void => {
      const host: MembershipFakeHost = new MembershipFakeHost();
      const controller: MembershipSession = membershipControllerOn(host);

      host.isChannelValue = false;
      controller.applyStatus(statusOf('chatMemberStatusMember'));
      expect(host.setMembershipStateCalls[0]).assertEqual('writable'); // 超级群普通成员

      host.isChannelValue = true;
      controller.applyStatus(statusOf('chatMemberStatusMember'));
      expect(host.setMembershipStateCalls[1]).assertEqual('readonly'); // 频道订阅者只读
    });

    // ========================================================================
    // dispose()：只做 membershipSeq++，不新增清理
    // ========================================================================

    // membershipSeq 是私有字段、没有读口子，只能通过它的效果观察：dispose()
    // 应该让此刻仍在途的 refresh() 三层响应全部作废，与"页面销毁前又调了一次
    // refresh()"等价；同时 supergroupId()/basicGroupId() 不应该被 dispose()
    // 顺手清零（原 aboutToDisappear 全链路从未清过它们，见 MembershipSession.ets
    // 文件头【dispose()】一节）。
    it('dispose()：使在途的 getSupergroup 响应作废，且不清零 supergroupId', 0,
      async (): Promise<void> => {
        const host: MembershipFakeHost = new MembershipFakeHost();
        host.chatIdValue = 1;
        const controller: MembershipSession = membershipControllerOn(host);

        controller.refresh();
        host.wired.respond(0, supergroupChat(10));
        await sleep(0);
        expect(host.membershipStateValue).assertEqual('checking');

        host.membershipStateValue = 'sentinel';
        controller.dispose(); // membershipSeq++，此刻在途的 getSupergroup(idx1) 归属旧 seq

        host.wired.respond(1, groupResponseWithStatus('chatMemberStatusMember', true));
        await sleep(0);

        expect(host.membershipStateValue).assertEqual('sentinel'); // 未被作废的响应覆盖
        expect(controller.supergroupId()).assertEqual(10); // dispose() 没有顺手清零
      });

    // ========================================================================
    // 实例隔离：per-ChatPage 字段初始化器 new，不是模块级单例
    // ========================================================================

    it('两个 MembershipSession 实例互不影响：各自的 supergroupId 与在途请求互不干扰', 0,
      async (): Promise<void> => {
        const hostA: MembershipFakeHost = new MembershipFakeHost();
        hostA.chatIdValue = 1;
        const hostB: MembershipFakeHost = new MembershipFakeHost();
        hostB.chatIdValue = 2;
        const a: MembershipSession = membershipControllerOn(hostA);
        const b: MembershipSession = membershipControllerOn(hostB);

        a.refresh();
        hostA.wired.respond(0, supergroupChat(77));
        await sleep(0);

        expect(a.supergroupId()).assertEqual(77);
        expect(b.supergroupId()).assertEqual(0); // b 未受影响
        expect(hostB.wired.bridge.sent.length).assertEqual(0); // a.refresh() 没有污染 b 的客户端
      });

    // 【验收时补的：上一条盖不住 membershipSeq 的隔离】
    // 上一条只验了两个 id 与两个客户端互不干扰。把 membershipSeq 做成模块级共享
    // （两个实例读写同一个计数器）之后，上一条照样全绿——真破验证过。
    //
    // 但 seq 共享是**真 bug**：平板分栏时两个 ChatPage 同时活着，B 页的一次
    // refresh() 会把共享计数器推高，A 页那条还在途的请求回来时就被自己的守卫
    // 当成陈旧响应丢掉——A 页的成员资格永远停在 'checking'，输入区一直不出现。
    //
    // 钉法：让 A 的请求在途时 B 也 refresh 一次，然后应答 A 的。共享的话 A 的
    // seq 已经被 B 顶掉，那道 `seq !== this.membershipSeq` 会把它丢弃。
    it('两个实例的 membershipSeq 互不干扰：B 的 refresh 不会作废 A 在途的请求', 0,
      async (): Promise<void> => {
        const hostA: MembershipFakeHost = new MembershipFakeHost();
        hostA.chatIdValue = 1;
        const hostB: MembershipFakeHost = new MembershipFakeHost();
        hostB.chatIdValue = 2;
        const a: MembershipSession = membershipControllerOn(hostA);
        const b: MembershipSession = membershipControllerOn(hostB);

        a.refresh();                      // A 的 getChat 在途
        b.refresh();                      // B 也发一轮——共享计数器的话这里把 A 顶掉
        b.refresh();                      // 再来一次，把差距拉开，排除"恰好相等"的巧合

        hostA.wired.respond(0, supergroupChat(77)); // 应答 A 自己那一轮
        await sleep(0);

        // 隔离在：A 的响应被自己的守卫放行，正常走进 supergroup 分支。
        // 共享的话：A 的 seq 已过期，getChat().then 第一行就 return，
        // supergroupId 停在 0、也不会发出第二跳。
        expect(a.supergroupId()).assertEqual(77);
        expect(hostA.wired.methodOf(1)).assertEqual('getSupergroup');
      });
  });
}
