import { describe, expect, it } from '@ohos/hypium';
import { hexToHsv, hsvToHex, isValidHex, relativeLuminance, textOn, toRgbHex } from '../main/ets/util/colorMath';

export default function colorMathTest() {
  describe('colorMath', () => {
    it('isValidHex 只认 #RRGGBB', 0, (): void => {
      expect(isValidHex('#3390EC')).assertTrue();
      expect(isValidHex('#3390ec')).assertTrue();
      expect(isValidHex('3390EC')).assertFalse();
      expect(isValidHex('#3390E')).assertFalse();
      expect(isValidHex('#GG90EC')).assertFalse();
    });
    it('hsv 往返误差 ≤ 1/255', 0, (): void => {
      for (const hex of ['#3390EC', '#E1FFC7', '#182533', '#000000', '#FFFFFF', '#CC5049']) {
        const hsv = hexToHsv(hex);
        const back = hsvToHex(hsv[0], hsv[1], hsv[2]);
        const a = parseInt(hex.substring(1), 16);
        const b = parseInt(back.substring(1), 16);
        for (let shift = 0; shift <= 16; shift += 8) {
          expect(Math.abs(((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)) <= 1).assertTrue();
        }
      }
    });
    it('hsvToHex 输出大写 #RRGGBB', 0, (): void => {
      expect(hsvToHex(0, 0, 1)).assertEqual('#FFFFFF');
      expect(hsvToHex(0, 1, 1)).assertEqual('#FF0000');
      expect(hsvToHex(120, 1, 0.5)).assertEqual('#008000');
    });
    it('toRgbHex 接受 #RRGGBB / #AARRGGBB，其它返回空', 0, (): void => {
      expect(toRgbHex('#3390ec')).assertEqual('#3390EC');
      expect(toRgbHex('#FF3390EC')).assertEqual('#3390EC');
      expect(toRgbHex(' #3390EC ')).assertEqual('#3390EC');
      expect(toRgbHex('3390EC')).assertEqual('');
    });
    it('textOn 按亮度取黑白', 0, (): void => {
      expect(textOn('#FFFFFF')).assertEqual('#000000');
      expect(textOn('#E1FFC7')).assertEqual('#000000');
      expect(textOn('#182533')).assertEqual('#FFFFFF');
      expect(textOn('#2B5278')).assertEqual('#FFFFFF');
      expect(relativeLuminance('#000000')).assertEqual(0);
    });
  });
}
