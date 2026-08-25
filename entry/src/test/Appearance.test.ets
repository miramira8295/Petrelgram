import { describe, expect, it } from '@ohos/hypium';
import {
  ACCENT_DEFAULT_DARK, BUBBLE_IN_DEFAULT_DARK, hexOrDefault, modeKey, resolveBubbleColors
} from '../main/ets/util/appearance';

export default function appearanceTest() {
  describe('appearance', () => {
    it('modeKey 深色加 Dark 后缀', 0, (): void => {
      expect(modeKey('accentHex', false)).assertEqual('accentHex');
      expect(modeKey('accentHex', true)).assertEqual('accentHexDark');
    });
    it('非法 hex 回落默认', 0, (): void => {
      expect(hexOrDefault(undefined, ACCENT_DEFAULT_DARK)).assertEqual('#57A8F2');
      expect(hexOrDefault('', ACCENT_DEFAULT_DARK)).assertEqual('#57A8F2');
      expect(hexOrDefault('#12345', BUBBLE_IN_DEFAULT_DARK)).assertEqual('#182533');
      expect(hexOrDefault('#abcdef', '#000000')).assertEqual('#ABCDEF');
    });
    it('按模式取气泡色并配文字色', 0, (): void => {
      const c = resolveBubbleColors(true, '#E1FFC7', '#2B5278', '#FFFFFF', '#182533');
      expect(c.out).assertEqual('#2B5278');
      expect(c.inn).assertEqual('#182533');
      expect(c.textOut).assertEqual('#FFFFFF');
      expect(c.textIn).assertEqual('#FFFFFF');
      const l = resolveBubbleColors(false, '#E1FFC7', '#2B5278', '#FFFFFF', '#182533');
      expect(l.out).assertEqual('#E1FFC7');
      expect(l.textIn).assertEqual('#000000');
    });
  });
}
