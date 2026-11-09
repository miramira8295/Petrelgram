import { describe, expect, it } from '@ohos/hypium';
import {
  glassBodyFallbackPainted, glassBodyPainted, glassBubbleCommands, glassPaintReady,
  glassStage, tailShapeCommands
} from '../main/ets/util/bubbleGlassPath';

export default function bubbleGlassPathTest() {
  describe('glassBubbleCommands', () => {
    it('收到气泡：尾巴向左倾转，内侧沿圆角接回', 0, (): void => {
      const c = glassBubbleCommands(108, 40, false, true, 10, 10, 10, 10, 8, 12, 1);
      expect(c.startsWith('M17 0 L98 0 A10 10 0 0 1 108 10')).assertTrue();
      expect(c.indexOf('L17 40 A10 10 0 0 1 17 40 C14.3 40 2.32 40 0 37.62 C1.59 37.67 6.07 38.62 7 32.59') >= 0).assertTrue();
      expect(c.endsWith('L7 10 A10 10 0 0 1 17 0 Z')).assertTrue();
    });
    it('发出气泡：尾巴镜像倾转，内侧沿圆角接回', 0, (): void => {
      const c = glassBubbleCommands(108, 40, true, true, 10, 10, 10, 10, 8, 12, 1);
      expect(c.indexOf('L101 32.59 C101.93 38.62 106.41 37.67 108 37.62 C105.68 40 93.7 40 91 40 A10 10 0 0 1 91 40 L10 40') >= 0).assertTrue();
      expect(c.indexOf('A10 10 0 0 1 0 30') >= 0).assertTrue();
    });
    it('inset 把整条轮廓向内缩，描边才不会被裁掉一半', 0, (): void => {
      const c = glassBubbleCommands(108, 40, false, true, 10, 10, 10, 10, 8, 12, 1, 0.5);
      // 顶边下移 0.5、右边内收 0.5、尖也跟着内收
      expect(c.indexOf(' 0.5') >= 0).assertTrue();
      expect(c.indexOf('107.5') >= 0).assertTrue();
      expect(c.indexOf('0.5 37.12') >= 0).assertTrue();  // 尾尖也跟着内收
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
      const t = tailShapeCommands(false, 8, 12, 1, 10);
      expect(t).assertEqual('M18 0 L18 12 A10 10 0 0 1 18 12 C15.18 12 2.42 12 0 9.97 C1.83 9.91 6.92 10.65 8 4.27 L8 0 L18 0 Z');
      const o = tailShapeCommands(true, 8, 12, 1, 10);
      expect(o).assertEqual('M10 0 L10 4.27 C11.08 10.65 16.17 9.91 18 9.97 C15.58 12 2.82 12 0 12 A10 10 0 0 1 0 12 L0 0 Z');
    });
  });

  describe('glassStage', () => {
    // 三段式：不要玻璃 / 只有本体上玻璃 / 容器也点亮。守的是两条真机 bug：
    // 没裁剪的容器把 7vp 留白涂满（横跳），以及退回实心档的那下白闪。
    it('材质没开就是 off，走实心档', 0, (): void => {
      expect(glassStage(false, 108, 40)).assertEqual('off');
      expect(glassStage(false, 0, 0)).assertEqual('off');
    });
    it('想要玻璃但还没量到 ⇒ bodyOnly，只有气泡本体上玻璃', 0, (): void => {
      expect(glassStage(true, 0, 0)).assertEqual('bodyOnly');
      expect(glassStage(true, 0, 40)).assertEqual('bodyOnly');
      expect(glassStage(true, 108, 0)).assertEqual('bodyOnly');
      expect(glassStage(true, -1, 40)).assertEqual('bodyOnly');
    });
    it('量到了才是 full，容器这才允许上色和裁剪', 0, (): void => {
      expect(glassStage(true, 108, 40)).assertEqual('full');
    });
  });

  describe('glassBodyPainted', () => {
    // 这一组守的是白闪：本体这一层**不许**因为没量到就退回实心（不透明）底色。
    it('还没量到时本体照样上玻璃 —— 不许退回实心档', 0, (): void => {
      expect(glassBodyPainted(true, 0, 0)).assertTrue();
      expect(glassBodyPainted(true, 108, 0)).assertTrue();
      expect(glassBodyPainted(true, 0, 40)).assertTrue();
    });
    it('量到之后本体依然上玻璃', 0, (): void => {
      expect(glassBodyPainted(true, 108, 40)).assertTrue();
    });
    it('材质没开时本体走实心底色', 0, (): void => {
      expect(glassBodyPainted(false, 108, 40)).assertFalse();
      expect(glassBodyPainted(false, 0, 0)).assertFalse();
    });
  });

  describe('glassPaintReady', () => {
    // 容器这一层：裁剪要尺寸，所以上色也必须等尺寸——否则没裁剪的容器
    // 把 7vp 留白一起涂上，气泡左边缘外扩。
    it('量到尺寸才允许上玻璃色', 0, (): void => {
      expect(glassPaintReady(true, 108, 40)).assertTrue();
    });
    it('还没量到（宽为 0）时不许上色，退回实心档', 0, (): void => {
      expect(glassPaintReady(true, 0, 40)).assertFalse();
    });
    it('还没量到（高为 0）时不许上色', 0, (): void => {
      expect(glassPaintReady(true, 108, 0)).assertFalse();
    });
    it('宽高都为 0（复用刚清零的那一帧）不许上色', 0, (): void => {
      expect(glassPaintReady(true, 0, 0)).assertFalse();
    });
    it('负数尺寸同样按没量到处理', 0, (): void => {
      expect(glassPaintReady(true, -1, 40)).assertFalse();
      expect(glassPaintReady(true, 108, -1)).assertFalse();
    });
    it('材质本来就没开时，量到多少都不上色', 0, (): void => {
      expect(glassPaintReady(false, 108, 40)).assertFalse();
      expect(glassPaintReady(false, 0, 0)).assertFalse();
    });
  });

  describe('glassBodyFallbackPainted', () => {
    it('只在外层尺寸未就绪时由本体临时绘制玻璃', 0, (): void => {
      expect(glassBodyFallbackPainted(true, 0, 0)).assertTrue();
      expect(glassBodyFallbackPainted(true, 108, 0)).assertTrue();
      expect(glassBodyFallbackPainted(true, 0, 40)).assertTrue();
    });
    it('完整轮廓就绪后本体停止绘制，避免双层模糊', 0, (): void => {
      expect(glassBodyFallbackPainted(true, 108, 40)).assertFalse();
    });
    it('材质关闭时不进入玻璃回退层', 0, (): void => {
      expect(glassBodyFallbackPainted(false, 108, 40)).assertFalse();
      expect(glassBodyFallbackPainted(false, 0, 0)).assertFalse();
    });
  });
}
