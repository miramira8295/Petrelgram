import { describe, expect, it } from '@ohos/hypium';
import { webBrowserTarget } from '../main/ets/util/webBrowserNav';

export default function webBrowserNavTest() {
  describe('WebBrowserNav', (): void => {
    it('accepts_https_urls_untouched', 0, (): void => {
      expect(webBrowserTarget('https://example.com/a?b=1#c'))
        .assertEqual('https://example.com/a?b=1#c');
    });
    it('accepts_http_urls_case_insensitively', 0, (): void => {
      expect(webBrowserTarget('HTTP://example.com')).assertEqual('HTTP://example.com');
    });
    it('normalizes_bare_web_addresses_to_https', 0, (): void => {
      expect(webBrowserTarget('www.example.com/path')).assertEqual('https://www.example.com/path');
      expect(webBrowserTarget('example.com')).assertEqual('https://example.com');
    });
    it('trims_surrounding_whitespace', 0, (): void => {
      expect(webBrowserTarget('  https://example.com  ')).assertEqual('https://example.com');
    });
    it('rejects_non_web_schemes', 0, (): void => {
      expect(webBrowserTarget('tel:+8613800138000')).assertEqual('');
      expect(webBrowserTarget('mailto:a@b.com')).assertEqual('');
      expect(webBrowserTarget('tg://resolve?domain=telegram')).assertEqual('');
      expect(webBrowserTarget('geo:0,0')).assertEqual('');
    });
    it('rejects_empty_input', 0, (): void => {
      expect(webBrowserTarget('')).assertEqual('');
      expect(webBrowserTarget('   ')).assertEqual('');
    });
  });
}
