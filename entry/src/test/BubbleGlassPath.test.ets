import { describe, expect, it } from '@ohos/hypium';
import { glassBubbleCommands } from '../main/ets/util/bubbleGlassPath';

export default function bubbleGlassPathTest() {
  describe('glassBubbleCommands', () => {
    it('收到气泡：尾巴在左下，尖在 (0,h)，气泡从 tailW-1 起', 0, (): void => {
      const c = glassBubbleCommands(108, 40, false, true, 10, 10, 10, 4, 8, 12, 1);
      expect(c.startsWith('M17 0 L98 0 A10 10 0 0 1 108 10')).assertTrue();
      expect(c.indexOf('L0 40 L7 28') >= 0).assertTrue();
      expect(c.endsWith('L7 10 A10 10 0 0 1 17 0 Z')).assertTrue();
    });
    it('发出气泡：尾巴在右下，尖在 (w,h)', 0, (): void => {
      const c = glassBubbleCommands(108, 40, true, true, 10, 10, 4, 10, 8, 12, 1);
      expect(c.indexOf('L101 28 L108 40 L10 40') >= 0).assertTrue();
      expect(c.indexOf('A10 10 0 0 1 0 30') >= 0).assertTrue();
    });
    it('没尾巴就是四角圆角矩形，半径按短边一半封顶', 0, (): void => {
      const c = glassBubbleCommands(60, 20, false, false, 17, 17, 17, 17, 8, 12, 1);
      expect(c.indexOf('A10 10') >= 0).assertTrue();
      expect(c.indexOf('A17') < 0).assertTrue();
      expect(c.indexOf('L0 20') < 0).assertTrue();
    });
    it('scale 作用到每个坐标', 0, (): void => {
      const c = glassBubbleCommands(10, 10, false, false, 0, 0, 0, 0, 8, 12, 3);
      expect(c.indexOf('L30 0') >= 0).assertTrue();
    });
  });
}
