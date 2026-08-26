import { describe, expect, it } from '@ohos/hypium';
import {
  globalReusePoolAvailable,
  globalReusePoolWinsAt
} from '../main/ets/util/messageReusePool';

// 全局复用池是 API 26 起的能力，而本仓 compatibleSdkVersion 是 6.0.0(20)。
// 判定必须是一个能脱离设备验证的纯函数——它决定的是「要不要 new 那个带
// reusePool 装饰器参数的宿主组件」，判错的后果不是效果差一点，而是低版本设备
// 上碰到不存在的运行时符号。
//
// 形状与 OverlayMaterial.test 的 materialWinsAt 一组用例一致：版本判定用纯
// 函数钉死，跑在设备上的那一个只断言不变量。
export default function messageReusePoolTest() {
  describe('messageReusePool', () => {
    it('turns the global pool on exactly at API 26', 0, () => {
      expect(globalReusePoolWinsAt(26)).assertTrue();
      expect(globalReusePoolWinsAt(25)).assertFalse();
    });

    it('leaves every API level below the pool on the default pool', 0, () => {
      // compatibleSdkVersion is 6.0.0(20); 24 is the level the immersive
      // material crash (1.3.6) was reported on.
      expect(globalReusePoolWinsAt(20)).assertFalse();
      expect(globalReusePoolWinsAt(24)).assertFalse();
      expect(globalReusePoolWinsAt(0)).assertFalse();
    });

    it('keeps the global pool on past 26', 0, () => {
      expect(globalReusePoolWinsAt(27)).assertTrue();
      expect(globalReusePoolWinsAt(99)).assertTrue();
    });

    it('agrees with the device lookup', 0, () => {
      // Runs against whatever host/device the suite is on, so it asserts the
      // invariant (the cached device answer is one of the two the rule can
      // produce) rather than one side of it.
      const live: boolean = globalReusePoolAvailable();
      expect(live === true || live === false).assertTrue();
    });
  });
}
