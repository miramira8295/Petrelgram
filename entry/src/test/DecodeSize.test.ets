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

    // ── 门槛按目标大小分两档（2026-09-20）──────────────────────────────
    //
    // 起因：真机上往上翻 220 行历史、15 秒解出 216 张图，其中 67 次是「解过、
    // 被挤出缓存、又解一次」，每次重解就是用户看到的图片闪一下。根因是原来那条
    // 统一的 2 倍门槛——相册格子目标约 273×420，而缩略图源常见 320–800，
    // 大多落在 1×–2× 区间 → 一律原样解码 → 按源分辨率占内存。
    it('相册那一档：源图 1.2 倍以上就交给解码器', 0, (): void => {
      // 800×600 的源画到 273×420 的相册格子：改之前 scale=0.7 > 1/2，判定
      // "缩得不够多"而原样解码，1875 KB；现在降采样到 919 KB。
      const got: DecodeSize | undefined = decodeDesiredSize(800, 600, 273, 420);
      expect(got !== undefined).assertTrue();
      expect(got?.width).assertEqual(560);
      expect(got?.height).assertEqual(420);
    });

    it('头像那一档仍然守着 2 倍（issue #92 不许回退）', 0, (): void => {
      // 160×160 画到 138×138（46vp×3）：scale=0.86，两档门槛下都必须原样解码。
      // 这条是 #92 那圈斜边锯齿的回归防线。
      expect(decodeDesiredSize(160, 160, 138, 138)).assertUndefined();
      // 就算源图到了 1.5 倍，小目标也不交给解码器。
      expect(decodeDesiredSize(207, 207, 138, 138)).assertUndefined();
    });

    it('200px 是两档的分界，列表头像都在小图那边', 0, (): void => {
      // 目标 200×200（含）算小图：1.5 倍不缩。
      expect(decodeDesiredSize(300, 300, 200, 200)).assertUndefined();
      // 会话行宽松档头像 56vp × 3 = 168 px，必须落在小图这边（#92 的防线）。
      expect(decodeDesiredSize(252, 252, 168, 168)).assertUndefined();
      // 目标 201×201 算大图：同样 1.5 倍就缩。
      expect(decodeDesiredSize(302, 302, 201, 201) !== undefined).assertTrue();
    });

    it('源图不大于目标时两档都不放大', 0, (): void => {
      // desiredSize 会**强制**缩放到给定尺寸，源比目标小就是放大，
      // 存一张比原图还大的位图，纯浪费。
      expect(decodeDesiredSize(320, 240, 273, 420)).assertUndefined();
      expect(decodeDesiredSize(100, 100, 138, 138)).assertUndefined();
    });
  });
}
