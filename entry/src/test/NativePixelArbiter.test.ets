import { describe, it, expect } from '@ohos/hypium';
import {
  ALPHA_FLOOR_BYTES, IMAGE_CAP_BYTES, imagePixelLimitNow, PINNED_ALLOWANCE_BYTES, sharedImageLimit
} from '../main/ets/util/nativePixelArbiter';
import { NATIVE_PIXEL_CACHE_MAX_BYTES } from '../main/ets/util/NativePixelBudget';

const MIB: number = 1024 * 1024;
const TOTAL: number = NATIVE_PIXEL_CACHE_MAX_BYTES;

export default function nativePixelArbiterTest() {
  describe('NativePixelArbiter', () => {
    // 可淘汰那部分的天花板 = 总线 − 贴纸地板 − 钉住豁免额。
    // 总量（可淘汰 + 钉住）仍然压在 总线 − 贴纸地板 之内，所以 2026-09-21 单开
    // 钉住那一格**不抬高真实内存**，只是把"谁被挤"划清楚。
    it('可淘汰天花板 = 总线 − 贴纸地板 − 钉住豁免额', 0, () => {
      expect(IMAGE_CAP_BYTES).assertEqual(TOTAL - ALPHA_FLOOR_BYTES - PINNED_ALLOWANCE_BYTES);
    });

    it('总量不超过 总线 − 贴纸地板', 0, () => {
      expect(IMAGE_CAP_BYTES + PINNED_ALLOWANCE_BYTES).assertEqual(TOTAL - ALPHA_FLOOR_BYTES);
    });

    // 钉住的字节在豁免额之内额外放行——壁纸 pin 住 7.4MB 不该把内容挤掉 7.4MB。
    it('钉住的字节在豁免额内额外放行', 0, () => {
      const base: number = imagePixelLimitNow(IMAGE_CAP_BYTES, 0);
      expect(imagePixelLimitNow(IMAGE_CAP_BYTES, 8 * MIB)).assertEqual(base + 8 * MIB);
      expect(imagePixelLimitNow(IMAGE_CAP_BYTES, PINNED_ALLOWANCE_BYTES))
        .assertEqual(base + PINNED_ALLOWANCE_BYTES);
    });

    // 超出豁免额的部分照旧从预算里扣，否则钉住的东西无限增长就会把真实内存顶穿。
    it('超出豁免额的钉住字节不再放行', 0, () => {
      const base: number = imagePixelLimitNow(IMAGE_CAP_BYTES, 0);
      expect(imagePixelLimitNow(IMAGE_CAP_BYTES, PINNED_ALLOWANCE_BYTES + 30 * MIB))
        .assertEqual(base + PINNED_ALLOWANCE_BYTES);
    });

    it('负数钉住字节不产生负豁免', 0, () => {
      const base: number = imagePixelLimitNow(IMAGE_CAP_BYTES, 0);
      expect(imagePixelLimitNow(IMAGE_CAP_BYTES, -5)).assertEqual(base);
    });

    // 这是本次改动的目的：纯图片会话里贴纸一个字节没用，图片应该拿到
    // 48MiB 之外那块闲置额度。
    it('贴纸空着时图片拿到天花板', 0, () => {
      expect(sharedImageLimit(TOTAL, 0)).assertEqual(IMAGE_CAP_BYTES);
    });

    it('贴纸占用低于地板时，仍按地板预留，不多给', 0, () => {
      expect(sharedImageLimit(TOTAL, 1 * MIB)).assertEqual(IMAGE_CAP_BYTES);
      expect(sharedImageLimit(TOTAL, ALPHA_FLOOR_BYTES)).assertEqual(IMAGE_CAP_BYTES);
    });

    it('贴纸占用超过地板后，图片按实际占用让出来', 0, () => {
      expect(sharedImageLimit(TOTAL, 30 * MIB)).assertEqual(TOTAL - 30 * MIB);
      expect(sharedImageLimit(TOTAL, 56 * MIB)).assertEqual(TOTAL - 56 * MIB);
    });

    // 不变式：图片限额 + 贴纸实际占用永远不超过总线。越界就是把
    // NativeBinding 警戒线顶穿，这条必须钉死。
    it('不变式：限额 + 贴纸占用 ≤ 总线', 0, () => {
      for (let used = 0; used <= TOTAL; used += 4 * MIB) {
        expect(sharedImageLimit(TOTAL, used) + used <= TOTAL).assertTrue();
      }
    });

    it('贴纸吃满总线时图片限额归零，不出负数', 0, () => {
      expect(sharedImageLimit(TOTAL, TOTAL)).assertEqual(0);
      expect(sharedImageLimit(TOTAL, TOTAL + 10 * MIB)).assertEqual(0);
    });

    it('调用方自己的天花板更低时以它为准（内存压力收紧）', 0, () => {
      expect(sharedImageLimit(TOTAL, 0, 16 * MIB)).assertEqual(16 * MIB);
      // 收紧的天花板不会因为贴纸空着就被抬回去。
      expect(sharedImageLimit(TOTAL, 0, 0)).assertEqual(0);
    });

    it('传进来的天花板高于全局上限时被夹回去', 0, () => {
      expect(sharedImageLimit(TOTAL, 0, TOTAL * 2)).assertEqual(IMAGE_CAP_BYTES);
    });

    it('总线被收紧时按收紧后的算', 0, () => {
      const half: number = 40 * MIB;
      expect(sharedImageLimit(half, 0)).assertEqual(half - ALPHA_FLOOR_BYTES);
      expect(sharedImageLimit(half, 20 * MIB)).assertEqual(half - 20 * MIB);
    });

    it('负数与小数输入不产生负限额或小数', 0, () => {
      expect(sharedImageLimit(TOTAL, -5)).assertEqual(IMAGE_CAP_BYTES);
      expect(sharedImageLimit(-1, 0)).assertEqual(0);
      const v: number = sharedImageLimit(TOTAL, 1.7 * MIB);
      expect(Math.floor(v)).assertEqual(v);
    });
  });
}
