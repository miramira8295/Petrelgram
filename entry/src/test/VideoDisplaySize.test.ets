import { describe, expect, it } from '@ohos/hypium';
import {
  DisplaySize, normalizeRotation, swapsAxes, videoDisplaySize
} from '../main/ets/util/videoDisplaySize';

// issue #193：实况照片保存下来「分辨率降低、特模糊」。根因是发送时把**静图**的
// 宽高（全传感器几千万像素）当成视频的宽高声明出去，存图库时抽帧按那个尺寸把
// 1080p 的帧放大。这一组钉住「视频自己的显示尺寸」怎么算——容器里存的是旋转前
// 的宽高，竖拍视频要对调。

export default function videoDisplaySizeTest() {
  describe('videoDisplaySize', () => {

    it('不旋转时原样返回', 0, (): void => {
      const s: DisplaySize = videoDisplaySize(1920, 1080, 0);
      expect(s.width).assertEqual(1920);
      expect(s.height).assertEqual(1080);
    });

    it('旋转 90/270 时宽高对调——竖拍视频的关键', 0, (): void => {
      const a: DisplaySize = videoDisplaySize(1920, 1080, 90);
      expect(a.width).assertEqual(1080);
      expect(a.height).assertEqual(1920);
      const b: DisplaySize = videoDisplaySize(1920, 1080, 270);
      expect(b.width).assertEqual(1080);
      expect(b.height).assertEqual(1920);
    });

    it('旋转 180 不对调', 0, (): void => {
      const s: DisplaySize = videoDisplaySize(1920, 1080, 180);
      expect(s.width).assertEqual(1920);
      expect(s.height).assertEqual(1080);
    });

    it('负角与超过 360 的角都归一', 0, (): void => {
      expect(normalizeRotation(-90)).assertEqual(270);
      expect(normalizeRotation(450)).assertEqual(90);
      expect(normalizeRotation(360)).assertEqual(0);
      expect(normalizeRotation(0)).assertEqual(0);
      // 归一之后判定要一致
      const s: DisplaySize = videoDisplaySize(1920, 1080, -90);
      expect(s.width).assertEqual(1080);
      expect(s.height).assertEqual(1920);
    });

    it('非有限的角当作不旋转，不抛', 0, (): void => {
      expect(normalizeRotation(Number.NaN)).assertEqual(0);
      const s: DisplaySize = videoDisplaySize(1920, 1080, Number.NaN);
      expect(s.width).assertEqual(1920);
    });

    it('对调判定按最近的直角', 0, (): void => {
      expect(swapsAxes(0)).assertFalse();
      expect(swapsAxes(90)).assertTrue();
      expect(swapsAxes(180)).assertFalse();
      expect(swapsAxes(270)).assertTrue();
    });

    it('任一边非正就返回 0——调用方据此退回旧行为，不把 0 填进协议', 0, (): void => {
      expect(videoDisplaySize(0, 1080, 0).width).assertEqual(0);
      expect(videoDisplaySize(1920, 0, 0).height).assertEqual(0);
      expect(videoDisplaySize(-1, -1, 90).width).assertEqual(0);
    });

    it('小数尺寸四舍五入到整像素', 0, (): void => {
      const s: DisplaySize = videoDisplaySize(1919.6, 1080.4, 0);
      expect(s.width).assertEqual(1920);
      expect(s.height).assertEqual(1080);
    });
  });
}
