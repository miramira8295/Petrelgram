import { describe, it, expect } from '@ohos/hypium';
import { inviteLinkOf, bareUsernameOf, isTelegramInternalUrl } from '../main/ets/util/linkNav';

export default function linkNavTest() {
  describe('inviteLinkOf', () => {
    it('plus_hash', 0, () => {
      expect(inviteLinkOf('https://t.me/+ajdklsd')).assertEqual('https://t.me/+ajdklsd');
    });
    it('plus_hash_no_scheme', 0, () => {
      expect(inviteLinkOf('t.me/+Ab_c1D')).assertEqual('https://t.me/+Ab_c1D');
    });
    it('joinchat_form', 0, () => {
      expect(inviteLinkOf('https://t.me/joinchat/AbCdEf123')).assertEqual('https://t.me/joinchat/AbCdEf123');
    });
    it('strips_query', 0, () => {
      expect(inviteLinkOf('https://t.me/+ajdklsd?foo=1')).assertEqual('https://t.me/+ajdklsd');
    });
    it('phone_number_not_invite', 0, () => {
      // t.me/+<digits> is a phone-number link, not an invite.
      expect(inviteLinkOf('https://t.me/+8615551234567')).assertEqual('');
    });
    it('username_not_invite', 0, () => {
      expect(inviteLinkOf('https://t.me/somechannel')).assertEqual('');
    });
    it('other_host_not_invite', 0, () => {
      expect(inviteLinkOf('https://example.com/+ajdklsd')).assertEqual('');
    });
    it('bare_plus_not_invite', 0, () => {
      expect(inviteLinkOf('https://t.me/+')).assertEqual('');
    });
  });
  describe('bareUsernameOf_invites_excluded', () => {
    it('plus_link_excluded', 0, () => {
      expect(bareUsernameOf('https://t.me/+ajdklsd')).assertEqual('');
    });
    it('plain_username_kept', 0, () => {
      expect(bareUsernameOf('https://t.me/telegram')).assertEqual('telegram');
    });
  });

  // 内链跳过「打开/复制」确认层直接解析（用户反馈 t.me 被当浏览器链接）。
  describe('isTelegramInternalUrl', () => {
    it('telegram_hosts_and_deep_links_are_internal', 0, () => {
      expect(isTelegramInternalUrl('https://t.me/telegram')).assertTrue();
      expect(isTelegramInternalUrl('https://t.me/DocOfCard_Channel/2429')).assertTrue();
      expect(isTelegramInternalUrl('t.me/+AbCdEf123')).assertTrue();
      expect(isTelegramInternalUrl('https://telegram.me/addstickers/Cats')).assertTrue();
      expect(isTelegramInternalUrl('https://telegram.dog/somebot?start=x')).assertTrue();
      expect(isTelegramInternalUrl('tg://resolve?domain=telegram')).assertTrue();
      expect(isTelegramInternalUrl('tg://user?id=123')).assertTrue();
      expect(isTelegramInternalUrl('@durov')).assertTrue();
    });
    it('external_web_urls_are_not_internal', 0, () => {
      expect(isTelegramInternalUrl('https://example.com/t.me/fake')).assertFalse();
      expect(isTelegramInternalUrl('https://tele.gram.me/x')).assertFalse();
      expect(isTelegramInternalUrl('https://t.me.evil.com/abc')).assertFalse();
      expect(isTelegramInternalUrl('http://example.com')).assertFalse();
    });
  });
}
