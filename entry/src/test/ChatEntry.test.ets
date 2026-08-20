import { describe, it, expect } from '@ohos/hypium';
import {
  ChatEntry, computeInitials, compareOrderDesc, effectiveMuted, isMutedFrom, usesDefaultMuteFrom
} from '../main/ets/store/ChatEntry';
import { TdObject } from '../main/ets/tdkit/TdTypes';

export default function chatEntryTest() {
  describe('ChatEntry', () => {
    it('initials_two_words', 0, () => {
      expect(computeInitials('Linux Do')).assertEqual('LD');
    });
    it('initials_one_word', 0, () => {
      expect(computeInitials('Telegram')).assertEqual('T');
    });
    it('initials_empty', 0, () => {
      expect(computeInitials('')).assertEqual('?');
    });
    it('order_longer_is_bigger', 0, () => {
      // 7000000000 > 999999999 -> desc puts longer first (negative)
      expect(compareOrderDesc('7000000000', '999999999') < 0).assertEqual(true);
    });
    it('order_same_length_lexicographic', 0, () => {
      expect(compareOrderDesc('900', '800') < 0).assertEqual(true);
    });
    it('muted_true', 0, () => {
      const ns: TdObject = { '@type': 'chatNotificationSettings' };
      ns['mute_for'] = 3600;
      expect(isMutedFrom(ns)).assertEqual(true);
    });
    it('muted_false_undefined', 0, () => {
      expect(isMutedFrom(undefined)).assertEqual(false);
    });

    // use_default_mute_for 缺省视为 true —— TDLib 对新会话不一定下发该字段，
    // 当成 false 会让这些会话被误判为"已显式设置为不静音"。
    it('uses_default_mute_defaults_to_true', 0, () => {
      expect(usesDefaultMuteFrom(undefined)).assertEqual(true);
      expect(usesDefaultMuteFrom({ '@type': 'chatNotificationSettings' })).assertEqual(true);
    });

    it('uses_default_mute_reads_explicit_false', 0, () => {
      const ns: TdObject = { '@type': 'chatNotificationSettings' };
      ns['use_default_mute_for'] = false;
      expect(usesDefaultMuteFrom(ns)).assertEqual(false);
    });

    // 关键场景：会话本身 mute_for=0 看着像"没静音"，但它跟随作用域默认值，
    // 而群组默认是静音 —— 真实状态必须是静音。只看 mute_for 就会显示成反的。
    it('effective_mute_follows_scope_default_when_using_default', 0, () => {
      const entry = makeEntry(false, true);
      expect(effectiveMuted(entry, true)).assertEqual(true);
      expect(effectiveMuted(entry, false)).assertEqual(false);
    });

    it('effective_mute_ignores_scope_when_chat_has_own_setting', 0, () => {
      const own = makeEntry(true, false);
      expect(effectiveMuted(own, false)).assertEqual(true);
      const ownUnmuted = makeEntry(false, false);
      expect(effectiveMuted(ownUnmuted, true)).assertEqual(false);
    });
  });
}

// 只填 effectiveMuted 用得到的两个字段，其余取占位值。
function makeEntry(isMuted: boolean, usesDefaultMute: boolean): ChatEntry {
  return {
    id: 1, revision: 0, title: 't', isMuted, usesDefaultMute, unreadCount: 0,
    lastMessageText: '', lastMessageDate: 0, lastMessageId: 0, lastSenderName: '',
    photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'supergroup', isMarkedUnread: false, isSavedMessages: false, background: null, themeName: '',
    liveGroupCallId: 0, isLive: false, isRtmpLive: false
  };
}
