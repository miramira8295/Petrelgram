import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushUser(bridge: FakeBridge, id: number, first: string, last: string): void {
  const user: TdObject = { '@type': 'user' };
  user['id'] = id; user['first_name'] = first; user['last_name'] = last;
  const u: TdObject = { '@type': 'updateUser' };
  u['user'] = user;
  bridge.onReceive(JSON.stringify(u));
}

function pushBot(bridge: FakeBridge, id: number, hasTopics: boolean, allowsUserTopics: boolean): void {
  const type: TdObject = { '@type': 'userTypeBot' };
  type['has_topics'] = hasTopics;
  type['allows_users_to_create_topics'] = allowsUserTopics;
  const user: TdObject = { '@type': 'user' };
  user['id'] = id; user['first_name'] = 'Bot'; user['last_name'] = '';
  user['type'] = type;
  const u: TdObject = { '@type': 'updateUser' };
  u['user'] = user;
  bridge.onReceive(JSON.stringify(u));
}

function pushUserWithPhoto(bridge: FakeBridge, id: number, smallFileId: number, animated: boolean): void {
  const small: TdObject = { '@type': 'file' };
  small['id'] = smallFileId;
  const photo: TdObject = { '@type': 'profilePhoto' };
  photo['small'] = small;
  photo['has_animation'] = animated;
  const user: TdObject = { '@type': 'user' };
  user['id'] = id; user['first_name'] = 'U'; user['last_name'] = '';
  user['profile_photo'] = photo;
  const u: TdObject = { '@type': 'updateUser' };
  u['user'] = user;
  bridge.onReceive(JSON.stringify(u));
}

export default function userStoreTest() {
  describe('UserStore', () => {
    it('caches_and_resolves', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      pushUser(bridge, 42, 'Ada', 'Lovelace');
      expect(users.displayName(42)).assertEqual('Ada Lovelace');
    });
    it('unknown_empty', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      expect(users.displayName(999)).assertEqual('');
    });
    it('first_only', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      pushUser(bridge, 7, 'Cher', '');
      expect(users.displayName(7)).assertEqual('Cher');
    });
    // 群聊气泡左侧的头像要不要去取动态头像，先看这个标志（2026-09-17，issue #140）：
    // profilePhoto 只带 has_animation，真正的 MP4 要再取一次完整资料。
    it('records_whether_profile_photo_is_animated', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      pushUserWithPhoto(bridge, 8, 101, true);
      pushUserWithPhoto(bridge, 9, 102, false);
      expect(users.hasAnimatedPhoto(8)).assertTrue();
      expect(users.hasAnimatedPhoto(9)).assertFalse();
      expect(users.hasAnimatedPhoto(404)).assertFalse();
      // 换成静态头像之后标志跟着变
      pushUserWithPhoto(bridge, 8, 103, false);
      expect(users.hasAnimatedPhoto(8)).assertFalse();
    // issue #206：开了话题模式的 Bot 私聊要按话题展示。
    it('records_bot_topic_mode', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const users = new UserStore(client);
      client.start();
      pushBot(bridge, 11, true, true);
      pushBot(bridge, 12, true, false);
      pushBot(bridge, 13, false, false);
      expect(users.botHasTopics(11)).assertTrue();
      expect(users.botAllowsUserTopics(11)).assertTrue();
      expect(users.botHasTopics(12)).assertTrue();
      expect(users.botAllowsUserTopics(12)).assertFalse();
      expect(users.botHasTopics(13)).assertFalse();
      expect(users.botHasTopics(404)).assertFalse();
      // Bot 关掉话题模式后跟着变
      pushBot(bridge, 11, false, false);
      expect(users.botHasTopics(11)).assertFalse();
      expect(users.botAllowsUserTopics(11)).assertFalse();
    });
    });
  });
}
