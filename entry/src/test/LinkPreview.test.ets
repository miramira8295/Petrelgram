import { describe, it, expect } from '@ohos/hypium';
import { linkPreviewDomain, linkPreviewPresentation } from '../main/ets/util/linkPreview';

export default function linkPreviewTest() {
  describe('LinkPreview', (): void => {
    it('classifies_regular_web_links', 0, (): void => {
      const presentation = linkPreviewPresentation('https://www.example.com/article?id=1', '', '');
      expect(presentation.kind).assertEqual('web');
      expect(presentation.actionLabel).assertEqual('link_preview_open_web');
      expect(presentation.siteLabel).assertEqual('example.com');
      expect(linkPreviewDomain('https://www.example.com/a')).assertEqual('example.com');
    });
    it('classifies_channel_posts_separately_from_profiles', 0, (): void => {
      const post = linkPreviewPresentation('https://t.me/mose_channel/42', '', '');
      const profile = linkPreviewPresentation('https://t.me/mose_channel', '', '');
      expect(post.kind).assertEqual('telegramMessage');
      expect(post.actionLabel).assertEqual('link_preview_open_message');
      expect(profile.kind).assertEqual('telegramChat');
      expect(profile.actionLabel).assertEqual('link_preview_open_profile');
    });
    it('classifies_invites_and_empty_targets', 0, (): void => {
      const invite = linkPreviewPresentation('https://t.me/+AbCdEf12', '', 'Telegram');
      const empty = linkPreviewPresentation('', '', 'Example');
      expect(invite.kind).assertEqual('telegramInvite');
      expect(invite.actionLabel).assertEqual('link_preview_open_invite');
      expect(empty.actionable).assertFalse();
      expect(empty.actionLabel).assertEqual('link_preview_unavailable');
    });
  });
}
