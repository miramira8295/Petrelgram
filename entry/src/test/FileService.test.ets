import { afterEach, describe, it, expect } from '@ohos/hypium';
import { TdClient, TimerFns } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { buildChatEntry } from '../main/ets/store/chatEntryFactory';
import { FileService } from '../main/ets/services/FileService';
import { cloneEntry } from '../main/ets/store/ChatEntry';
import { avatarFilePathFor, resetAvatarFileChannelForTest } from '../main/ets/util/avatarFileChannel';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushCompletedFile(bridge: FakeBridge, fileId: number, path: string): void {
  const local: TdObject = { '@type': 'localFile' };
  local['path'] = path; local['is_downloading_completed'] = true;
  const file: TdObject = { '@type': 'file' };
  file['id'] = fileId; file['local'] = local;
  const u: TdObject = { '@type': 'updateFile' };
  u['file'] = file;
  bridge.onReceive(JSON.stringify(u));
}

function seedChat(store: ChatStore, bridge: FakeBridge, id: number, photoFileId: number = 0,
  listType: string = 'chatListMain'): void {
  const list: TdObject = { '@type': listType };
  if (listType === 'chatListFolder') { list['chat_folder_id'] = 9; }
  const pos: TdObject = { '@type': 'chatPosition' };
  pos['list'] = list; pos['order'] = '100'; pos['is_pinned'] = false;
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = id; chat['title'] = 'X'; chat['positions'] = [pos]; chat['unread_count'] = 0;
  if (photoFileId !== 0) {
    const small: TdObject = { '@type': 'file' }; small['id'] = photoFileId;
    const photo: TdObject = { '@type': 'chatPhotoInfo' }; photo['small'] = small;
    chat['photo'] = photo;
  }
  // 实体只来自 worker 投递（V1 的生产已删）：这里直接播种。
  const entry: ChatEntry = buildChatEntry({
    chat, previous: undefined, selfId: 0,
    senderName: (_m: TdObject | undefined): string => ''
  });
  const listKey: string = listType === 'chatListMain' ? 'main'
    : (listType === 'chatListArchive' ? 'archive' : 'folder:9');
  store.ingestForTest([entry], [{ key: listKey, ids: [id], pinned: [] }]);
  const u: TdObject = { '@type': 'updateNewChat' }; u['chat'] = chat;
  bridge.onReceive(JSON.stringify(u));
}

interface Task { id: number; due: number; callback: () => void; }
class ManualTimer implements TimerFns {
  private time: number = 0;
  private seq: number = 0;
  private tasks: Task[] = [];
  now = (): number => this.time;
  setTimeout(callback: () => void, ms: number): number {
    const id = ++this.seq;
    this.tasks.push({ id, due: this.time + ms, callback });
    return id;
  }
  clearTimeout(id: number): void {
    this.tasks = this.tasks.filter((task) => task.id !== id);
  }
  advance(ms: number): void {
    const target = this.time + ms;
    let limit = 1000;
    while (limit-- > 0) {
      this.tasks.sort((a, b) => a.due - b.due || a.id - b.id);
      if (this.tasks.length === 0 || this.tasks[0].due > target) { break; }
      const task = this.tasks.shift()!;
      this.time = task.due;
      task.callback();
    }
    this.time = target;
  }
  count(): number { return this.tasks.length; }
}

class ProbeStore extends ChatStore {
  snapshots: number = 0;
  scans: number = 0;
  getChats(key: string = 'main'): ChatEntry[] { this.snapshots++; return super.getChats(key); }
  allEntries(): ChatEntry[] { this.scans++; return super.allEntries(); }
}
class ProbeFiles extends FileService {
  requests: number = 0;
  requestAvatar(chatId: number, fileId: number): void {
    this.requests++;
    super.requestAvatar(chatId, fileId);
  }
}
interface Harness {
  bridge: FakeBridge;
  client: TdClient;
  timer: ManualTimer;
  store: ProbeStore;
  files: ProbeFiles;
}
function makeHarness(): Harness {
  const timer = new ManualTimer();
  const bridge = new FakeBridge();
  const client = new TdClient(bridge, timer);
  const store = new ProbeStore(client, new UserStore(client), timer);
  client.start();
  const files = new ProbeFiles(client, store, timer);
  return { bridge, client, timer, store, files };
}
function downloads(h: Harness): TdObject[] {
  return h.bridge.sent.map((text) => JSON.parse(text) as TdObject)
    .filter((req) => req['@type'] === 'downloadFile');
}
function photo(h: Harness, id: number, fileId: number): void {
  const update: TdObject = { '@type': 'updateChatPhoto' };
  update['chat_id'] = id;
  if (fileId !== 0) {
    const small: TdObject = { '@type': 'file' }; small['id'] = fileId;
    const info: TdObject = { '@type': 'chatPhotoInfo' }; info['small'] = small;
    update['photo'] = info;
  }
  h.bridge.onReceive(JSON.stringify(update));
  // 实体只来自 worker 投递：把"换了头像之后的那份 entry"也播种进来，
  // 这正是 worker 会做的事（V1 的 updateChatPhoto handler 已删）。
  const current = h.store.entryOf(id);
  if (current !== undefined) {
    const next: ChatEntry = cloneEntry(current);
    next.photoFileId = fileId;
    h.store.ingestForTest([next]);
  }
}
function reply(h: Harness, fileId: number, error: boolean, path: string = ''): void {
  const requests = downloads(h).filter((req) => req['file_id'] === fileId);
  const extra = requests[requests.length - 1]['@extra'];
  const result: TdObject = { '@type': error ? 'error' : 'file' };
  if (error) { result['code'] = 500; result['message'] = 'test failure'; }
  else {
    const local: TdObject = { '@type': 'localFile' };
    local['is_downloading_completed'] = path !== ''; local['path'] = path;
    result['id'] = fileId; result['local'] = local;
  }
  result['@extra'] = extra;
  h.bridge.onReceive(JSON.stringify(result));
}
async function microtasks(): Promise<void> { await Promise.resolve(); await Promise.resolve(); }
function connection(h: Harness, ready: boolean): void {
  const state: TdObject = { '@type': ready ? 'connectionStateReady' : 'connectionStateConnecting' };
  const update: TdObject = { '@type': 'updateConnectionState' }; update['state'] = state;
  h.bridge.onReceive(JSON.stringify(update));
}

export default function fileServiceTest() {
  const cleanups: Array<() => void> = [];
  describe('FileService', () => {
    afterEach(() => { for (const cleanup of cleanups) { cleanup(); } cleanups.length = 0; });
    it('completed_file_sets_avatar_path', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      const store = new ChatStore(client, users);
      const files = new FileService(client, store);
      cleanups.push(() => { files.close(); client.dispose(); });
      client.start();
      seedChat(store, bridge, 1, 55);
      files.requestAvatar(1, 55);
      pushCompletedFile(bridge, 55, '/data/avatar_55.jpg');
      expect(store.getChats()[0].avatarPath).assertEqual('/data/avatar_55.jpg');
    });
    it('dedups_download', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      const store = new ChatStore(client, users);
      const files = new FileService(client, store);
      cleanups.push(() => { files.close(); client.dispose(); });
      client.start();
      seedChat(store, bridge, 1, 55);
      files.requestAvatar(1, 55);
      const after1 = bridge.sent.length;
      files.requestAvatar(1, 55);
      expect(bridge.sent.length).assertEqual(after1);
    });
    it('shared_file_updates_every_chat_and_late_subscriber', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      const store = new ChatStore(client, users);
      const files = new FileService(client, store);
      cleanups.push(() => { files.close(); client.dispose(); });
      client.start();
      seedChat(store, bridge, 1, 55);
      seedChat(store, bridge, 2, 55);
      files.requestAvatar(1, 55);
      files.requestAvatar(2, 55);
      pushCompletedFile(bridge, 55, '/data/avatar_55.jpg');
      expect(store.entryOf(1)?.avatarPath).assertEqual('/data/avatar_55.jpg');
      expect(store.entryOf(2)?.avatarPath).assertEqual('/data/avatar_55.jpg');

      seedChat(store, bridge, 3, 55);
      const sentBefore = bridge.sent.length;
      files.requestAvatar(3, 55);
      expect(store.entryOf(3)?.avatarPath).assertEqual('/data/avatar_55.jpg');
      expect(bridge.sent.length).assertEqual(sentBefore);
    });
  });
  describe('avatar targeted prefetch', () => {
    const harnesses: Harness[] = [];
    const setup = (): Harness => { const h = makeHarness(); harnesses.push(h); return h; };
    afterEach(() => {
      for (const h of harnesses) { h.files.close(); h.client.dispose(); }
      harnesses.length = 0;
    });

    it('新增主列表归档文件夹头像均触发，且不生成列表或扫描allEntries', 0, () => {
      const h = setup();
      seedChat(h.store, h.bridge, 1, 51);
      seedChat(h.store, h.bridge, 2, 52, 'chatListArchive');
      seedChat(h.store, h.bridge, 3, 53, 'chatListFolder');
      h.timer.advance(80);
      expect(downloads(h).length).assertEqual(3);
      expect(h.store.snapshots).assertEqual(0);
      expect(h.store.scans).assertEqual(0);
    });

    it('订阅时补已有头像一次，已有本地路径不再请求', 0, () => {
      const h = setup();
      h.files.close();
      seedChat(h.store, h.bridge, 1, 55);
      seedChat(h.store, h.bridge, 2, 56);
      h.store.setAvatarPath(2, '/already.jpg');
      h.timer.advance(80);
      h.files = new ProbeFiles(h.client, h.store, h.timer);
      expect(downloads(h).length).assertEqual(1);
      expect(downloads(h)[0]['file_id']).assertEqual(55);
      expect(h.store.snapshots).assertEqual(0);
      expect(h.store.scans).assertEqual(0);
    });

    it('普通标题未读位置更新不再重复检查头像', 0, () => {
      const h = setup();
      seedChat(h.store, h.bridge, 1, 55);
      h.timer.advance(80);
      const before = h.files.requests;
      for (let i = 0; i < 20; i++) {
        h.bridge.onReceive(JSON.stringify({ '@type': 'updateChatTitle', chat_id: 1, title: `${i}` }));
        h.bridge.onReceive(JSON.stringify({ '@type': 'updateChatUnreadMentionCount', chat_id: 1, unread_mention_count: i }));
        const list: TdObject = { '@type': 'chatListMain' };
        const position: TdObject = { '@type': 'chatPosition' };
        position['list'] = list; position['order'] = `${100 + i}`; position['is_pinned'] = false;
        const update: TdObject = { '@type': 'updateChatPosition' };
        update['chat_id'] = 1; update['position'] = position;
        h.bridge.onReceive(JSON.stringify(update));
        h.timer.advance(80);
      }
      expect(h.files.requests).assertEqual(before);
      expect(h.store.snapshots).assertEqual(0);
      expect(h.store.scans).assertEqual(0);
    });

    it('同窗口多次换头像只请求最终文件，旧完成不覆盖新头像', 0, () => {
      const h = setup();
      seedChat(h.store, h.bridge, 1, 55); h.timer.advance(80);
      photo(h, 1, 56); photo(h, 1, 57); h.timer.advance(80);
      expect(downloads(h).length).assertEqual(2);
      expect(downloads(h)[1]['file_id']).assertEqual(57);
      pushCompletedFile(h.bridge, 55, '/old.jpg');
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('');
      pushCompletedFile(h.bridge, 57, '/new.jpg');
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('/new.jpg');
    });

    it('共享文件只下载一次且完成后更新全部会话', 0, () => {
      const h = setup();
      seedChat(h.store, h.bridge, 1, 55); seedChat(h.store, h.bridge, 2, 55, 'chatListArchive'); h.timer.advance(80);
      expect(downloads(h).length).assertEqual(1);
      pushCompletedFile(h.bridge, 55, '/shared.jpg');
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('/shared.jpg');
      expect(h.store.entryOf(2)!.avatarPath).assertEqual('/shared.jpg');
    });

    it('直接下载应答完成也能更新头像，不依赖updateFile', 0, async () => {
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); h.timer.advance(80);
      reply(h, 55, false, '/response.jpg'); await microtasks();
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('/response.jpg');
    });

    it('下载失败无需消息更新即可延迟重试', 0, async () => {
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); h.timer.advance(80);
      reply(h, 55, true); await microtasks();
      h.timer.advance(1999); expect(downloads(h).length).assertEqual(1);
      h.timer.advance(1); expect(downloads(h).length).assertEqual(2);
      reply(h, 55, false, '/retry.jpg'); await microtasks();
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('/retry.jpg');
      expect(h.timer.count()).assertEqual(1); // only the Store avatar-path notification
      h.timer.advance(80); expect(h.timer.count()).assertEqual(0);
    });

    it('失败最多追加三次重试，网络恢复只重试失败文件且Ready不重复触发', 0, async () => {
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); seedChat(h.store, h.bridge, 2, 56); h.timer.advance(80);
      reply(h, 56, false, '/ok.jpg'); await microtasks();
      for (const delay of [2000, 5000, 15000]) {
        reply(h, 55, true); await microtasks(); h.timer.advance(delay);
      }
      reply(h, 55, true); await microtasks();
      h.timer.advance(60000);
      expect(downloads(h).length).assertEqual(5);
      connection(h, true);
      expect(downloads(h).length).assertEqual(6);
      expect(downloads(h)[5]['file_id']).assertEqual(55);
      connection(h, true); expect(downloads(h).length).assertEqual(6);
    });

    it('移除头像取消失败文件的重试', 0, async () => {
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); h.timer.advance(80);
      reply(h, 55, true); await microtasks();
      photo(h, 1, 0); h.timer.advance(80); h.timer.advance(6000);
      connection(h, true);
      expect(downloads(h).length).assertEqual(1);
      expect(h.store.entryOf(1)!.photoFileId).assertEqual(0);
    });

    it('独立预取的文件不会因会话换头像而丢失重试', 0, async () => {
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); h.timer.advance(80);
      h.files.prefetchAvatar(55);
      reply(h, 55, true); await microtasks();
      photo(h, 1, 0); h.timer.advance(2000);
      expect(downloads(h).length).assertEqual(2);
      reply(h, 55, false, '/prefetch.jpg'); await microtasks();
      expect(h.files.avatarPathOf(55)).assertEqual('/prefetch.jpg');
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('');
    });

    it('清除本地路径后按单会话恢复缓存，无需再次下载', 0, () => {
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); h.timer.advance(80);
      pushCompletedFile(h.bridge, 55, '/cached.jpg'); h.timer.advance(80);
      const requests = h.files.requests;
      h.store.setAvatarPath(1, ''); h.timer.advance(80);
      expect(h.files.requests).assertEqual(requests + 1);
      expect(h.store.entryOf(1)!.avatarPath).assertEqual('/cached.jpg');
      expect(downloads(h).length).assertEqual(1);
    });

    it('关闭取消重试并拒绝新更新和迟到应答的全局发布', 0, async () => {
      resetAvatarFileChannelForTest();
      const h = setup(); seedChat(h.store, h.bridge, 1, 55); seedChat(h.store, h.bridge, 2, 56); h.timer.advance(80);
      reply(h, 55, true); await microtasks();
      h.files.close(); h.files.close();
      reply(h, 56, false, '/old-account.jpg'); await microtasks();
      pushCompletedFile(h.bridge, 55, '/old-update.jpg');
      seedChat(h.store, h.bridge, 3, 57); h.timer.advance(10000);
      expect(downloads(h).length).assertEqual(2);
      expect(h.store.entryOf(2)!.avatarPath).assertEqual('');
      expect(avatarFilePathFor(56)).assertEqual('');
      expect(avatarFilePathFor(55)).assertEqual('');
    });
  });

}
