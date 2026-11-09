import { publishThumbPath, subscribeThumbPath } from '../main/ets/util/mediaThumbChannel';
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

function album(id: number, fileId: number): MessageEntry[] {
  const a = media(id);
  const b = media(id + 1);
  a.albumId = String(700000 + id);
  b.albumId = a.albumId;
  a.photoFileId = fileId;
  b.photoFileId = fileId + 1;
  return [a, b];
}

export default function messageRowPresentationChannelTest() {
  describe('messageRowPresentationChannel', () => {
    it('album_delivered_thumbnails_update_tiles_without_waking_the_row', 0, () => {
      const entries = album(890101, 910101);
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991101, [first]);
      let rows = 0;
      let tiles = 0;
      const unsub = subscribeMessageRowPresentation(991101, first.head.rowId, (): void => { rows++; });
      const unthumb = subscribeThumbPath(entries[0].photoFileId, (): void => { tiles++; });
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[0].photoPath = '/album-delivered-a';
      next[1].photoPath = '/album-delivered-b';
      publishThumbPath(next[0].photoFileId, next[0].photoPath);
      publishThumbPath(next[1].photoFileId, next[1].photoPath);
      const group = collapseAlbums(next)[0];
      publishMessageRowPresentations(991101, [group]);
      expect(rows).assertEqual(0);
      expect(tiles).assertEqual(1);
      expect(messageRowPresentationFor(991101, first.head.rowId) === group).assertTrue();
      unsub(); unthumb();
    });
    it('album_missing_file_channel_still_notifies_row', 0, () => {
      const entries = album(890200, 910200);
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[0].photoPath = '/not-published';
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991102, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991102, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991102, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_different_channel_path_still_notifies_row', 0, () => {
      const entries = album(890210, 910210);
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[0].photoPath = '/wanted'; publishThumbPath(next[0].photoFileId, '/different');
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991103, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991103, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991103, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_local_only_path_still_notifies_row', 0, () => {
      const entries = album(890220, 910220);
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      entries[0].photoFileId = 0; next[0].photoFileId = 0; next[0].photoPath = '/local-only';
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991104, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991104, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991104, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_path_removal_still_notifies_row', 0, () => {
      const entries = album(890230, 910230);
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      entries[0].photoPath = '/old'; next[0].photoPath = '';
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991105, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991105, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991105, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_failure_with_delivered_path_still_notifies_row', 0, () => {
      const entries = album(890240, 910240);
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[0].photoPath = '/failure'; next[0].photoFailed = true; publishThumbPath(next[0].photoFileId, next[0].photoPath);
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991106, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991106, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991106, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_translation_with_delivered_path_still_notifies_row', 0, () => {
      const entries = album(890250, 910250);
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[0].photoPath = '/translation'; next[0].translatedText = 'translated'; publishThumbPath(next[0].photoFileId, next[0].photoPath);
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991107, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991107, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991107, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_video_poster_still_notifies_row_after_file_delivery', 0, () => {
      const entries = album(890260, 910260);
      entries[1].contentType = 'video';
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[1].photoPath = '/video-poster';
      publishThumbPath(next[1].photoFileId, next[1].photoPath);
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991108, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991108, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991108, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
    it('album_existing_failure_path_arrival_refreshes_tap_to_retry', 0, () => {
      const entries = album(890270, 910270);
      entries[1].photoFailed = true;
      const next = entries.map((m: MessageEntry): MessageEntry => cloneMessage(m));
      next[1].photoPath = '/arrived-despite-failure';
      publishThumbPath(next[1].photoFileId, next[1].photoPath);
      const first = collapseAlbums(entries)[0];
      publishMessageRowPresentations(991109, [first]);
      let rows = 0;
      const unsub = subscribeMessageRowPresentation(991109, first.head.rowId, (): void => { rows++; });
      publishMessageRowPresentations(991109, [collapseAlbums(next)[0]]);
      expect(rows).assertEqual(1);
      unsub();
    });
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

    // 2026-09-15：刚发出去的贴纸不会动。发送成功时 MessageStore 把临时 id 换成真实 id、rowId 继承，
    // 展示字段（路径 / 失败 / 译文）一个没变——旧实现据此判「没变」，快照停在临时那条，挂着的气泡
    // 一直优先画旧快照（[RowGuard] param=真实 id rendered=临时 id）。
    it('同一行换了消息身份（id 变、展示字段不变）时，快照换掉并定点通知', 0, () => {
      const chatId: number = 990004;
      const pending: MessageEntry = media(880004);
      pending.photoPath = '/data/sticker-thumb-880004.jpg';
      const first: AlbumGroup = collapseAlbums([pending])[0];
      publishMessageRowPresentations(chatId, [first]);

      const seen: AlbumGroup[] = [];
      const unsub = subscribeMessageRowPresentation(
        chatId, first.head.rowId, (group: AlbumGroup): void => { seen.push(group); });

      const sent: MessageEntry = cloneMessage(pending);
      sent.id = 880004 + 1048576;
      const landed: AlbumGroup = collapseAlbums([sent])[0];
      expect(landed.head.rowId).assertEqual(first.head.rowId);
      publishMessageRowPresentations(chatId, [landed]);
      expect(seen.length).assertEqual(1);
      expect(messageRowPresentationFor(chatId, first.head.rowId)?.head.id ?? 0).assertEqual(sent.id);
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
