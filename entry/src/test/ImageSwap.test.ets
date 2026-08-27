import { describe, expect, it } from '@ohos/hypium';
import {
  isDecodableTarget,
  sameDecodeTarget,
  shouldBlankBeforeDecode,
  shouldStartDecode
} from '../main/ets/util/imageSwap';

// 图片闪烁的判定层。
//
// 现象（真机 trace 2026-08-27）：同一个从未被重建的 Image 节点上，
// CreateImageObj 60 次、StartDecoding 114 次，而全局 StartDecoding 2151 次
// 对 OnImageLoadSuccess 只有 964 次——一多半的 src 重设根本没走到"加载成功"，
// 那些就是画面上的空窗帧。其中一条成因是 boxHeight 先给错后修正：同一张图
// 因为解码目标尺寸变了而被整个重解，重解期间节点先被清空。
//
// 清空这一步才是用户看得见的那一下。这里把"什么时候必须清空"钉死：只有换了
// 源文件才必须清空，同一个源文件换尺寸不许清空。
const PATH_A: string = '/data/a.jpg';
const PATH_B: string = '/data/b.jpg';

export default function imageSwapTest() {
  describe('imageSwap', () => {
    it('refuses to decode before the box has been measured', 0, () => {
      expect(isDecodableTarget(PATH_A, 350, 467)).assertTrue();
      expect(isDecodableTarget('', 350, 467)).assertFalse();
      expect(isDecodableTarget(PATH_A, 0, 467)).assertFalse();
      expect(isDecodableTarget(PATH_A, 350, 0)).assertFalse();
      expect(isDecodableTarget(PATH_A, 350, -1)).assertFalse();
    });

    it('treats an identical path and target size as already shown', 0, () => {
      expect(sameDecodeTarget(PATH_A, 350, 467, PATH_A, 350, 467)).assertTrue();
      expect(shouldStartDecode(PATH_A, 350, 467, PATH_A, 350, 467)).assertFalse();
    });

    // vp2px 的取整抖动不该算作一次换图，否则每次重新测量都重解一遍。
    it('ignores sub-pixel drift in the target size', 0, () => {
      expect(sameDecodeTarget(PATH_A, 350.2, 466.58, PATH_A, 349.8, 466.9)).assertTrue();
    });

    it('nothing held is never the same target', 0, () => {
      expect(sameDecodeTarget('', 0, 0, PATH_A, 350, 467)).assertFalse();
      expect(shouldStartDecode('', 0, 0, PATH_A, 350, 467)).assertTrue();
    });

    it('a real size correction still starts a decode', 0, () => {
      expect(shouldStartDecode(PATH_A, 350, 622, PATH_A, 350, 467)).assertTrue();
    });

    // 核心：换源文件才清空。
    it('blanks only when the held bitmap belongs to another file', 0, () => {
      expect(shouldBlankBeforeDecode(PATH_A, PATH_B)).assertTrue();
    });

    // 这一条就是闪烁：同一张图，boxHeight 从 622 修正成 467。旧代码在这里
    // 把节点清空，于是"解码 → 空窗 → 加载成功 → 重绘"。
    it('never blanks when only the target size changed', 0, () => {
      expect(shouldBlankBeforeDecode(PATH_A, PATH_A)).assertFalse();
    });

    it('nothing held means nothing to blank', 0, () => {
      expect(shouldBlankBeforeDecode('', PATH_A)).assertFalse();
    });
  });
}
