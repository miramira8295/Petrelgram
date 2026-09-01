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
    photoPaths: [], photoFileIds: [], photoRatios: [], photoIsVideo: [], photoIsLive: [],
    photoProgress: [], photoFailed: [],
    videoFileIds: [], videoFileSizes: [], videoDurations: [], videoMimeTypes: [],
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

      // msg.isOutgoing is its own structural axis, independent of and
      // additive to group.showAvatar/showSenderName: it flips which child of
      // the tail Row comes first (MessageBubble.ets ~3471-3475 vs ~3610-
      // 3614) and gates a trailing statusIcon() node. Fix wave 3: this used
      // to be asserted as "no effect at medium" because the prior wave's
      // avatar/sender-name fix dropped direction as a side effect of
      // removing the old (flawed) proxy — that was a real regression, not a
      // deliberate design choice, so this now asserts the opposite.
      const outgoing: AlbumGroup = groupOf(textEntry(21, true));
      expect(rowReuseId(data, outgoing, 'medium') === baseId).assertFalse();

      // Sender-name visibility is `group.showSenderName && head.senderName
      // !== ''` (MessageBubble.ets:3494) — the conjunction, not
      // showSenderName alone. With the group flag held fixed (both groups
      // default showSenderName: true here), msg.senderName differing alone
      // still has to move the bucket: a channel post / anonymous admin with
      // showSenderName=true but senderName === '' renders no name node at
      // all, unlike a row that does render one.
      const withSenderName: MessageEntry = cloneMessage(base);
      withSenderName.senderName = 'Bob';
      const withoutSenderName: MessageEntry = cloneMessage(base);
      withoutSenderName.senderName = '';
      expect(rowReuseId(data, groupOf(withSenderName), 'medium') ===
        rowReuseId(data, groupOf(withoutSenderName), 'medium')).assertFalse();
    });

    it('bare_surface_rows_never_share_a_medium_bucket_with_bubbles', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const text: MessageEntry = textEntry(90);
      const emoji: MessageEntry = cloneMessage(text);
      emoji.contentType = 'emoji';
      const sticker: MessageEntry = cloneMessage(text);
      sticker.contentType = 'sticker';
      // 文本行带玻璃轮廓和尾巴，裸表情没有：复用串档就是「表情带边框」。
      expect(rowReuseId(data, groupOf(text), 'medium') === rowReuseId(data, groupOf(emoji), 'medium')).assertFalse();
      // 两种裸面之间在 medium 档仍然共池（都没有气泡面），细分留给 fine。
      expect(rowReuseId(data, groupOf(emoji), 'medium') === rowReuseId(data, groupOf(sticker), 'medium')).assertTrue();
    });

    it('content_kind_hidden_system_normal_are_three_distinct_medium_buckets', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const normal: MessageEntry = textEntry(80);
      const hidden: MessageEntry = cloneMessage(normal);
      hidden.contentType = 'hidden';
      const system: MessageEntry = cloneMessage(normal);
      system.contentType = 'system';

      const ids: string[] = [normal, hidden, system]
        .map((m: MessageEntry): string => rowReuseId(data, groupOf(m), 'medium'));
      expect(ids[0] === ids[1]).assertFalse();
      expect(ids[0] === ids[2]).assertFalse();
      expect(ids[1] === ids[2]).assertFalse();

      // fine must not paper back over the split by folding hidden/system
      // into the same 'none' media kind as a plain text row.
      const fineIds: string[] = [normal, hidden, system]
        .map((m: MessageEntry): string => rowReuseId(data, groupOf(m), 'fine'));
      expect(fineIds[0] === fineIds[1]).assertFalse();
      expect(fineIds[0] === fineIds[2]).assertFalse();
      expect(fineIds[1] === fineIds[2]).assertFalse();
    });

    it('link_preview_fields_split_medium_and_fine', 0, () => {
      const data: MessageBubbleRenderData = renderData({ isGroup: true });
      const plain: MessageEntry = textEntry(81);
      const linked: MessageEntry = cloneMessage(plain);
      linked.linkUrl = 'https://example.com';
      linked.linkSiteName = 'Example';

      expect(rowReuseId(data, groupOf(plain), 'medium') ===
        rowReuseId(data, groupOf(linked), 'medium')).assertFalse();
      expect(rowReuseId(data, groupOf(plain), 'fine') ===
        rowReuseId(data, groupOf(linked), 'fine')).assertFalse();

      // Only linkPhotoFileId differing (the fifth field in hasLinkPreview)
      // must also move the bucket.
      const linkedByPhotoOnly: MessageEntry = cloneMessage(plain);
      linkedByPhotoOnly.linkPhotoFileId = 555;
      expect(rowReuseId(data, groupOf(plain), 'medium') ===
        rowReuseId(data, groupOf(linkedByPhotoOnly), 'medium')).assertFalse();
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
    // (~224: `data.lightweightPlainText && group.head.translatedText === ''`),
    // swapping the entire subtree, not just a child node inside it. Fix wave
    // 3: coarseBucket's real condition includes translatedText too — a
    // lightweight-eligible row that picks up a translation still renders the
    // full MessageBubble tree, so coarse must split here as well, not just
    // medium/fine (this is the corrected assertion; the prior wave asserted
    // coarse stayed equal, which is the bug the audit's item 3 called out).
    it('translation_on_plain_text_row_splits_every_level', 0, () => {
      const msg: MessageEntry = textEntry(73);
      const data: MessageBubbleRenderData = renderData({ isGroup: true, lightweightPlainText: true });
      const untranslated: AlbumGroup = groupOf(msg);
      const translatedMsg: MessageEntry = cloneMessage(msg);
      translatedMsg.translatedText = 'translated body';
      translatedMsg.translatedLang = 'en';
      const translated: AlbumGroup = groupOf(translatedMsg);

      expect(rowReuseId(data, untranslated, 'coarse') ===
        rowReuseId(data, translated, 'coarse')).assertFalse();
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
