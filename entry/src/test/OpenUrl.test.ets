import { describe, it, expect } from '@ohos/hypium';
import { normalizeExternalUrl } from '../main/ets/util/openUrl';

export default function openUrlTest() {
  describe('OpenUrl', () => {
    it('preserves_geo_tel_and_mailto_schemes', 0, () => {
      expect(normalizeExternalUrl('geo:31.2,121.4?q=test')).assertEqual('geo:31.2,121.4?q=test');
      expect(normalizeExternalUrl('tel:+8613800000000')).assertEqual('tel:+8613800000000');
      expect(normalizeExternalUrl('mailto:test@example.com')).assertEqual('mailto:test@example.com');
    });
    it('adds_https_only_to_bare_web_addresses', 0, () => {
      expect(normalizeExternalUrl('example.com/path')).assertEqual('https://example.com/path');
      expect(normalizeExternalUrl('https://example.com')).assertEqual('https://example.com');
    });
  });
}
