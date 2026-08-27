import { describe, expect, it } from '@ohos/hypium';
import { glassBubbleCommands, tailShapeCommands } from '../main/ets/util/bubbleGlassPath';

export default function bubbleGlassPathTest() {
  describe('glassBubbleCommands', () => {
    it('收到气泡：底边走到尖 (0,h)，再一段三次贝塞尔勾回 (7, h-tailH)', 0, (): void => {
      const c = glassBubbleCommands(108, 40, false, true, 10, 10, 10, 4, 8, 12, 1);
      expect(c.startsWith('M17 0 L98 0 A10 10 0 0 1 108 10')).assertTrue();
      expect(c.indexOf('L13.8 40 C8.36 36.4 1.75 39.28 0 40 C0 34 7 32.56 7 28') >= 0).assertTrue();
      expect(c.endsWith('L7 10 A10 10 0 0 1 17 0 Z')).assertTrue();
    });
    it('发出气泡：右边缘 yTail 处甩出到尖 (w,h)，底边再直回左下角', 0, (): void => {
      const c = glassBubbleCommands(108, 40, true, true, 10, 10, 4, 10, 8, 12, 1);
      expect(c.indexOf('L101 28 C101 32.56 108 34 108 40 C106.25 39.28 99.64 36.4 94.2 40 L10 40') >= 0).assertTrue();
      expect(c.indexOf('A10 10 0 0 1 0 30') >= 0).assertTrue();
    });
    it('inset 把整条轮廓向内缩，描边才不会被裁掉一半', 0, (): void => {
      const c = glassBubbleCommands(108, 40, false, true, 10, 10, 10, 4, 8, 12, 1, 0.5);
      // 顶边下移 0.5、右边内收 0.5、尖也跟着内收
      expect(c.indexOf(' 0.5') >= 0).assertTrue();
      expect(c.indexOf('107.5') >= 0).assertTrue();
      expect(c.indexOf('0.5 39.5') >= 0).assertTrue();  // 尾尖也跟着内收
    });
    it('没尾巴就是四角圆角矩形，半径按短边一半封顶，左边仍留 7 的空位', 0, (): void => {
      const c = glassBubbleCommands(60, 20, false, false, 17, 17, 17, 17, 8, 12, 1);
      expect(c.indexOf('A10 10') >= 0).assertTrue();
      expect(c.indexOf('A17') < 0).assertTrue();
      expect(c.indexOf('L0 20') < 0).assertTrue();
      expect(c.startsWith('M17 0')).assertTrue();
      expect(c.endsWith('A10 10 0 0 1 17 0 Z')).assertTrue();
    });
    it('scale 作用到每个坐标', 0, (): void => {
      const c = glassBubbleCommands(20, 10, false, false, 0, 0, 0, 0, 8, 12, 3);
      expect(c.indexOf('L60 0') >= 0).assertTrue();
      expect(c.startsWith('M21 0')).assertTrue();
    });
    it('实心档的尾巴和整体轮廓用同一条曲线', 0, (): void => {
      const t = tailShapeCommands(false, 8, 12, 1);
      expect(t).assertEqual('M8 0 L8 12 C6.8 8.4 2 11.28 0 12 C0 6 8 4.56 8 0 Z');
      const o = tailShapeCommands(true, 8, 12, 1);
      expect(o).assertEqual('M0 0 L0 12 C1.2 8.4 6 11.28 8 12 C8 6 0 4.56 0 0 Z');
    });
  });
}
