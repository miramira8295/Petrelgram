import { describe, expect, it } from '@ohos/hypium';
import { SelectionSession, SelectionSessionHost } from '../main/ets/pages/chat/SelectionSession';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';

// 消息多选（长按菜单的"选择"）状态机，B7 把它从 ChatPage 整体搬进
// pages/chat/SelectionSession.ets 之后补的第一组断言。
//
// 钉的不是"值等于多少"，而是几条一旦被改写就会在真机上表现成"相册转发漏图 /
// 删除后对幽灵 id 发请求 / 分栏两页串选中状态"的规则。

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

function usersOf(): UserStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  const users: UserStore = new UserStore(client);
  client.start();
  const user: TdObject = { '@type': 'user' };
  user['id'] = 7;
  user['first_name'] = 'Ann';
  const update: TdObject = { '@type': 'updateUser' };
  update['user'] = user;
  bridge.onReceive(JSON.stringify(update));
  return users;
}

// 一条普通文本消息，id/contentType 可覆盖。reconcile() 只看 id，其余字段随便。
function baseEntry(id: number, contentType: string, users: UserStore): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = '';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 1000;
  message['content'] = content;
  const entry: MessageEntry = buildMessageEntry(message, users);
  if (contentType !== 'text') {
    const c: MessageEntry = cloneMessage(entry);
    c.contentType = contentType;
    return c;
  }
  return entry;
}

// 三条同一个 albumId、连续的照片消息，喂给真正的 collapseAlbums()——不手搭
// AlbumGroup 字面量（字段太多也太容易和真实分组逻辑对不上），拿真实产物当夹具。
function albumRowOf(ids: number[], users: UserStore): AlbumGroup {
  const members: MessageEntry[] = ids.map((id: number): MessageEntry => {
    const e: MessageEntry = cloneMessage(baseEntry(id, 'text', users));
    e.contentType = 'photo';
    e.albumId = 'album-1';
    return e;
  });
  const groups: AlbumGroup[] = collapseAlbums(members);
  return groups[0];
}

// 宿主替身：三个动作/取值全记账，控制器不许缓存宿主的值。
class FakeHost implements SelectionSessionHost {
  scrollActiveValue: boolean = false;
  closeReactionSheetCount: number = 0;
  emojiPanelCalls: boolean[] = [];
  activeCalls: boolean[] = [];

  chatTgsScrollActive: () => boolean = (): boolean => this.scrollActiveValue;
  closeReactionSheet: () => void = (): void => { this.closeReactionSheetCount++; };
  setEmojiPanel: (show: boolean) => void = (show: boolean): void => {
    this.emojiPanelCalls.push(show);
  };
  onActiveChange: (active: boolean) => void = (active: boolean): void => {
    this.activeCalls.push(active);
  };
}

function sessionOn(host: FakeHost): SelectionSession {
  const session: SelectionSession = new SelectionSession();
  session.bind(host);
  return session;
}

export default function selectionSessionTest() {
  describe('SelectionSession', () => {

    // 防的回归：长按相册行进多选、或者后续点相册行，只把被长按/被点的那一条
    // 记进选中集合，而不是整行的全部成员——用户看到"整行是选中底色"，计数却是
    // 1，转发时也只发一张，九图相册转发成一张。
    it('toggleRow 对相册组整体增删：一行要么全选要么全不选', 0, (): void => {
      const users: UserStore = usersOf();
      const row: AlbumGroup = albumRowOf([101, 102, 103], users);
      expect(row.memberIds.length).assertEqual(3);

      const session: SelectionSession = sessionOn(new FakeHost());
      session.toggleRow(row);
      // 整行三条全部进选中集合，不是只有第一条。
      expect(session.ids.length).assertEqual(3);
      expect(session.ids.indexOf(101) >= 0).assertTrue();
      expect(session.ids.indexOf(102) >= 0).assertTrue();
      expect(session.ids.indexOf(103) >= 0).assertTrue();
      expect(session.isRowSelected(row)).assertTrue();

      // 再点一次同一行：整行清空，不是留下半选。
      session.toggleRow(row);
      expect(session.ids.length).assertEqual(0);
      expect(session.isRowSelected(row)).assertFalse();
      // 唯一一行清空后自动退出多选态（clearState 那一支）。
      expect(session.active).assertFalse();
    });

    // 防的回归：系统消息/被隐藏的消息（没有可转发/可复制的内容）被长按菜单
    // 硬塞进选中集合。
    it('toggleRow 对不可选内容类型（系统消息）直接不生效', 0, (): void => {
      const users: UserStore = usersOf();
      const sys: MessageEntry = baseEntry(201, 'system', users);
      const row: AlbumGroup = collapseAlbums([sys])[0];

      const session: SelectionSession = sessionOn(new FakeHost());
      session.toggleRow(row);
      expect(session.ids.length).assertEqual(0);
    });

    // 防的回归：删除/撤回消息后，选中集合里留着指向不存在消息的幽灵 id——
    // 计数还在涨，删除按钮却对着一个已经不存在的 message id 发请求。
    it('reconcile 剔除已不存在的 id，仍剩的保留', 0, (): void => {
      const users: UserStore = usersOf();
      const session: SelectionSession = sessionOn(new FakeHost());
      session.enter([301, 302, 303]);
      expect(session.ids.length).assertEqual(3);

      // 301 被删除，只剩 302/303 还活着。
      const live: MessageEntry[] = [
        baseEntry(302, 'text', users),
        baseEntry(303, 'text', users)
      ];
      session.reconcile(live);

      expect(session.ids.length).assertEqual(2);
      expect(session.ids.indexOf(301) >= 0).assertFalse();
      expect(session.ids.indexOf(302) >= 0).assertTrue();
      expect(session.ids.indexOf(303) >= 0).assertTrue();
      // 还剩东西，不该被自动退出多选态。
      expect(session.active).assertTrue();
    });

    // 防的回归：选中的消息被整批删光之后，多选工具栏还挂着（active 仍是
    // true），底部的删除/转发按钮对一个空集合可点，用户点下去等于对着空气
    // 发请求。
    it('reconcile 把选中集合全部剔完后自动 exit', 0, (): void => {
      const session: SelectionSession = sessionOn(new FakeHost());
      session.enter([401, 402]);
      expect(session.active).assertTrue();

      // 401/402 全没了，存活列表里什么都不剩。
      session.reconcile([]);

      expect(session.ids.length).assertEqual(0);
      expect(session.active).assertFalse();
    });

    // reconcile 在没进多选态时是个 no-op：不该因为一次列表快照刷新就凭空
    // 把 active 从 false 掰成别的状态，也不该动 ids。
    it('reconcile 在未进入多选态时什么都不做', 0, (): void => {
      const session: SelectionSession = sessionOn(new FakeHost());
      session.reconcile([]);
      expect(session.active).assertFalse();
      expect(session.ids.length).assertEqual(0);
    });

    // 防的回归：reset() 只是把 clearSelectionState 的裸赋值删掉/写岔，导致路由
    // 切换或新会话进入时上一个会话选中的消息 id 跟着漏到下一个会话里。
    it('reset() 清空 active 与 ids', 0, (): void => {
      const session: SelectionSession = sessionOn(new FakeHost());
      session.enter([501, 502]);
      expect(session.active).assertTrue();
      expect(session.ids.length).assertEqual(2);

      session.reset();

      expect(session.active).assertFalse();
      expect(session.ids.length).assertEqual(0);
    });

    // count() 是 UI 上"已选 N 条"文案的唯一数据源，必须永远等于 ids.length，
    // 不能是缓存下来的、可能和 ids 实际内容脱节的另一个计数器。
    it('count() 与 ids.length 保持一致', 0, (): void => {
      const users: UserStore = usersOf();
      const session: SelectionSession = sessionOn(new FakeHost());
      expect(session.count()).assertEqual(0);

      session.enter([601, 602, 603]);
      expect(session.count()).assertEqual(3);

      session.reconcile([baseEntry(602, 'text', users)]);
      expect(session.count()).assertEqual(1);
    });

    // 防的回归：把这簇状态做成模块级单例（比如挂在一个共享变量上），平板
    // 分栏、导航栈多层时同时活着多个 ChatPage 就会共用同一份选择态——A 页删
    // 选中的消息，B 页的选中集合也跟着被清掉。
    it('两个 SelectionSession 实例互不影响', 0, (): void => {
      const hostA: FakeHost = new FakeHost();
      const hostB: FakeHost = new FakeHost();
      const sessionA: SelectionSession = sessionOn(hostA);
      const sessionB: SelectionSession = sessionOn(hostB);

      sessionA.enter([701, 702]);
      expect(sessionA.active).assertTrue();
      expect(sessionA.ids.length).assertEqual(2);
      // B 完全没被 A 的 enter() 碰到。
      expect(sessionB.active).assertFalse();
      expect(sessionB.ids.length).assertEqual(0);

      sessionB.enter([801]);
      expect(sessionB.ids.length).assertEqual(1);
      // A 也没被 B 的 enter() 影响，仍是自己的两条。
      expect(sessionA.ids.length).assertEqual(2);
      expect(sessionA.ids.indexOf(701) >= 0).assertTrue();
      expect(sessionA.ids.indexOf(702) >= 0).assertTrue();

      // A 清空不影响 B。
      sessionA.reset();
      expect(sessionA.ids.length).assertEqual(0);
      expect(sessionB.ids.length).assertEqual(1);
      expect(sessionB.ids.indexOf(801) >= 0).assertTrue();
    });

    // enter() 的两个跨簇副作用（关反应面板、收表情抽屉）必须经 host 回调
    // 触达，不能在控制器内部直接吞掉——否则页面收不到通知，面板/抽屉停在
    // 打开状态，和刚进的多选工具栏叠在一起。
    it('enter() 经 host 回调关反应面板与表情抽屉', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const session: SelectionSession = sessionOn(host);

      session.enter([901]);

      expect(host.closeReactionSheetCount).assertEqual(1);
      expect(host.emojiPanelCalls.length).assertEqual(1);
      expect(host.emojiPanelCalls[0]).assertFalse();
    });

    // exit() 是 clearState 的动画包装版：从多选态里出来必须真的清空，不能
    // 只把工具栏收起来、选中集合却留在内存里，导致下次进多选时残留上次的
    // 选中 id。
    it('exit() 清空 active 与 ids', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const session: SelectionSession = sessionOn(host);
      session.enter([111, 112]);
      session.exit();
      expect(session.active).assertFalse();
      expect(session.ids.length).assertEqual(0);
      expect(host.activeCalls).assertDeepEquals([true, false]);
    });
  });
}
