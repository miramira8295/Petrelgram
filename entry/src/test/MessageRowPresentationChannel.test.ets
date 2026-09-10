import { describe, it, expect } from '@ohos/hypium';
import { MessageEntry, cloneMessage, buildMessageEntry } from '../main/ets/store/MessageEntry';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import {
  messageRowPresentationFor, publishMessageRowPresentations,
  subscribeMessageRowPresentation
} from '../main/ets/util/messageRowPresentationChannel';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

function usersOf(): UserStore {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  client.start();
  const user: TdObject = { '@type': 'user' };
  user['id'] = 7;
  user['first_name'] = 'Ann';
  const update: TdObject = { '@type': 'updateUser' };
  update['user'] = user;
  bridge.onReceive(JSON.stringify(update));
  return users;
}

function media(id: number): MessageEntry {
  const text: TdObject = { '@type': 'formattedText' };
  text['text'] = '';
  const content: TdObject = { '@type': 'messagePhoto' };
  content['caption'] = text;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const raw: TdObject = { '@type': 'message' };
  raw['id'] = id;
  raw['sender_id'] = sender;
  raw['date'] = 1000;
  raw['content'] = content;
  const entry: MessageEntry = buildMessageEntry(raw, usersOf());
  entry.photoFileId = 801;
  return entry;
}

export default function messageRowPresentationChannelTest() {
  describe('messageRowPresentationChannel', () => {
    it('进度不唤醒整颗气泡，失败和译文会定点更新', 0, () => {
      const chatId: number = 990001;
      const firstEntry: MessageEntry = media(880001);
      const first: AlbumGroup = collapseAlbums([firstEntry])[0];
      publishMessageRowPresentations(chatId, [first]);

      const seen: AlbumGroup[] = [];
      const unsub = subscribeMessageRowPresentation(
        chatId, first.head.rowId, (group: AlbumGroup): void => { seen.push(group); });

      const progressingEntry: MessageEntry = cloneMessage(firstEntry);
      progressingEntry.photoProgress = 47;
      const progressing: AlbumGroup = collapseAlbums([progressingEntry])[0];
      publishMessageRowPresentations(chatId, [progressing]);
      expect(seen.length).assertEqual(0);

      const failedEntry: MessageEntry = cloneMessage(progressingEntry);
      failedEntry.photoFailed = true;
      const failed: AlbumGroup = collapseAlbums([failedEntry])[0];
      publishMessageRowPresentations(chatId, [failed]);
      expect(seen.length).assertEqual(1);
      expect(seen[0].head.photoFailed).assertTrue();

      const translatedEntry: MessageEntry = cloneMessage(failedEntry);
      translatedEntry.translatedText = 'hello';
      translatedEntry.translatedLang = 'en';
      const translated: AlbumGroup = collapseAlbums([translatedEntry])[0];
      publishMessageRowPresentations(chatId, [translated]);
      expect(seen.length).assertEqual(2);
      expect(messageRowPresentationFor(chatId, first.head.rowId)?.head.translatedText ?? '')
        .assertEqual('hello');
      unsub();
    });
    // 2026-09-10：这一趟是发布流水线里最贵的一段（1368 行 7ms）。改成数字键的
    // 嵌套表 + head 引用快速路径之后，语义必须一个字不变——下面钉的就是那些。
    it('head 引用没变时不唤醒订阅者，但换了内容照样定点更新', 0, () => {
      const chatId: number = 990002;
      const entry: MessageEntry = media(880002);
      const first: AlbumGroup = collapseAlbums([entry])[0];
      publishMessageRowPresentations(chatId, [first]);

      const seen: AlbumGroup[] = [];
      const unsub = subscribeMessageRowPresentation(
        chatId, first.head.rowId, (group: AlbumGroup): void => { seen.push(group); });

      // 同一个 head 对象再发一次（稳态下绝大多数行就是这样）：一次都不该唤醒。
      publishMessageRowPresentations(chatId, [collapseAlbums([entry])[0]]);
      publishMessageRowPresentations(chatId, [collapseAlbums([entry])[0]]);
      expect(seen.length).assertEqual(0);

      // 换了 head 且内容真的变了：照旧定点唤醒。
      const landed: MessageEntry = cloneMessage(entry);
      landed.photoPath = '/data/thumb-880002.jpg';
      publishMessageRowPresentations(chatId, [collapseAlbums([landed])[0]]);
      expect(seen.length).assertEqual(1);
      expect(seen[0].head.photoPath).assertEqual('/data/thumb-880002.jpg');
      unsub();
    });

    // 离屏行稍后上屏时要能拿到最新快照——换成按会话嵌套之后这条最容易被改坏。
    it('换过几个会话之后，旧会话的快照仍然读得到', 0, () => {
      const chatId: number = 990003;
      const entry: MessageEntry = media(880003);
      entry.photoPath = '/data/keep-me.jpg';
      publishMessageRowPresentations(chatId, [collapseAlbums([entry])[0]]);
      // 中间穿插几个别的会话（不超过会话表上限）。
      for (let i = 0; i < 4; i++) {
        publishMessageRowPresentations(990100 + i, [collapseAlbums([media(880100 + i)])[0]]);
      }
      expect(messageRowPresentationFor(chatId, collapseAlbums([entry])[0].head.rowId)
        ?.head.photoPath ?? '').assertEqual('/data/keep-me.jpg');
    });

  });
}
