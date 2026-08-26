import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageBubbleRenderData } from '../main/ets/pages/chat/ReusableMessageBubble';
import { ReuseIdLevel, rowReuseId } from '../main/ets/util/rowReuseId';

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

function textEntry(id: number, outgoing: boolean = false): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = `plain-${id}`;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = outgoing;
  message['sender_id'] = sender;
  message['date'] = 100;
  message['content'] = content;
  return buildMessageEntry(message, usersOf());
}

// ArkTS 不支持 Partial<T>，用等价的「全字段可选」接口代替（同
// MediaPolicy.test.ets 的写法）。
interface RenderDataOverrides {
  isGroup?: boolean;
  lightweightPlainText?: boolean;
}

function renderData(over: RenderDataOverrides = {}): MessageBubbleRenderData {
  return {
    chatId: 1,
    isGroup: over.isGroup ?? false,
    isChannel: false,
    liveSharingId: 0,
    themeBubbleOut: '',
    showUnreadDivider: false,
    paidMediaPending: false,
    audioQueuePosition: 0,
    audioQueueLength: 0,
    audioHasPrevious: false,
    audioHasNext: false,
    playSlotKey: '',
    autoplayMuted: false,
    playSlotStartMs: 0,
    animationPaused: false,
    animationForcePlay: false,
    animationPlaybackFailed: false,
    editingActive: false,
    isPinnedMsg: false,
    liveGroupCallId: 0,
    animateIn: false,
    lightweightPlainText: over.lightweightPlainText ?? false
  };
}

export default function rowReuseIdTest() {
  describe('RowReuseId', () => {
    it('coarse_level_only_splits_lightweight_from_rich', 0, () => {
      const plain: MessageEntry = textEntry(1);
      const other: MessageEntry = textEntry(2);
      other.senderName = 'Different sender entirely';
      expect(rowReuseId(renderData({ lightweightPlainText: true }), plain, 'coarse'))
        .assertEqual(rowReuseId(renderData({ lightweightPlainText: true }), other, 'coarse'));
      expect(rowReuseId(renderData({ lightweightPlainText: true }), plain, 'coarse') ===
        rowReuseId(renderData({ lightweightPlainText: false }), plain, 'coarse')).assertFalse();
    });

    it('same_structure_same_id_at_every_level', 0, () => {
      const a: MessageEntry = textEntry(10);
      const b: MessageEntry = textEntry(11);
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const levels: ReuseIdLevel[] = ['coarse', 'medium', 'fine'];
      for (const level of levels) {
        expect(rowReuseId(data, a, level)).assertEqual(rowReuseId(data, b, level));
      }
    });

    it('medium_level_splits_on_structural_switches', 0, () => {
      const base: MessageEntry = textEntry(20);
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const baseId: string = rowReuseId(data, base, 'medium');

      const withReply: MessageEntry = cloneMessage(base);
      withReply.replyToMessageId = 5;
      expect(rowReuseId(data, withReply, 'medium') === baseId).assertFalse();

      const withForward: MessageEntry = cloneMessage(base);
      withForward.forwardFrom = 'Alice';
      expect(rowReuseId(data, withForward, 'medium') === baseId).assertFalse();

      const withReaction: MessageEntry = cloneMessage(base);
      withReaction.reactions = [{ emoji: '👍', count: 1, isChosen: false,
        customEmojiId: '', customEmojiPath: '' }];
      expect(rowReuseId(data, withReaction, 'medium') === baseId).assertFalse();

      const outgoing: MessageEntry = textEntry(21, true);
      expect(rowReuseId(data, outgoing, 'medium') === baseId).assertFalse();

      const withSenderName: MessageEntry = cloneMessage(base);
      withSenderName.senderName = 'Bob';
      const withoutSenderName: MessageEntry = cloneMessage(base);
      withoutSenderName.senderName = '';
      expect(rowReuseId(data, withSenderName, 'medium') ===
        rowReuseId(data, withoutSenderName, 'medium')).assertFalse();
    });

    it('fine_level_splits_on_media_kind_only', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const text: MessageEntry = textEntry(30);
      const photo: MessageEntry = cloneMessage(text);
      photo.contentType = 'photo';
      const video: MessageEntry = cloneMessage(text);
      video.contentType = 'video';
      const sticker: MessageEntry = cloneMessage(text);
      sticker.contentType = 'sticker';
      const file: MessageEntry = cloneMessage(text);
      file.contentType = 'file';
      const other: MessageEntry = cloneMessage(text);
      other.contentType = 'poll';

      const ids: string[] = [text, photo, video, sticker, file, other]
        .map((m: MessageEntry): string => rowReuseId(data, m, 'fine'));
      // Every distinct media kind must land in a distinct bucket.
      for (let i = 0; i < ids.length; i++) {
        for (let j = i + 1; j < ids.length; j++) {
          expect(ids[i] === ids[j]).assertFalse();
        }
      }

      // Same media kind, different (non-structural) content -> same bucket.
      const photoTwin: MessageEntry = cloneMessage(text);
      photoTwin.contentType = 'photo';
      photoTwin.photoFileId = 999;
      expect(rowReuseId(data, photo, 'fine')).assertEqual(rowReuseId(data, photoTwin, 'fine'));

      // Fine level must not collapse back to medium's bucket count: text (no
      // media) still differs from photo even though medium treats them alike.
      expect(rowReuseId(data, text, 'medium')).assertEqual(rowReuseId(data, photo, 'medium'));
      expect(rowReuseId(data, text, 'fine') === rowReuseId(data, photo, 'fine')).assertFalse();
    });

    it('bucket_count_grows_from_coarse_to_fine', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const samples: MessageEntry[] = [];
      const base: MessageEntry = textEntry(40);
      samples.push(base);
      const reply: MessageEntry = cloneMessage(base);
      reply.replyToMessageId = 1;
      samples.push(reply);
      const photo: MessageEntry = cloneMessage(base);
      photo.contentType = 'photo';
      samples.push(photo);
      const video: MessageEntry = cloneMessage(base);
      video.contentType = 'video';
      samples.push(video);

      const bucketCount = (level: ReuseIdLevel): number => {
        const seen = new Set<string>();
        for (const m of samples) {
          seen.add(rowReuseId(data, m, level));
        }
        return seen.size;
      };
      const coarse = bucketCount('coarse');
      const medium = bucketCount('medium');
      const fine = bucketCount('fine');
      expect(coarse <= medium).assertTrue();
      expect(medium <= fine).assertTrue();
      expect(medium < fine).assertTrue();
    });

    it('identity_content_and_timestamp_never_affect_the_id', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const first: MessageEntry = textEntry(50);
      const second: MessageEntry = cloneMessage(first);
      second.id = 999999;
      second.rowId = 999999;
      second.text = 'a completely different sentence, much longer than the first one';
      second.date = first.date + 12345;
      const levels: ReuseIdLevel[] = ['coarse', 'medium', 'fine'];
      for (const level of levels) {
        expect(rowReuseId(data, first, level)).assertEqual(rowReuseId(data, second, level));
      }
    });
  });
}
