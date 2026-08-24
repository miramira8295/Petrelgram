import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import {
  canRenderLightweightPlainText, canReuseMessageBubble,
  MessageBubbleReuseContext, messageBubbleReuseId
} from '../main/ets/util/messageBubbleReuse';

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

function context(
  isGroup: boolean = false,
  showAvatar: boolean = false,
  showSenderName: boolean = false,
  isChannel: boolean = false
): MessageBubbleReuseContext {
  return {
    albumItemCount: 0,
    memberCount: 1,
    hasDateSeparator: false,
    showUnreadDivider: false,
    isGroup,
    isChannel,
    showAvatar,
    showSenderName,
    translationActive: false,
    menuEditable: false
  };
}

export default function plainTextBubbleReuseTest() {
  describe('MessageBubbleReuse', () => {
    it('routes_only_simple_text_to_lightweight_renderer', 0, () => {
      const simple: MessageEntry = textEntry(0);
      expect(canRenderLightweightPlainText(simple, context())).assertTrue();
      expect(messageBubbleReuseId(simple, context()).startsWith('plain-text:')).assertTrue();

      const reply: MessageEntry = cloneMessage(simple);
      reply.replyToMessageId = 99;
      expect(canRenderLightweightPlainText(reply, context(true, true, true))).assertTrue();

      const linked: MessageEntry = cloneMessage(simple);
      linked.text = 'https://example.com';
      expect(canRenderLightweightPlainText(linked, context())).assertFalse();
      const previewResolving: MessageEntry = cloneMessage(simple);
      previewResolving.linkPhotoPath = '/tmp/preview.jpg';
      expect(canRenderLightweightPlainText(previewResolving, context())).assertFalse();
      const reacted: MessageEntry = cloneMessage(simple);
      reacted.reactions = [{ emoji: '👍', count: 1, isChosen: false,
        customEmojiId: '', customEmojiPath: '' }];
      expect(canRenderLightweightPlainText(reacted, context())).assertFalse();
      const translating: MessageBubbleReuseContext = context();
      translating.translationActive = true;
      // The lightweight component renders the transient translating/error row;
      // once translatedText arrives, the normal data update promotes the row
      // to the complete renderer.
      expect(canRenderLightweightPlainText(simple, translating)).assertTrue();
    });
    it('accepts_private_plain_text', 0, () => {
      expect(canReuseMessageBubble(textEntry(1), context())).assertTrue();
      expect(canReuseMessageBubble(textEntry(2, true), context())).assertTrue();
    });

    it('accepts_text_feature_structures', 0, () => {
      const base: MessageEntry = textEntry(10);
      const variants: MessageEntry[] = [];
      let next: MessageEntry = cloneMessage(base);
      next.text = '   ';
      variants.push(next);
      next = cloneMessage(base);
      next.replyToMessageId = 9;
      variants.push(next);
      next = cloneMessage(base);
      next.forwardFrom = 'Alice';
      variants.push(next);
      next = cloneMessage(base);
      next.commentCount = 1;
      variants.push(next);
      next = cloneMessage(base);
      next.textEntities = [{ '@type': 'textEntity' }];
      variants.push(next);
      next = cloneMessage(base);
      next.text = 'visit https://example.com';
      variants.push(next);
      next = cloneMessage(base);
      next.text = 'hello @alice';
      variants.push(next);
      next = cloneMessage(base);
      next.text = 'read #topic';
      variants.push(next);
      next = cloneMessage(base);
      next.inlineCustomEmojiIds = ['99'];
      variants.push(next);
      next = cloneMessage(base);
      next.inlineCustomEmojiPaths = ['/tmp/99.webp'];
      variants.push(next);
      next = cloneMessage(base);
      next.linkUrl = 'https://example.com';
      variants.push(next);
      next = cloneMessage(base);
      next.reactions = [{ emoji: '👍', count: 1, isChosen: false,
        customEmojiId: '', customEmojiPath: '' }];
      variants.push(next);
      next = cloneMessage(base);
      next.inlineButtons = [[{ text: 'Open', url: 'https://example.com', callbackData: '',
        isGame: false, style: '' }]];
      variants.push(next);
      next = cloneMessage(base);
      next.translatedText = 'translated';
      next.translatedLang = 'en';
      variants.push(next);

      for (const candidate of variants) {
        expect(canReuseMessageBubble(candidate, context())).assertTrue();
      }
    });

    it('accepts_all_fixed_signature_group_positions', 0, () => {
      const incoming: MessageEntry = textEntry(20);
      expect(canReuseMessageBubble(incoming, context(true, false, false))).assertTrue();
      expect(canReuseMessageBubble(incoming, context(true, true, false))).assertTrue();
      expect(canReuseMessageBubble(incoming, context(true, false, true))).assertTrue();
      expect(canReuseMessageBubble(incoming, context(true, true, true))).assertTrue();
      expect(canReuseMessageBubble(textEntry(21, true), context(true, true, true))).assertTrue();
    });

    it('accepts_row_shell_album_and_transient_translation', 0, () => {
      const entry: MessageEntry = textEntry(30);
      const dateCtx: MessageBubbleReuseContext = context();
      dateCtx.hasDateSeparator = true;
      expect(canReuseMessageBubble(entry, dateCtx)).assertTrue();
      const unreadCtx: MessageBubbleReuseContext = context();
      unreadCtx.showUnreadDivider = true;
      expect(canReuseMessageBubble(entry, unreadCtx)).assertTrue();
      const albumCtx: MessageBubbleReuseContext = context();
      albumCtx.albumItemCount = 3;
      albumCtx.memberCount = 3;
      albumCtx.albumShape = '3:prfo:vrfo:pnfe';
      expect(canReuseMessageBubble(entry, albumCtx)).assertTrue();
      const albumEntry: MessageEntry = cloneMessage(entry);
      albumEntry.albumId = 'album';
      expect(canReuseMessageBubble(albumEntry, context())).assertTrue();
      const translationCtx: MessageBubbleReuseContext = context();
      translationCtx.translationActive = true;
      expect(canReuseMessageBubble(entry, translationCtx)).assertTrue();
    });

    it('accepts_every_message_family', 0, () => {
      const families: string[] = [
        'richMessage', 'photo', 'video', 'videoNote', 'voice', 'audio', 'file',
        'contact', 'location', 'venue', 'poll', 'dice', 'game', 'paidMedia',
        'gift', 'giveaway', 'emoji', 'customEmoji', 'sticker', 'system', 'hidden',
        'futureUnsupported'
      ];
      for (const family of families) {
        const entry: MessageEntry = cloneMessage(textEntry(35));
        entry.contentType = family;
        entry.isUnsupportedMessage = family === 'futureUnsupported';
        expect(canReuseMessageBubble(entry, context())).assertTrue();
      }
    });

    it('reuse_id_tracks_structure_not_message_identity', 0, () => {
      const first: MessageEntry = textEntry(40);
      const second: MessageEntry = textEntry(41);
      second.text = 'different content and width';
      expect(messageBubbleReuseId(first, context()))
        .assertEqual(messageBubbleReuseId(second, context()));
      expect(messageBubbleReuseId(first, context()) ===
        messageBubbleReuseId(textEntry(42, true), context())).assertFalse();
      expect(messageBubbleReuseId(first, context(false, false, false, false)) ===
        messageBubbleReuseId(first, context(false, true, false, false))).assertFalse();
      const edited: MessageEntry = cloneMessage(first);
      edited.editDate = 101;
      expect(messageBubbleReuseId(first, context()) ===
        messageBubbleReuseId(edited, context())).assertFalse();
      const editableCtx: MessageBubbleReuseContext = context();
      editableCtx.menuEditable = true;
      expect(messageBubbleReuseId(first, context()) ===
        messageBubbleReuseId(first, editableCtx)).assertFalse();
      const anonymous: MessageEntry = cloneMessage(first);
      anonymous.senderIsUser = false;
      anonymous.senderId = 0;
      expect(messageBubbleReuseId(first, context(true)) ===
        messageBubbleReuseId(anonymous, context(true))).assertFalse();
      const reply: MessageEntry = cloneMessage(first);
      reply.replyToMessageId = 1;
      expect(messageBubbleReuseId(first, context()) ===
        messageBubbleReuseId(reply, context())).assertFalse();
      const linked: MessageEntry = cloneMessage(first);
      linked.text = 'visit https://example.com';
      expect(messageBubbleReuseId(first, context()) ===
        messageBubbleReuseId(linked, context())).assertFalse();
      const translated: MessageEntry = cloneMessage(first);
      translated.translatedText = 'translated';
      translated.translatedLang = 'en';
      expect(messageBubbleReuseId(first, context()) ===
        messageBubbleReuseId(translated, context())).assertFalse();
    });

    it('reuse_id_tracks_media_album_and_stateful_child_structure', 0, () => {
      const video: MessageEntry = cloneMessage(textEntry(50));
      video.contentType = 'video';
      video.videoFileId = 100;
      video.photoFileId = 101;
      const idleVideoCtx: MessageBubbleReuseContext = context();
      const playingVideoCtx: MessageBubbleReuseContext = context();
      playingVideoCtx.playSlotActive = true;
      expect(messageBubbleReuseId(video, idleVideoCtx) ===
        messageBubbleReuseId(video, playingVideoCtx)).assertFalse();

      const audio: MessageEntry = cloneMessage(textEntry(51));
      audio.contentType = 'audio';
      audio.text = '';
      const noQueueCtx: MessageBubbleReuseContext = context();
      const queueCtx: MessageBubbleReuseContext = context();
      queueCtx.audioQueuePosition = 2;
      queueCtx.audioQueueLength = 4;
      expect(messageBubbleReuseId(audio, noQueueCtx) ===
        messageBubbleReuseId(audio, queueCtx)).assertFalse();

      const albumA: MessageBubbleReuseContext = context();
      albumA.albumItemCount = 2;
      albumA.memberCount = 2;
      albumA.albumShape = '2:prfo:vrfo';
      albumA.albumCaptionShape = 'caption-plain';
      const albumB: MessageBubbleReuseContext = context();
      albumB.albumItemCount = 2;
      albumB.memberCount = 2;
      albumB.albumShape = '2:prfo:vrfo';
      albumB.albumCaptionShape = 'caption-link';
      expect(messageBubbleReuseId(video, albumA) ===
        messageBubbleReuseId(video, albumB)).assertFalse();
    });

    it('reuse_id_tracks_poll_game_and_menu_branches', 0, () => {
      const poll: MessageEntry = cloneMessage(textEntry(60));
      poll.contentType = 'poll';
      poll.text = '';
      poll.pollIsAnonymous = true;
      const publicPoll: MessageEntry = cloneMessage(poll);
      publicPoll.pollIsAnonymous = false;
      expect(messageBubbleReuseId(poll, context()) ===
        messageBubbleReuseId(publicPoll, context())).assertFalse();

      const activePollCtx: MessageBubbleReuseContext = context();
      const expiredPollCtx: MessageBubbleReuseContext = context();
      expiredPollCtx.pollExpired = true;
      expect(messageBubbleReuseId(poll, activePollCtx) ===
        messageBubbleReuseId(poll, expiredPollCtx)).assertFalse();

      const game: MessageEntry = cloneMessage(textEntry(61));
      game.contentType = 'game';
      game.text = '';
      game.gameDescription = 'description';
      const detailedGame: MessageEntry = cloneMessage(game);
      detailedGame.gameText = 'extra game text';
      expect(messageBubbleReuseId(game, context()) ===
        messageBubbleReuseId(detailedGame, context())).assertFalse();

      const voice: MessageEntry = cloneMessage(textEntry(62));
      voice.contentType = 'voice';
      voice.text = '';
      const captionedVoice: MessageEntry = cloneMessage(voice);
      captionedVoice.text = 'translatable caption';
      expect(messageBubbleReuseId(voice, context()) ===
        messageBubbleReuseId(captionedVoice, context())).assertFalse();
    });
  });
}
