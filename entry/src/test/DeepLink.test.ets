import { describe, it, expect } from '@ohos/hypium';
import { OpenMessageTarget, parseOpenMessageLink, tgSchemeToUrl } from '../main/ets/util/deepLink';

export default function deepLinkTest() {
  describe('deepLink', () => {
    it('maps_resolve_and_join_to_tme_urls', 0, () => {
      expect(tgSchemeToUrl('tg://resolve?domain=foo&post=12')).assertEqual('https://t.me/foo/12');
      expect(tgSchemeToUrl('tg://resolve?domain=foo')).assertEqual('https://t.me/foo');
      expect(tgSchemeToUrl('tg://join?invite=HASH')).assertEqual('https://t.me/+HASH');
      // 非 tg:// 与未知 action 原样返回，交给下游路由。
      expect(tgSchemeToUrl('https://t.me/foo')).assertEqual('https://t.me/foo');
      // 系统递过来的没有双斜杠：实测 want.uri = "tg:resolve?domain=Petrelgram"。
      // 少了这一支，浏览器点进来的链接会原样交给 TDLib，最后弹"无法识别"。
      expect(tgSchemeToUrl('tg:resolve?domain=foo')).assertEqual('https://t.me/foo');
      expect(tgSchemeToUrl('tg:resolve?domain=foo&post=12')).assertEqual('https://t.me/foo/12');
      expect(tgSchemeToUrl('tg:join?invite=HASH')).assertEqual('https://t.me/+HASH');
      // 不是 tg 的一律不动，别把别的 scheme 也补上斜杠。
      expect(tgSchemeToUrl('tgx:resolve?domain=foo')).assertEqual('tgx:resolve?domain=foo');
      expect(tgSchemeToUrl('mailto:a@b.c')).assertEqual('mailto:a@b.c');
      expect(tgSchemeToUrl('tg://user?id=7')).assertEqual('tg://user?id=7');
    });

    // 频道：td_api chat_id = ZERO_CHANNEL_ID - channel_id（TDLib DialogId.h:27）
    it('converts_channel_id_to_td_chat_id', 0, () => {
      const t = parseOpenMessageLink('tg://openmessage?channel_id=1536172802&msg_id=3') as OpenMessageTarget;
      expect(t !== null).assertTrue();
      expect(t.chatId).assertEqual(-1001536172802);
      expect(t.messageId).assertEqual(3 * 1048576);
    });

    it('converts_basic_group_id_to_negative_chat_id', 0, () => {
      const t = parseOpenMessageLink('tg://openmessage?chat_id=12345&msg_id=7') as OpenMessageTarget;
      expect(t.chatId).assertEqual(-12345);
      expect(t.messageId).assertEqual(7 * 1048576);
    });

    it('keeps_user_id_positive_and_accepts_from_id_alias', 0, () => {
      const a = parseOpenMessageLink('tg://openmessage?from_id=778899&msg_id=1') as OpenMessageTarget;
      expect(a.chatId).assertEqual(778899);
      const b = parseOpenMessageLink('tg://openmessage?user_id=778899&msg_id=1') as OpenMessageTarget;
      expect(b.chatId).assertEqual(778899);
    });

    // msg_id 缺失是合法的：只打开会话，不跳转到具体消息。
    it('allows_missing_msg_id', 0, () => {
      const t = parseOpenMessageLink('tg://openmessage?channel_id=5') as OpenMessageTarget;
      expect(t.chatId).assertEqual(-1000000000005);
      expect(t.messageId).assertEqual(0);
    });

    // 大 server id 乘 2^20 仍需落在 Number.isSafeInteger 范围内，否则跳转会
    // 指向一条不存在的消息。int32 上限 2147483647 是最坏情况。
    it('keeps_max_server_message_id_within_safe_integer_range', 0, () => {
      const t = parseOpenMessageLink('tg://openmessage?channel_id=1&msg_id=2147483647') as OpenMessageTarget;
      expect(Number.isSafeInteger(t.messageId)).assertTrue();
      expect(t.messageId).assertEqual(2147483647 * 1048576);
    });

    it('rejects_links_without_any_peer', 0, () => {
      expect(parseOpenMessageLink('tg://openmessage?msg_id=5') === null).assertTrue();
      expect(parseOpenMessageLink('tg://resolve?domain=foo') === null).assertTrue();
      expect(parseOpenMessageLink('https://t.me/foo') === null).assertTrue();
      expect(parseOpenMessageLink('tg://openmessage') === null).assertTrue();
    });

    // 非纯数字不能被 parseInt 式地截断成一个有效 id。
    it('rejects_non_numeric_ids', 0, () => {
      expect(parseOpenMessageLink('tg://openmessage?channel_id=12abc') === null).assertTrue();
      const t = parseOpenMessageLink('tg://openmessage?channel_id=5&msg_id=9x') as OpenMessageTarget;
      expect(t.messageId).assertEqual(0);
    });
  });
}
