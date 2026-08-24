import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { resetScopeMute, setScopeMuted } from '../main/ets/store/ScopeMuteStore';
import { SCOPE_CHANNEL, SCOPE_GROUP } from '../main/ets/store/NotificationApi';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function mainPos(order: string, pinned: boolean): TdObject {
  const list: TdObject = { '@type': 'chatListMain' };
  const p: TdObject = { '@type': 'chatPosition' };
  p['list'] = list; p['order'] = order; p['is_pinned'] = pinned;
  return p;
}

function textMessage(text: string, date: number): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' }; content['text'] = ft;
  const m: TdObject = { '@type': 'message' };
  m['content'] = content; m['date'] = date;
  return m;
}

function pushNewChat(bridge: FakeBridge, id: number, title: string,
    positions: TdObject[], lastMsg: TdObject | null, unread: number): void {
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = id; chat['title'] = title; chat['positions'] = positions;
  chat['unread_count'] = unread;
  if (lastMsg !== null) { chat['last_message'] = lastMsg; }
  const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
  bridge.onReceive(JSON.stringify(u));
}


function pushMyId(bridge: FakeBridge, id: number): void {
  const value: TdObject = { '@type': 'optionValueInteger' };
  value['value'] = `${id}`;   // TDLib 的 int53 在 JSON 里是字符串
  const u: TdObject = { '@type': 'updateOption' };
  u['name'] = 'my_id'; u['value'] = value;
  bridge.onReceive(JSON.stringify(u));
}

// ChatStore 按 NOTIFY_COALESCE_MS(80ms) 合并订阅者通知，断言前需等窗口结束。
function settleNotify(): Promise<void> {
  return new Promise<void>((resolve: (v: void) => void): void => {
    setTimeout((): void => resolve(), 140);
  });
}

function pushPosition(bridge: FakeBridge, id: number, pos: TdObject): void {
  const u: TdObject = { '@type': 'updateChatPosition' };
  u['chat_id'] = id; u['position'] = pos;
  bridge.onReceive(JSON.stringify(u));
}

function folderPos(fid: number, order: string, pinned: boolean): TdObject {
  const list: TdObject = { '@type': 'chatListFolder' }; list['chat_folder_id'] = fid;
  const p: TdObject = { '@type': 'chatPosition' };
  p['list'] = list; p['order'] = order; p['is_pinned'] = pinned;
  return p;
}
function archivePos(order: string, pinned: boolean): TdObject {
  const list: TdObject = { '@type': 'chatListArchive' };
  const p: TdObject = { '@type': 'chatPosition' };
  p['list'] = list; p['order'] = order; p['is_pinned'] = pinned;
  return p;
}

function ids(chats: ChatEntry[]): number[] {
  return chats.map((c: ChatEntry) => c.id);
}

function make(): ChatStore {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  const store = new ChatStore(client, users);
  client.start();
  // stash bridge on store for test access
  (store as object)['__bridge'] = bridge;
  return store;
}

function bridgeOf(store: ChatStore): FakeBridge {
  return (store as object)['__bridge'] as FakeBridge;
}


// 会应答 loadChats 的桥：前 pagesBeforeEnd 页返回 ok，之后返回 404
// （TDLib 用 404 表示"这个列表没有更多会话了"）。
class PagingBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  loadChatsCalls: number = 0;
  pagesBeforeEnd: number = 2;
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void {
    const req = JSON.parse(json) as Record<string, Object>;
    if (req['@type'] !== 'loadChats') {
      return;
    }
    this.loadChatsCalls += 1;
    const extra = req['@extra'] as string;
    const ended: boolean = this.loadChatsCalls > this.pagesBeforeEnd;
    const reply: Record<string, Object> = ended
      ? { '@type': 'error', 'code': 404, 'message': 'Not Found', '@extra': extra }
      : { '@type': 'ok', '@extra': extra };
    this.onReceive(JSON.stringify(reply));
  }
}

function pagingStore(bridge: PagingBridge): ChatStore {
  const c = new TdClient(bridge);
  const s = new ChatStore(c, new UserStore(c));
  c.start();
  return s;
}

export default function chatStoreTest() {
  describe('ChatStore', () => {
    it('forum_supergroup_detected', 0, () => {
      const b = new FakeBridge();
      const c = new TdClient(b);
      const store = new ChatStore(c, new UserStore(c));
      c.start();
      const type: TdObject = { '@type': 'chatTypeSupergroup' };
      type['supergroup_id'] = 77;
      type['is_channel'] = false;
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = -100777;
      chat['title'] = '话题群';
      chat['type'] = type;
      chat['positions'] = [];
      const newChat: TdObject = { '@type': 'updateNewChat' };
      newChat['chat'] = chat;
      b.onReceive(JSON.stringify(newChat));
      expect(store.isForum(-100777)).assertFalse();
      const supergroup: TdObject = { '@type': 'supergroup' };
      supergroup['id'] = 77;
      supergroup['is_forum'] = true;
      const upd: TdObject = { '@type': 'updateSupergroup' };
      upd['supergroup'] = supergroup;
      b.onReceive(JSON.stringify(upd));
      expect(store.isForum(-100777)).assertTrue();
      expect(store.isForum(999)).assertFalse();
    });
    it('orders_by_desc_order_pinned_first', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      pushNewChat(b, 2, 'B', [mainPos('300', false)], null, 0);
      pushNewChat(b, 3, 'C', [mainPos('50', true)], null, 0);
      // pinned (3) first, then 2 (300) > 1 (100)
      expect(ids(store.getChats()).join(',')).assertEqual('3,2,1');
    });
    it('excludes_order_zero', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [], null, 0); // no main position
      expect(store.getChats().length).assertEqual(0);
    });
    it('archive_removes_unarchive_restores', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      expect(store.getChats().length).assertEqual(1);
      pushPosition(b, 1, mainPos('0', false)); // archived
      expect(store.getChats().length).assertEqual(0);
      pushPosition(b, 1, mainPos('100', false)); // unarchived
      expect(store.getChats().length).assertEqual(1);
    });
    it('last_message_updates_and_reorders', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      pushNewChat(b, 2, 'B', [mainPos('200', false)], null, 0);
      // chat 1 gets a newer message that bumps its order above 2
      const u: TdObject = { '@type': 'updateChatLastMessage' };
      u['chat_id'] = 1; u['last_message'] = textMessage('hi', 1783512000);
      u['positions'] = [mainPos('300', false)];
      b.onReceive(JSON.stringify(u));
      expect(ids(store.getChats()).join(',')).assertEqual('1,2');
      expect(store.getChats()[0].lastMessageText).assertEqual('hi');
    });
    it('read_inbox_updates_unread', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 5);
      const u: TdObject = { '@type': 'updateChatReadInbox' };
      u['chat_id'] = 1; u['unread_count'] = 0;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].unreadCount).assertEqual(0);
    });
    // 回归：刚读完的会话来新消息时，updateChatReadInbox（unread=1、水位=旧末条）
    // 可能先于 updateChatLastMessage 到达。那一刻按旧末条判，水位恰好盖住它，
    // 幽灵未读抑制会把 1 抹成 0；换上新末条后必须重算，否则"会话上浮但角标
    // 不出现"。
    it('unread_survives_read_inbox_before_last_message', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const read = textMessage('old', 1783512000);
      read['id'] = 100;
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 1; chat['title'] = 'A';
      chat['positions'] = [mainPos('100', false)];
      chat['unread_count'] = 0;
      chat['last_read_inbox_message_id'] = 100; // 全部读完
      chat['last_message'] = read;
      const nc: TdObject = { '@type': 'updateNewChat' }; nc['chat'] = chat;
      b.onReceive(JSON.stringify(nc));
      // 新消息的两条更新按"坏"顺序到：先 ReadInbox 后 LastMessage。
      const ri: TdObject = { '@type': 'updateChatReadInbox' };
      ri['chat_id'] = 1; ri['unread_count'] = 1;
      ri['last_read_inbox_message_id'] = 100;
      b.onReceive(JSON.stringify(ri));
      const fresh = textMessage('new', 1783512100);
      fresh['id'] = 101;
      const lm: TdObject = { '@type': 'updateChatLastMessage' };
      lm['chat_id'] = 1; lm['last_message'] = fresh;
      b.onReceive(JSON.stringify(lm));
      expect(store.getChats()[0].unreadCount).assertEqual(1);
    });
    it('visible_last_message_clears_stuck_unread_optimistically', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const last = textMessage('joined', 1783512000);
      last['id'] = 100;
      pushNewChat(b, 1, 'A', [mainPos('100', false)], last, 1);
      store.markReadLocally(1, 99);
      expect(store.getChats()[0].unreadCount).assertEqual(1);
      store.markReadLocally(1, 100);
      expect(store.getChats()[0].unreadCount).assertEqual(0);
    });
    it('notification_settings_mute', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      const ns: TdObject = { '@type': 'chatNotificationSettings' }; ns['mute_for'] = 3600;
      const u: TdObject = { '@type': 'updateChatNotificationSettings' };
      u['chat_id'] = 1; u['notification_settings'] = ns;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].isMuted).assertEqual(true);
    });
    it('subscribe_replays_and_notifies', 0, async () => {
      const store = make();
      const b = bridgeOf(store);
      let calls = 0;
      const off = store.subscribe((_c: ChatEntry[]) => { calls += 1; });
      expect(calls).assertEqual(1); // replay
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      // 通知按 NOTIFY_COALESCE_MS 合并，等窗口过去再断言。
      await settleNotify();
      expect(calls).assertEqual(2);
      off();
      pushNewChat(b, 2, 'B', [mainPos('200', false)], null, 0);
      await settleNotify();
      expect(calls).assertEqual(2); // no more after unsubscribe
    });
    it('subscribe_changes_replays_notifies_and_unsubscribes', 0, async () => {
      const store = make();
      const b = bridgeOf(store);
      let calls = 0;
      const off = store.subscribeChanges((): void => { calls += 1; });
      expect(calls).assertEqual(1);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 0);
      await settleNotify();
      expect(calls).assertEqual(2);
      off();
      pushNewChat(b, 2, 'B', [folderPos(5, '200', false)], null, 0);
      await settleNotify();
      expect(calls).assertEqual(2);
    });
    it('load_sends_loadChats', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      store.load();
      const sent = JSON.parse(b.sent[b.sent.length - 1]) as TdObject;
      expect(sent['@type']).assertEqual('loadChats');
    });
    it('sender_name_from_user', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const user: TdObject = { '@type': 'user' };
      user['id'] = 7; user['first_name'] = 'Ada'; user['last_name'] = 'L';
      const uu: TdObject = { '@type': 'updateUser' }; uu['user'] = user;
      b.onReceive(JSON.stringify(uu));
      const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
      const m = textMessage('hey', 1783512000); m['sender_id'] = sender;
      pushNewChat(b, 1, 'Group', [mainPos('100', false)], m, 0);
      expect(store.getChats()[0].lastSenderName).assertEqual('Ada L');
    });
    it('sender_name_private_empty', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const m = textMessage('hi', 1783512000); // no sender_id
      pushNewChat(b, 1, 'A', [mainPos('100', false)], m, 0);
      expect(store.getChats()[0].lastSenderName).assertEqual('');
    });
    it('photo_file_id_and_set_avatar_path', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const small: TdObject = { '@type': 'file' }; small['id'] = 88;
      const photo: TdObject = { '@type': 'chatPhotoInfo' }; photo['small'] = small;
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 1; chat['title'] = 'A'; chat['positions'] = [mainPos('100', false)];
      chat['unread_count'] = 0; chat['photo'] = photo;
      const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
      b.onReceive(JSON.stringify(u));
      expect(store.photoFileIdOf(1)).assertEqual(88);
      store.setAvatarPath(1, '/data/a.jpg');
      expect(store.getChats()[0].avatarPath).assertEqual('/data/a.jpg');
      const revision = store.getChats()[0].revision;
      // A later full chat refresh must not erase an already resolved avatar.
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].avatarPath).assertEqual('/data/a.jpg');
      expect(store.getChats()[0].revision).assertEqual(revision + 1);
    });
    it('update_does_not_mutate_prior_snapshot', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 5);
      const before = store.getChats()[0];
      const ur: TdObject = { '@type': 'updateChatReadInbox' };
      ur['chat_id'] = 1; ur['unread_count'] = 0;
      b.onReceive(JSON.stringify(ur));
      expect(before.unreadCount).assertEqual(5);            // 旧快照不被改写(不可变)
      expect(store.getChats()[0].unreadCount).assertEqual(0); // 新快照已更新
      expect(before.revision).assertEqual(0);
      expect(store.getChats()[0].revision).assertEqual(1);
    });
    it('notification_settings_unmute', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      const ns: TdObject = { '@type': 'chatNotificationSettings' }; ns['mute_for'] = 0;
      const u: TdObject = { '@type': 'updateChatNotificationSettings' };
      u['chat_id'] = 1; u['notification_settings'] = ns;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats()[0].isMuted).assertEqual(false);
    });
    it('load_more_sends_loadChats', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      store.loadMore();
      const sent = JSON.parse(b.sent[b.sent.length - 1]) as TdObject;
      expect(sent['@type']).assertEqual('loadChats');
    });
    it('concurrent_initial_load_is_deduplicated', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      store.ensureLoaded('folder:5');
      store.ensureLoaded('folder:5');
      let count = 0;
      for (const json of b.sent) {
        const sent = JSON.parse(json) as TdObject;
        if (sent['@type'] === 'loadChats') {
          count += 1;
        }
      }
      expect(count).assertEqual(1);
    });
    it('chat_in_main_and_folder_independent_order', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false), folderPos(5, '900', false)], null, 0);
      pushNewChat(b, 2, 'B', [mainPos('200', false), folderPos(5, '800', false)], null, 0);
      expect(ids(store.getChats('main')).join(',')).assertEqual('2,1');       // 200>100
      expect(ids(store.getChats('folder:5')).join(',')).assertEqual('1,2');   // 900>800
    });
    it('folder_only_chat_not_in_main', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 0);
      expect(store.getChats('main').length).assertEqual(0);
      expect(store.getChats('folder:5').length).assertEqual(1);
    });
    it('archive_bucket_and_hasArchive', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      expect(store.hasArchive()).assertEqual(false);
      pushNewChat(b, 1, 'A', [archivePos('100', false)], null, 0);
      expect(store.getChats('archive').length).assertEqual(1);
      expect(store.hasArchive()).assertEqual(true);
    });
    it('unread_chat_count_excludes_read_and_muted', 0, () => {
      resetScopeMute();
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '300', false)], null, 3); // unread, unmuted -> counted
      pushNewChat(b, 2, 'B', [folderPos(5, '200', false)], null, 0); // read -> not counted
      pushNewChat(b, 3, 'C', [folderPos(5, '100', false)], null, 5); // unread but muted below -> not counted
      // **use_default_mute_for 必须显式给 false。** 它为 true 时 mute_for 是无
      // 意义的（TDLib 文档原话），真实状态在分类默认里——这正是 issue #110。
      // 用户单独静音一个会话时 TDLib 发的就是 false + 非零 mute_for（我们自己的
      // setMute 也是这么写的，见 ChatActions）。
      const ns: TdObject = { '@type': 'chatNotificationSettings' };
      ns['use_default_mute_for'] = false;
      ns['mute_for'] = 3600;
      const u: TdObject = { '@type': 'updateChatNotificationSettings' }; u['chat_id'] = 3; u['notification_settings'] = ns;
      b.onReceive(JSON.stringify(u));
      expect(store.unreadChatCount('folder:5')).assertEqual(1);
      expect(store.unreadChatCount('main')).assertEqual(0);
    });
    // issue #110：把整类静音（通知设置里关掉"频道"），跟随默认的会话就该算静音。
    // 原来这里只看 mute_for，于是官版显示静音、我们既照常计数又照常画角标。
    it('unread_chat_count_honours_scope_default_mute', 0, () => {
      resetScopeMute();
      const store = make();
      const b = bridgeOf(store);
      // 频道，通知设置跟随默认、自身 mute_for 为 0。
      const type: TdObject = { '@type': 'chatTypeSupergroup' };
      type['is_channel'] = true;
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 7; chat['title'] = 'CH'; chat['type'] = type;
      chat['positions'] = [folderPos(5, '100', false)];
      chat['unread_count'] = 4;
      const ns: TdObject = { '@type': 'chatNotificationSettings' };
      ns['use_default_mute_for'] = true;
      ns['mute_for'] = 0;
      chat['notification_settings'] = ns;
      const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
      b.onReceive(JSON.stringify(u));

      expect(store.unreadChatCount('folder:5')).assertEqual(1);
      setScopeMuted(SCOPE_CHANNEL, true);
      expect(store.unreadChatCount('folder:5')).assertEqual(0);
      // 群组分类不该被频道那一次写入带上。
      setScopeMuted(SCOPE_CHANNEL, false);
      setScopeMuted(SCOPE_GROUP, true);
      expect(store.unreadChatCount('folder:5')).assertEqual(1);
      resetScopeMute();
    });
    // 文件夹角标只数**有未读消息**的会话，"手动标记为未读"不计入。
    //
    // 这一条以前是反过来的（marked 也算），但「全部」那个角标读的是 TDLib 的
    // unread_unmuted_count，而 TDLib 把手动标记单独放在
    // marked_as_unread_unmuted_count 里、不含在前者中。两边口径不同的后果很
    // 具体：把一个会话标记成未读，文件夹的数字 +1、全部的数字不动。钉的是
    // "两个角标同一个口径"，不是某一边的具体数值。
    it('unread_chat_count_ignores_manually_marked_unread', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 0);
      const u: TdObject = { '@type': 'updateChatIsMarkedAsUnread' };
      u['chat_id'] = 1;
      u['is_marked_as_unread'] = true;
      b.onReceive(JSON.stringify(u));
      expect(store.unreadChatCount('folder:5')).assertEqual(0);
    });

    // 真有未读消息时照常计入——上面那条不能把整个计数关掉。
    it('unread_chat_count_still_counts_real_unread', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 3);
      expect(store.unreadChatCount('folder:5')).assertEqual(1);
    });
    it('position_update_adds_to_folder', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      pushPosition(b, 1, folderPos(5, '300', false));
      expect(store.getChats('folder:5').length).assertEqual(1);
      expect(store.getChats('main').length).assertEqual(1); // still in main
    });
    it('display_update_reflects_across_lists', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false), folderPos(5, '100', false)], null, 5);
      const u: TdObject = { '@type': 'updateChatReadInbox' }; u['chat_id'] = 1; u['unread_count'] = 0;
      b.onReceive(JSON.stringify(u));
      expect(store.getChats('main')[0].unreadCount).assertEqual(0);
      expect(store.getChats('folder:5')[0].unreadCount).assertEqual(0);
    });
    it('chat_background_update_is_cached', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [mainPos('100', false)], null, 0);
      const fill: TdObject = { '@type': 'backgroundFillSolid' };
      fill['color'] = 0x123456;
      const type: TdObject = { '@type': 'backgroundTypeFill' };
      type['fill'] = fill;
      const background: TdObject = { '@type': 'background' };
      background['type'] = type;
      const chatBackground: TdObject = { '@type': 'chatBackground' };
      chatBackground['background'] = background;
      const update: TdObject = { '@type': 'updateChatBackground' };
      update['chat_id'] = 1;
      update['background'] = chatBackground;
      b.onReceive(JSON.stringify(update));
      const entry = store.entryOf(1);
      expect(entry !== undefined && entry.background !== null).assertTrue();
      expect(entry?.revision).assertEqual(1);
    });
    it('default_background_updates_are_cached_per_color_scheme', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      const light: TdObject = { '@type': 'background' };
      light['id'] = '101';
      const dark: TdObject = { '@type': 'background' };
      dark['id'] = '202';
      const lightUpdate: TdObject = { '@type': 'updateDefaultBackground' };
      lightUpdate['for_dark_theme'] = false;
      lightUpdate['background'] = light;
      b.onReceive(JSON.stringify(lightUpdate));
      const darkUpdate: TdObject = { '@type': 'updateDefaultBackground' };
      darkUpdate['for_dark_theme'] = true;
      darkUpdate['background'] = dark;
      b.onReceive(JSON.stringify(darkUpdate));
      expect(store.defaultBackgroundKnown(false)).assertTrue();
      expect(store.defaultBackgroundKnown(true)).assertTrue();
      expect(store.defaultBackground(false)?.['id']).assertEqual('101');
      expect(store.defaultBackground(true)?.['id']).assertEqual('202');
    });
    it('subscribe_listkey_replays_only_that_list', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 1, 'A', [folderPos(5, '100', false)], null, 0);
      let seen = -1;
      const off = store.subscribe((c: ChatEntry[]) => { seen = c.length; }, 'folder:5');
      expect(seen).assertEqual(1); // replay of folder:5
      off();
    });
    it('entry_of_returns_display_or_undefined', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      expect(store.entryOf(1)).assertUndefined();
      pushNewChat(b, 1, 'Alice', [mainPos('100', false)], null, 0);
      const e = store.entryOf(1);
      expect(e !== undefined).assertTrue();
      expect(e!.title).assertEqual('Alice');
    });

    // issue #43：分组的角标和列表都按本地已加载的会话算，而「所有」的角标是
    // TDLib 的服务端真值。分组只预取一页就会两边对不上——分组里少几个群。
    it('分组列表要一直翻到 404 为止，而不是只取一页', 0, async () => {
      const b = new PagingBridge();
      b.pagesBeforeEnd = 3;
      const store = pagingStore(b);
      await store.ensureFullyLoaded('folder:5');
      expect(b.loadChatsCalls).assertEqual(4); // 3 页 + 收到 404 的那次
      expect(store.isListExhausted('folder:5')).assertTrue();
    });

    it('翻到底之后再调不会重复请求', 0, async () => {
      const b = new PagingBridge();
      b.pagesBeforeEnd = 1;
      const store = pagingStore(b);
      await store.ensureFullyLoaded('folder:5');
      const first = b.loadChatsCalls;
      await store.ensureFullyLoaded('folder:5');
      expect(b.loadChatsCalls).assertEqual(first);
    });

    it('分组定义变了：invalidateList 之后会重新翻', 0, async () => {
      const b = new PagingBridge();
      b.pagesBeforeEnd = 1;
      const store = pagingStore(b);
      await store.ensureFullyLoaded('folder:5');
      const first = b.loadChatsCalls;
      store.invalidateList('folder:5');
      expect(store.isListExhausted('folder:5')).assertFalse();
      b.pagesBeforeEnd = b.loadChatsCalls + 1;
      await store.ensureFullyLoaded('folder:5');
      expect(b.loadChatsCalls > first).assertTrue();
    });

    // issue #8：和自己的私聊就是「我的收藏」。TDLib 不做任何标记——标题是自己
    // 的昵称、头像是自己的头像，只能靠 chat.id === 自己的 user id 认出来。
    it('和自己的私聊标记为我的收藏', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushMyId(b, 42);
      pushNewChat(b, 42, 'Me', [mainPos('100', false)], null, 0);
      pushNewChat(b, 43, 'Someone', [mainPos('99', false)], null, 0);
      expect(store.entryOf(42)!.isSavedMessages).assertTrue();
      expect(store.entryOf(43)!.isSavedMessages).assertFalse();
    });

    // my_id 通常先到；万一晚到，已经建好的那条要补标，且 revision 必须往前走
    // ——行 key 含 revision，不变就不重画，标题会一直停在自己的昵称上。
    it('my_id 晚到时补标，并推进 revision', 0, () => {
      const store = make();
      const b = bridgeOf(store);
      pushNewChat(b, 42, 'Me', [mainPos('100', false)], null, 0);
      expect(store.entryOf(42)!.isSavedMessages).assertFalse();
      const before: number = store.entryOf(42)!.revision;
      pushMyId(b, 42);
      expect(store.entryOf(42)!.isSavedMessages).assertTrue();
      expect(store.entryOf(42)!.revision > before).assertTrue();
    });
  });
}
