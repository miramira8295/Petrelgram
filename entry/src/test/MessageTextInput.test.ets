import { describe, expect, it } from '@ohos/hypium';
import { MessageTextPresentationCache, MessageTextLayout, TRANSLATION_TEXT_INPUT } from '../main/ets/util/messageTextInput';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';

class TextInputBridge implements TdBridge {
  init(_cb: (json: string) => void): void {}
  send(_json: string): void {}
}
function message(): MessageEntry {
  const raw: TdObject = { '@type': 'message' }; raw['id'] = 701;
  return buildMessageEntry(raw, new UserStore(new TdClient(new TextInputBridge())));
}
function layout(): MessageTextLayout {
  return { contentWidth: 390, isGroup: true, isChannel: false };
}

export default function messageTextInputTest(): void {
  describe('MessageTextInput', (): void => {
    it('unrelated_parent_snapshot_replacement_keeps_text_presentation', 0, (): void => {
      const cache = new MessageTextPresentationCache(); const msg = message();
      const first = cache.prepare(msg, false, layout(), 'caption', msg.textEntities, 0, 'caption');
      expect(cache.prepare(msg, false, layout(), 'caption', msg.textEntities, 0, 'caption') === first).assertTrue();
    });
    it('sender_label_and_layout_changes_replace_snapshot_without_mutating_old_width', 0, (): void => {
      const cache = new MessageTextPresentationCache(); const msg = message(); const data = layout();
      const first = cache.prepare(msg, false, data, 'caption', msg.textEntities, 0, 'caption');
      const sender = cache.prepare(msg, true, data, 'caption', msg.textEntities, 0, 'caption');
      expect(sender === first).assertFalse(); expect(sender.showSenderName).assertTrue();
      data.contentWidth = 700;
      const wider = cache.prepare(msg, true, data, 'caption', msg.textEntities, 0, 'caption');
      expect(wider === sender).assertFalse(); expect(first.layout.contentWidth).assertEqual(390);
      data.isGroup = false;
      const direct = cache.prepare(msg, true, data, 'caption', msg.textEntities, 0, 'caption');
      expect(direct === wider).assertFalse(); expect(direct.layout.isGroup).assertFalse();
      data.isChannel = true;
      expect(cache.prepare(msg, true, data, 'caption', msg.textEntities, 0, 'caption') === direct).assertFalse();
    });
    it('message_replacement_refreshes_translation_and_sent_message_identity', 0, (): void => {
      const cache = new MessageTextPresentationCache(); const msg = message();
      const first = cache.prepare(msg, false, layout(), '', msg.textEntities, 0, 'translation');
      const next = cloneMessage(msg); next.id = 702; next.translatedText = '译文'; next.translationHidden = true;
      const translated = cache.prepare(next, false, layout(), '', msg.textEntities, 0, 'translation');
      expect(translated === first).assertFalse(); expect(translated.msg.id).assertEqual(702);
      expect(translated.msg.translatedText).assertEqual('译文'); expect(translated.msg.translationHidden).assertTrue();
      expect(first.msg.id).assertEqual(701);
    });
    it('same_text_new_entities_refreshes_formatting_and_spoilers', 0, (): void => {
      const cache = new MessageTextPresentationCache(); const msg = message();
      const first = cache.prepare(msg, false, layout(), 'text', msg.textEntities, 0, 'caption');
      const type: TdObject = { '@type': 'textEntityTypeSpoiler' };
      const entity: TdObject = { '@type': 'textEntity' }; entity['offset'] = 0; entity['length'] = 4; entity['type'] = type;
      const entities: TdObject[] = [entity];
      const next = cache.prepare(msg, false, layout(), 'text', entities, 0, 'caption');
      expect(next === first).assertFalse(); expect(next.input.entities === entities).assertTrue();
      expect(first.input.entities.length).assertEqual(0);
    });
    it('text_mode_and_explicit_width_invalidate_independently', 0, (): void => {
      const cache = new MessageTextPresentationCache(); const msg = message();
      const first = cache.prepare(msg, false, layout(), 'text', msg.textEntities, 100, 'body');
      const edit = cache.prepare(msg, false, layout(), 'edited', msg.textEntities, 100, 'body');
      const width = cache.prepare(msg, false, layout(), 'edited', msg.textEntities, 200, 'body');
      const mode = cache.prepare(msg, false, layout(), 'edited', msg.textEntities, 200, 'caption');
      expect(first === edit || edit === width || width === mode).assertFalse();
      expect(first.input.text).assertEqual('text'); expect(first.input.maxWidth).assertEqual(100);
    });
    it('body_and_translation_owners_do_not_evict_each_other', 0, (): void => {
      const body = new MessageTextPresentationCache(); const footer = new MessageTextPresentationCache(); const msg = message();
      const first = body.prepare(msg, false, layout(), 'text', msg.textEntities, 100, 'body');
      const translated = footer.prepare(msg, false, layout(), '', TRANSLATION_TEXT_INPUT.entities, 0, 'translation');
      expect(body.prepare(msg, false, layout(), 'text', msg.textEntities, 100, 'body') === first).assertTrue();
      expect(footer.prepare(msg, false, layout(), '', TRANSLATION_TEXT_INPUT.entities, 0, 'translation') === translated).assertTrue();
      expect(translated.input.mode).assertEqual('translation');
    });
  });
}
