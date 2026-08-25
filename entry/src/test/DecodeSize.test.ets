import { describe, expect, it } from '@ohos/hypium';
import { DecodeSize, decodeDesiredSize } from '../main/ets/util/decodeSize';

export default function decodeSizeTest() {
  describe('decodeSize', () => {
    it('大照片进小格子照旧降采样', 0, (): void => {
      // 相册单元格：1280×720 的照片画到 225×225。省下的像素是数量级的，
      // 这正是 desiredSize 存在的理由。
      const got: DecodeSize | undefined = decodeDesiredSize(1280, 720, 225, 225);
      expect(got !== undefined).assertTrue();
      // 比例取两维里大的那个（225/720），结果仍能盖住方框，剩下的交给 Cover。
      expect(got?.width).assertEqual(400);
      expect(got?.height).assertEqual(225);
    });

    it('小幅缩放不交给解码器', 0, (): void => {
      // **这条钉的是 issue #92。** 160px 的头像画到 130px，原来在解码阶段
      // 重采样，斜边一格一格；省下的内存不到 40KB，不值得。
      expect(decodeDesiredSize(160, 160, 130, 130)).assertUndefined();
      expect(decodeDesiredSize(300, 300, 200, 200)).assertUndefined();
    });

    it('刚好两倍是分界，含等号那侧才缩', 0, (): void => {
      // scale === 0.5：正好到门槛，缩。
      const at: DecodeSize | undefined = decodeDesiredSize(200, 200, 100, 100);
      expect(at !== undefined).assertTrue();
      expect(at?.width).assertEqual(100);
      // 差一点点就不缩。
      expect(decodeDesiredSize(200, 200, 101, 101)).assertUndefined();
    });

    it('源图不比目标大就原样解码', 0, (): void => {
      // 放大没有意义：解码器放大出来的和渲染阶段放大出来的一样糊，还多占内存。
      expect(decodeDesiredSize(64, 64, 128, 128)).assertUndefined();
      expect(decodeDesiredSize(128, 128, 128, 128)).assertUndefined();
    });

    it('尺寸不合法时不设 desiredSize', 0, (): void => {
      // getImageInfo 失败/返回 0 时不能算出一个 0×0 的目标——那会解出空图。
      expect(decodeDesiredSize(0, 0, 100, 100)).assertUndefined();
      expect(decodeDesiredSize(100, 100, 0, 100)).assertUndefined();
      expect(decodeDesiredSize(Number.NaN, 100, 100, 100)).assertUndefined();
    });

    it('极端长宽比下两个维度都不为 0', 0, (): void => {
      // 解码器拿到 0 会失败。比例取两维里大的那个，所以短边乘回来至少等于
      // 目标短边——数学上到不了 0，但这条钉住"将来把比例改成取小的"会出事。
      const got: DecodeSize | undefined = decodeDesiredSize(4000, 40, 100, 1);
      expect(got !== undefined).assertTrue();
      expect((got?.width ?? 0) >= 1).assertTrue();
      expect((got?.height ?? 0) >= 1).assertTrue();
    });
  });
}
