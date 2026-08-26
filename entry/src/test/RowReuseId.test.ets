import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageBubbleRenderData } from '../main/ets/pages/chat/ReusableMessageBubble';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
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
  showUnreadDivider?: boolean;
}

function renderData(over: RenderDataOverrides = {}): MessageBubbleRenderData {
  return {
    chatId: 1,
    isGroup: over.isGroup ?? false,
    isChannel: false,
    liveSharingId: 0,
    themeBubbleOut: '',
    showUnreadDivider: over.showUnreadDivider ?? false,
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

// AlbumGroup carries the two real per-row structural flags (showAvatar,
// showSenderName) that collapseAlbums.ets computes from run position, plus
// dateLabel (date-separator pill). rowReuseId needs the whole group, not just
// head, to reach them — see the fix note in the P2 Task 2a report on why a
// head-only signature couldn't express these.
interface GroupOverrides {
  showAvatar?: boolean;
  showSenderName?: boolean;
  dateLabel?: string;
}

function groupOf(head: MessageEntry, over: GroupOverrides = {}): AlbumGroup {
  return {
    key: `group-${head.id}`,
    head,
    memberIds: [head.id],
    rowMemberIds: [head.rowId],
    photoPaths: [], photoFileIds: [], photoRatios: [], photoIsVideo: [],
    photoProgress: [], photoFailed: [],
    videoFileIds: [], videoFileSizes: [], videoMimeTypes: [],
    caption: '', captionEntities: [],
    dateLabel: over.dateLabel ?? '',
    showAvatar: over.showAvatar ?? true,
    showSenderName: over.showSenderName ?? true
  };
}

export default function rowReuseIdTest() {
  describe('RowReuseId', () => {
    it('coarse_level_only_splits_lightweight_from_rich', 0, () => {
      const plain: AlbumGroup = groupOf(textEntry(1));
      const other: MessageEntry = textEntry(2);
      other.senderName = 'Different sender entirely';
      const otherGroup: AlbumGroup = groupOf(other);
      expect(rowReuseId(renderData({ lightweightPlainText: true }), plain, 'coarse'))
        .assertEqual(rowReuseId(renderData({ lightweightPlainText: true }), otherGroup, 'coarse'));
      expect(rowReuseId(renderData({ lightweightPlainText: true }), plain, 'coarse') ===
        rowReuseId(renderData({ lightweightPlainText: false }), plain, 'coarse')).assertFalse();
    });

    it('same_structure_same_id_at_every_level', 0, () => {
      const a: AlbumGroup = groupOf(textEntry(10));
      const b: AlbumGroup = groupOf(textEntry(11));
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const levels: ReuseIdLevel[] = ['coarse', 'medium', 'fine'];
      for (const level of levels) {
        expect(rowReuseId(data, a, level)).assertEqual(rowReuseId(data, b, level));
      }
    });

    it('medium_level_splits_on_structural_switches', 0, () => {
      const base: MessageEntry = textEntry(20);
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const baseGroup: AlbumGroup = groupOf(base);
      const baseId: string = rowReuseId(data, baseGroup, 'medium');

      const withReply: MessageEntry = cloneMessage(base);
      withReply.replyToMessageId = 5;
      expect(rowReuseId(data, groupOf(withReply), 'medium') === baseId).assertFalse();

      const withForward: MessageEntry = cloneMessage(base);
      withForward.forwardFrom = 'Alice';
      expect(rowReuseId(data, groupOf(withForward), 'medium') === baseId).assertFalse();

      const withReaction: MessageEntry = cloneMessage(base);
      withReaction.reactions = [{ emoji: '👍', count: 1, isChosen: false,
        customEmojiId: '', customEmojiPath: '' }];
      expect(rowReuseId(data, groupOf(withReaction), 'medium') === baseId).assertFalse();

      // isOutgoing on its own is not one of medium's tracked switches (it was
      // only ever a side effect of the fixed avatar/sender-name proxy this
      // file used before the AlbumGroup fix); an outgoing message with the
      // same group flags as an incoming one lands in the same medium bucket.
      const outgoing: AlbumGroup = groupOf(textEntry(21, true));
      expect(rowReuseId(data, outgoing, 'medium')).assertEqual(baseId);

      // Sender-name/avatar visibility is tracked via AlbumGroup.showAvatar/
      // showSenderName, not msg.senderName — msg.senderName differing alone
      // (with the group flag unchanged) must NOT move the medium bucket. The
      // group-flag-driven case is covered separately below
      // (avatar_flag_from_group_splits_medium_and_fine_but_not_coarse).
      const withSenderName: MessageEntry = cloneMessage(base);
      withSenderName.senderName = 'Bob';
      const withoutSenderName: MessageEntry = cloneMessage(base);
      withoutSenderName.senderName = '';
      expect(rowReuseId(data, groupOf(withSenderName), 'medium'))
        .assertEqual(rowReuseId(data, groupOf(withoutSenderName), 'medium'));
    });

    // Fix wave: the first cut of this file derived "has avatar"/"has sender
    // name" from data.isGroup + msg.isOutgoing (a structural proxy) because
    // the signature only took MessageEntry. That conflated mid-run rows with
    // run-head/tail rows even though LazyForEach's own row key
    // (collapseAlbums.ets:292) already tells them apart. These two cases pin
    // the real per-row flags now that the signature carries the AlbumGroup.
    it('avatar_flag_from_group_splits_medium_and_fine_but_not_coarse', 0, () => {
      const msg: MessageEntry = textEntry(70);
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const withAvatar: AlbumGroup = groupOf(msg, { showAvatar: true });
      const withoutAvatar: AlbumGroup = groupOf(cloneMessage(msg), { showAvatar: false });

      expect(rowReuseId(data, withAvatar, 'coarse'))
        .assertEqual(rowReuseId(data, withoutAvatar, 'coarse'));
      expect(rowReuseId(data, withAvatar, 'medium') ===
        rowReuseId(data, withoutAvatar, 'medium')).assertFalse();
      expect(rowReuseId(data, withAvatar, 'fine') ===
        rowReuseId(data, withoutAvatar, 'fine')).assertFalse();
    });

    it('date_separator_from_group_splits_medium_and_fine', 0, () => {
      const msg: MessageEntry = textEntry(71);
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const withDate: AlbumGroup = groupOf(msg, { dateLabel: 'Aug 26' });
      const withoutDate: AlbumGroup = groupOf(cloneMessage(msg), { dateLabel: '' });

      expect(rowReuseId(data, withDate, 'medium') ===
        rowReuseId(data, withoutDate, 'medium')).assertFalse();
      expect(rowReuseId(data, withDate, 'fine') ===
        rowReuseId(data, withoutDate, 'fine')).assertFalse();
    });

    it('unread_divider_from_render_data_splits_medium_and_fine', 0, () => {
      const group: AlbumGroup = groupOf(textEntry(72));
      const withUnread: MessageBubbleRenderData = renderData({ isGroup: true, showUnreadDivider: true });
      const withoutUnread: MessageBubbleRenderData = renderData({ isGroup: true, showUnreadDivider: false });
      expect(rowReuseId(withUnread, group, 'medium') ===
        rowReuseId(withoutUnread, group, 'medium')).assertFalse();
    });

    // translatedText is the biggest structural fork of all: it flips
    // ReusableMessageBubble.build()'s lightweight/full-bubble branch
    // (~215: `data.lightweightPlainText && group.head.translatedText === ''`),
    // swapping the entire subtree, not just a child node inside it. Covered
    // for both a lightweight-eligible plain-text row and a row that is
    // already routed to the full renderer (rich), since the translation
    // fork sits above/independent of the coarse plain/rich split.
    it('translation_on_plain_text_row_splits_medium_and_fine_not_coarse', 0, () => {
      const msg: MessageEntry = textEntry(73);
      const data: MessageBubbleRenderData = renderData({ isGroup: true, lightweightPlainText: true });
      const untranslated: AlbumGroup = groupOf(msg);
      const translatedMsg: MessageEntry = cloneMessage(msg);
      translatedMsg.translatedText = 'translated body';
      translatedMsg.translatedLang = 'en';
      const translated: AlbumGroup = groupOf(translatedMsg);

      expect(rowReuseId(data, untranslated, 'coarse'))
        .assertEqual(rowReuseId(data, translated, 'coarse'));
      expect(rowReuseId(data, untranslated, 'medium') ===
        rowReuseId(data, translated, 'medium')).assertFalse();
      expect(rowReuseId(data, untranslated, 'fine') ===
        rowReuseId(data, translated, 'fine')).assertFalse();
    });

    it('translation_on_rich_row_splits_medium_and_fine', 0, () => {
      const msg: MessageEntry = textEntry(74);
      msg.replyToMessageId = 5; // keep it 'rich', independent of the reply switch
      const data: MessageBubbleRenderData = renderData({ isGroup: true, lightweightPlainText: false });
      const untranslated: AlbumGroup = groupOf(msg);
      const translatedMsg: MessageEntry = cloneMessage(msg);
      translatedMsg.translatedText = 'translated body';
      translatedMsg.translatedLang = 'en';
      const translated: AlbumGroup = groupOf(translatedMsg);

      expect(rowReuseId(data, untranslated, 'medium') ===
        rowReuseId(data, translated, 'medium')).assertFalse();
      expect(rowReuseId(data, untranslated, 'fine') ===
        rowReuseId(data, translated, 'fine')).assertFalse();
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
        .map((m: MessageEntry): string => rowReuseId(data, groupOf(m), 'fine'));
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
      expect(rowReuseId(data, groupOf(photo), 'fine'))
        .assertEqual(rowReuseId(data, groupOf(photoTwin), 'fine'));

      // Fine level must not collapse back to medium's bucket count: text (no
      // media) still differs from photo even though medium treats them alike.
      expect(rowReuseId(data, groupOf(text), 'medium'))
        .assertEqual(rowReuseId(data, groupOf(photo), 'medium'));
      expect(rowReuseId(data, groupOf(text), 'fine') ===
        rowReuseId(data, groupOf(photo), 'fine')).assertFalse();
    });

    it('bucket_count_grows_from_coarse_to_fine', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const samples: AlbumGroup[] = [];
      const base: MessageEntry = textEntry(40);
      samples.push(groupOf(base));
      const reply: MessageEntry = cloneMessage(base);
      reply.replyToMessageId = 1;
      samples.push(groupOf(reply));
      const photo: MessageEntry = cloneMessage(base);
      photo.contentType = 'photo';
      samples.push(groupOf(photo));
      const video: MessageEntry = cloneMessage(base);
      video.contentType = 'video';
      samples.push(groupOf(video));

      const bucketCount = (level: ReuseIdLevel): number => {
        const seen = new Set<string>();
        for (const g of samples) {
          seen.add(rowReuseId(data, g, level));
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
        expect(rowReuseId(data, groupOf(first), level))
          .assertEqual(rowReuseId(data, groupOf(second), level));
      }
    });
  });
}
