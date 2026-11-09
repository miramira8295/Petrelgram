import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageStore } from '../main/ets/store/MessageStore';
import { MessageEntry, ReactionInfo, reactionsFromInteraction } from '../main/ets/store/MessageEntry';
import {
  AvailableReactionSet, ReactionKey, customEmojiReactionKey, isCustomEmojiReactionKey,
  parseAvailableReactions, parseReactionKey, reactionDisplayLabel, reactionKeyFrom, reactionTypeOf
} from '../main/ets/util/reactions';
import { customEmojiThumbFileId } from '../main/ets/util/customEmojiThumbs';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function setup(chatId: number): Array<Object> {
  const b = new FakeBridge();
  const c = new TdClient(b);
  const u = new UserStore(c);
  const store = new MessageStore(c, u, chatId, 0, 30);
  c.start();
  return [b, store];
}

function extraOf(json: string): string {
  const o = JSON.parse(json) as TdObject;
  return (o['@extra'] as string | undefined) ?? '';
}

function feedChat(b: FakeBridge, chatId: number): void {
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChat') { extra = extraOf(s); }
  }
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = chatId;
  chat['@extra'] = extra;
  b.onReceive(JSON.stringify(chat));
}

function feedHistory(b: FakeBridge, msgs: TdObject[]): void {
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChatHistory') { extra = extraOf(s); }
  }
  const res: TdObject = { '@type': 'messages' };
  res['total_count'] = msgs.length;
  res['messages'] = msgs;
  res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}

function tick(): Promise<void> {
  return new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
}

function textMessage(id: number, chatId: number, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}

function customEmojiReactionUpdate(chatId: number, messageId: number, ceId: string): TdObject {
  const type: TdObject = { '@type': 'reactionTypeCustomEmoji' };
  type['custom_emoji_id'] = ceId;
  const reaction: TdObject = { '@type': 'messageReaction' };
  reaction['type'] = type;
  reaction['total_count'] = 3;
  reaction['is_chosen'] = true;
  const reactions: TdObject = { '@type': 'messageReactions' };
  reactions['reactions'] = [reaction];
  const ii: TdObject = { '@type': 'messageInteractionInfo' };
  ii['reactions'] = reactions;
  const u: TdObject = { '@type': 'updateMessageInteractionInfo' };
  u['chat_id'] = chatId;
  u['message_id'] = messageId;
  u['interaction_info'] = ii;
  return u;
}

function availableReactionOf(typeName: string, value: string): TdObject {
  const type: TdObject = { '@type': typeName };
  if (typeName === 'reactionTypeEmoji') {
    type['emoji'] = value;
  } else {
    type['custom_emoji_id'] = value;
  }
  const item: TdObject = { '@type': 'availableReaction' };
  item['type'] = type;
  item['needs_premium'] = false;
  return item;
}

function sentOfType(b: FakeBridge, type: string): TdObject[] {
  return b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
    .filter((request: TdObject): boolean => request['@type'] === type);
}

export default function customEmojiReactionsTest() {
  describe('CustomEmojiReactions', () => {
    it('reaction_key_round_trips_for_both_reaction_types', 0, () => {
      const customKey: string = customEmojiReactionKey('5789098845777254222');
      expect(customKey).assertEqual('ce:5789098845777254222');
      expect(isCustomEmojiReactionKey(customKey)).assertTrue();
      expect(isCustomEmojiReactionKey('👍')).assertFalse();
      const parsedCustom: ReactionKey = parseReactionKey(customKey);
      expect(parsedCustom.customEmojiId).assertEqual('5789098845777254222');
      expect(parsedCustom.emoji).assertEqual('');
      const parsedStandard: ReactionKey = parseReactionKey('👍');
      expect(parsedStandard.emoji).assertEqual('👍');
      expect(parsedStandard.customEmojiId).assertEqual('');
      expect(reactionKeyFrom('👍', '')).assertEqual('👍');
      expect(reactionKeyFrom('', '42')).assertEqual('ce:42');
      expect(reactionDisplayLabel('ce:42')).assertEqual('reactions_custom_emoji');
      expect(reactionDisplayLabel('👍')).assertEqual('👍');
    });

    it('reaction_type_keeps_custom_emoji_id_as_string', 0, () => {
      const custom: TdObject = reactionTypeOf('ce:5789098845777254222');
      expect(custom['@type']).assertEqual('reactionTypeCustomEmoji');
      // int64 必须以字符串下发，转成 number 会在 2^53 之上丢精度。
      expect(typeof custom['custom_emoji_id']).assertEqual('string');
      expect(JSON.stringify(custom))
        .assertEqual('{"@type":"reactionTypeCustomEmoji","custom_emoji_id":"5789098845777254222"}');
      const standard: TdObject = reactionTypeOf('👍');
      expect(JSON.stringify(standard))
        .assertEqual('{"@type":"reactionTypeEmoji","emoji":"👍"}');
    });

    it('available_reactions_split_by_type_and_dedupe', 0, () => {
      const result: TdObject = { '@type': 'availableReactions' };
      result['top_reactions'] = [
        availableReactionOf('reactionTypeEmoji', '👍'),
        availableReactionOf('reactionTypeCustomEmoji', '111')
      ];
      result['recent_reactions'] = [
        availableReactionOf('reactionTypeEmoji', '👍'),
        availableReactionOf('reactionTypeCustomEmoji', '111'),
        availableReactionOf('reactionTypeCustomEmoji', '222'),
        availableReactionOf('reactionTypeCustomEmoji', '0')
      ];
      result['allow_custom_emoji'] = true;
      const parsed: AvailableReactionSet = parseAvailableReactions(result);
      expect(parsed.emojis.join(',')).assertEqual('👍');
      expect(parsed.customEmojiIds.join(',')).assertEqual('111,222');
      expect(parsed.allowCustomEmoji).assertTrue();
    });

    it('available_reactions_default_to_no_custom_emoji', 0, () => {
      const result: TdObject = { '@type': 'availableReactions' };
      result['top_reactions'] = [availableReactionOf('reactionTypeEmoji', '🔥')];
      const parsed: AvailableReactionSet = parseAvailableReactions(result);
      expect(parsed.allowCustomEmoji).assertFalse();
      expect(parsed.customEmojiIds.length).assertEqual(0);
    });

    it('interaction_info_parses_custom_emoji_reactions', 0, () => {
      const type: TdObject = { '@type': 'reactionTypeCustomEmoji' };
      type['custom_emoji_id'] = '777';
      const custom: TdObject = { '@type': 'messageReaction' };
      custom['type'] = type;
      custom['total_count'] = 2;
      custom['is_chosen'] = true;
      const standardType: TdObject = { '@type': 'reactionTypeEmoji' };
      standardType['emoji'] = '👍';
      const standard: TdObject = { '@type': 'messageReaction' };
      standard['type'] = standardType;
      standard['total_count'] = 5;
      standard['is_chosen'] = false;
      const reactions: TdObject = { '@type': 'messageReactions' };
      reactions['reactions'] = [standard, custom];
      const ii: TdObject = { '@type': 'messageInteractionInfo' };
      ii['reactions'] = reactions;
      const parsed: ReactionInfo[] = reactionsFromInteraction(ii);
      expect(parsed.length).assertEqual(2);
      expect(parsed[0].emoji).assertEqual('👍');
      expect(parsed[0].customEmojiId).assertEqual('');
      expect(parsed[1].emoji).assertEqual('');
      expect(parsed[1].customEmojiId).assertEqual('777');
      expect(parsed[1].count).assertEqual(2);
      expect(parsed[1].isChosen).assertTrue();
      expect(parsed[1].customEmojiPath).assertEqual('');
    });

    it('set_reaction_sends_custom_emoji_add_request', 0, async () => {
      const arr = setup(5);
      const b = arr[0] as FakeBridge;
      const store = arr[1] as MessageStore;
      store.setReaction(42, 'ce:998877', false);
      const requests: TdObject[] = sentOfType(b, 'addMessageReaction');
      expect(requests.length).assertEqual(1);
      const req: TdObject = requests[0];
      expect(req['chat_id']).assertEqual(5);
      expect(req['message_id']).assertEqual(42);
      expect(req['is_big']).assertEqual(false);
      expect(req['update_recent_reactions']).assertEqual(true);
      const type = req['reaction_type'] as TdObject;
      expect(type['@type']).assertEqual('reactionTypeCustomEmoji');
      expect(type['custom_emoji_id']).assertEqual('998877');
      expect(sentOfType(b, 'removeMessageReaction').length).assertEqual(0);
    });

    it('set_reaction_removes_chosen_custom_emoji', 0, async () => {
      const arr = setup(5);
      const b = arr[0] as FakeBridge;
      const store = arr[1] as MessageStore;
      store.setReaction(42, 'ce:998877', true);
      const requests: TdObject[] = sentOfType(b, 'removeMessageReaction');
      expect(requests.length).assertEqual(1);
      const type = requests[0]['reaction_type'] as TdObject;
      expect(type['@type']).assertEqual('reactionTypeCustomEmoji');
      expect(type['custom_emoji_id']).assertEqual('998877');
      expect(sentOfType(b, 'addMessageReaction').length).assertEqual(0);
    });

    it('set_reaction_still_sends_plain_emoji_type', 0, async () => {
      const arr = setup(5);
      const b = arr[0] as FakeBridge;
      const store = arr[1] as MessageStore;
      store.setReaction(42, '👍', false);
      const type = sentOfType(b, 'addMessageReaction')[0]['reaction_type'] as TdObject;
      expect(type['@type']).assertEqual('reactionTypeEmoji');
      expect(type['emoji']).assertEqual('👍');
    });

    it('custom_emoji_reaction_triggers_sticker_resolution', 0, async () => {
      const arr = setup(5);
      const b = arr[0] as FakeBridge;
      const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await tick();
      feedHistory(b, [textMessage(10, 5, 'hi')]);
      await tick();
      b.onReceive(JSON.stringify(customEmojiReactionUpdate(5, 10, '5555')));
      await tick();
      const entry: MessageEntry = store.getMessages()[0];
      expect(entry.reactions.length).assertEqual(1);
      expect(entry.reactions[0].customEmojiId).assertEqual('5555');
      // 位图还没到，气泡靠 customEmojiPath === '' 渲染占位。
      expect(entry.reactions[0].customEmojiPath).assertEqual('');
      const requests: TdObject[] = sentOfType(b, 'getCustomEmojiStickers');
      expect(requests.length).assertEqual(1);
      expect(((requests[0]['custom_emoji_ids'] as string[] | undefined) ?? []).join(','))
        .assertEqual('5555');
    });

    it('thumb_file_id_prefers_thumbnail_then_static_webp', 0, () => {
      const thumbFile: TdObject = { '@type': 'file' };
      thumbFile['id'] = 91;
      const thumb: TdObject = { '@type': 'thumbnail' };
      thumb['file'] = thumbFile;
      const source: TdObject = { '@type': 'file' };
      source['id'] = 17;
      const animated: TdObject = { '@type': 'sticker' };
      animated['format'] = { '@type': 'stickerFormatTgs' } as TdObject;
      animated['sticker'] = source;
      animated['thumbnail'] = thumb;
      expect(customEmojiThumbFileId(animated)).assertEqual(91);

      const staticWebp: TdObject = { '@type': 'sticker' };
      staticWebp['format'] = { '@type': 'stickerFormatWebp' } as TdObject;
      staticWebp['sticker'] = source;
      expect(customEmojiThumbFileId(staticWebp)).assertEqual(17);

      // 无缩略图的 TGS/WEBM 拿不到可直接渲染的位图。
      const animatedNoThumb: TdObject = { '@type': 'sticker' };
      animatedNoThumb['format'] = { '@type': 'stickerFormatWebm' } as TdObject;
      animatedNoThumb['sticker'] = source;
      expect(customEmojiThumbFileId(animatedNoThumb)).assertEqual(0);
    });
  });
}
