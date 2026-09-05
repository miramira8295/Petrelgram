import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { mediaEntryIsPhoto, mediaEntryIsVideo } from '../main/ets/util/mediaEntryKind';

// 这两个判据决定"点开这条消息要不要进全屏查看器"。它们是 B1 从 ChatPage.ets
// 搬到 util/mediaEntryKind.ets 的纯函数，本测试把真值表钉死，防止以后有人
// 顺手把 videoNote 或未解锁的付费媒体也放进查看器。

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

// 先造一条真实形状的文本消息（走 buildMessageEntry，字段一个不漏），再 clone
// 出各种 contentType —— 与 PlainTextBubbleReuse.test.ets 同一套路。
function baseEntry(): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = 'hi';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const message: TdObject = { '@type': 'message' };
  message['id'] = 900001;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 100;
  message['content'] = content;
  return buildMessageEntry(message, usersOf());
}

function entryOf(contentType: string): MessageEntry {
  const entry: MessageEntry = cloneMessage(baseEntry());
  entry.contentType = contentType;
  return entry;
}

// 付费媒体：contentType 恒为 'paidMedia'，真正的种类在 paidMediaKind
// （formatMsgContent 只产出 'photo' / 'video' / 'preview' 三种），
// 是否已解锁在 paidMediaLocked。
function paidEntry(kind: string, locked: boolean): MessageEntry {
  const entry: MessageEntry = entryOf('paidMedia');
  entry.paidMediaKind = kind;
  entry.paidMediaLocked = locked;
  return entry;
}

export default function mediaEntryKindTest() {
  describe('mediaEntryKind', () => {
    it('普通图片进图片档、普通视频进视频档，两档互斥', 0, (): void => {
      const photo: MessageEntry = entryOf('photo');
      expect(mediaEntryIsPhoto(photo)).assertTrue();
      expect(mediaEntryIsVideo(photo)).assertFalse();

      const video: MessageEntry = entryOf('video');
      expect(mediaEntryIsVideo(video)).assertTrue();
      expect(mediaEntryIsPhoto(video)).assertFalse();
    });

    it('videoNote（圆形视频）两档都不算——它在气泡里原地播放', 0, (): void => {
      const note: MessageEntry = entryOf('videoNote');
      expect(mediaEntryIsPhoto(note)).assertFalse();
      expect(mediaEntryIsVideo(note)).assertFalse();
    });

    it('已解锁的付费媒体按 paidMediaKind 落档', 0, (): void => {
      const paidPhoto: MessageEntry = paidEntry('photo', false);
      expect(mediaEntryIsPhoto(paidPhoto)).assertTrue();
      expect(mediaEntryIsVideo(paidPhoto)).assertFalse();

      const paidVideo: MessageEntry = paidEntry('video', false);
      expect(mediaEntryIsVideo(paidVideo)).assertTrue();
      expect(mediaEntryIsPhoto(paidVideo)).assertFalse();
    });

    it('未解锁的付费媒体一律不进查看器——付费墙先于种类', 0, (): void => {
      const lockedPhoto: MessageEntry = paidEntry('photo', true);
      expect(mediaEntryIsPhoto(lockedPhoto)).assertFalse();
      expect(mediaEntryIsVideo(lockedPhoto)).assertFalse();

      const lockedVideo: MessageEntry = paidEntry('video', true);
      expect(mediaEntryIsPhoto(lockedVideo)).assertFalse();
      expect(mediaEntryIsVideo(lockedVideo)).assertFalse();
    });

    it("付费媒体的 'preview' 档既不是图也不是视频", 0, (): void => {
      const preview: MessageEntry = paidEntry('preview', false);
      expect(mediaEntryIsPhoto(preview)).assertFalse();
      expect(mediaEntryIsVideo(preview)).assertFalse();
    });

    it('文本 / 文件 / 贴纸都不是查看器的料', 0, (): void => {
      const text: MessageEntry = entryOf('text');
      expect(mediaEntryIsPhoto(text)).assertFalse();
      expect(mediaEntryIsVideo(text)).assertFalse();

      const file: MessageEntry = entryOf('file');
      expect(mediaEntryIsPhoto(file)).assertFalse();
      expect(mediaEntryIsVideo(file)).assertFalse();

      const sticker: MessageEntry = entryOf('sticker');
      expect(mediaEntryIsPhoto(sticker)).assertFalse();
      expect(mediaEntryIsVideo(sticker)).assertFalse();
    });

    it('paidMediaKind 只在 contentType 为 paidMedia 时生效', 0, (): void => {
      // 一条文本消息即使残留了 paidMediaKind='photo'，也不该被当成图片。
      const text: MessageEntry = entryOf('text');
      text.paidMediaKind = 'photo';
      text.paidMediaLocked = false;
      expect(mediaEntryIsPhoto(text)).assertFalse();
      expect(mediaEntryIsVideo(text)).assertFalse();
    });
  });
}
