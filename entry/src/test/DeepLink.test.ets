import { describe, it, expect } from '@ohos/hypium';
import { OpenMessageTarget, isHandledDeepLinkUri, parseOpenMessageLink, tgSchemeToUrl }
  from '../main/ets/util/deepLink';

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

    // —— 守卫：哪些 uri 才当链接打开 ——
    //
    // 真机实测（2026-09-16）：点通知拉起时系统把动作编码进 want.uri，
    // 值是 abilityEvent:clickAlertMessage。原来只判非空，它就被当成深链
    // 送进解析器，最后弹"无法识别该 Telegram 链接"——而通知里没有任何链接。
    it('accepts_only_real_link_uris', 0, () => {
      // 系统事件标记：这是这条守卫存在的唯一理由，必须挡住。
      expect(isHandledDeepLinkUri('abilityEvent:clickAlertMessage')).assertFalse();
      // 分享进来的 want 也可能带 uri，同样不是要打开的链接。
      expect(isHandledDeepLinkUri('file:///data/storage/el2/base/haps/entry/files/a.jpg')).assertFalse();
      expect(isHandledDeepLinkUri('')).assertFalse();
      expect(isHandledDeepLinkUri('   ')).assertFalse();
      expect(isHandledDeepLinkUri('mailto:a@b.c')).assertFalse();
      expect(isHandledDeepLinkUri('https://example.com/x')).assertFalse();
    });

    it('keeps_every_legitimate_deep_link_shape', 0, () => {
      // module.json5 只声明了 tg scheme，所以 tg:// 全族必须放行。
      expect(isHandledDeepLinkUri('tg://resolve?domain=foo')).assertTrue();
      expect(isHandledDeepLinkUri('tg://join?invite=HASH')).assertTrue();
      expect(isHandledDeepLinkUri('tg://user?id=7')).assertTrue();
      // 自建推送中转点通知跳会话用的就是这条，挡掉它=推送点了没反应。
      expect(isHandledDeepLinkUri('tg://openmessage?channel_id=1&msg_id=2')).assertTrue();
      // 系统会把没有 authority 的 tg 链接规范化掉双斜杠。
      expect(isHandledDeepLinkUri('tg:resolve?domain=foo')).assertTrue();
      expect(isHandledDeepLinkUri('tg:openmessage?from_id=5')).assertTrue();
      // t.me 家族与 @用户名：系统不会这样递进来，但判据语义要一致。
      expect(isHandledDeepLinkUri('https://t.me/foo')).assertTrue();
      expect(isHandledDeepLinkUri('https://telegram.me/foo/12')).assertTrue();
      expect(isHandledDeepLinkUri('@someone')).assertTrue();
    });

    // 中转（relay-go-src/format.go 的 openMessageUrl）实际发出的三种形态。
    // 它们经华为 Push Kit 的 clickAction.data.url 送达，由 EntryAbility 取出
    // 当深链走——挡掉任何一种，冻结期间点通知就只能落到首页。
    it('accepts_relay_click_urls_verbatim', 0, () => {
      expect(isHandledDeepLinkUri('tg://openmessage?channel_id=2536172802&msg_id=4567')).assertTrue();
      expect(isHandledDeepLinkUri('tg://openmessage?chat_id=1')).assertTrue();
      expect(isHandledDeepLinkUri('tg://openmessage?from_id=99&msg_id=7')).assertTrue();
      // 这三条同时要能解析出目标，否则放行了也跳不过去。
      const a = parseOpenMessageLink('tg://openmessage?channel_id=2536172802&msg_id=4567');
      expect(a !== null).assertTrue();
      const b = parseOpenMessageLink('tg://openmessage?from_id=99&msg_id=7');
      expect(b !== null).assertTrue();
    });
  });
}
