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
  });
}
