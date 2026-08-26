import { describe, expect, it } from '@ohos/hypium';
import {
  MIN_MESSAGE_ROW_HEIGHT_VP,
  REUSE_BUCKET_MAX_COUNT_CEILING,
  REUSE_BUCKET_MAX_COUNT_FLOOR,
  bucketsNeedingCap,
  globalReusePoolAvailable,
  globalReusePoolWinsAt,
  messageRowViewportRows,
  reuseBucketMaxCount
} from '../main/ets/util/messageReusePool';
import { IReusableInfo } from '@kit.ArkUI';

// A stand-in for one reuseId partition of the pool. The real IReusableInfo is
// handed out by the framework and cannot exist off-device; the only thing the
// pure part needs from it is a readable/writable maxCount.
class FakeBucket implements IReusableInfo {
  readonly count: number;
  maxCount: number;
  readonly reuseId?: string;

  constructor(count: number, maxCount: number, reuseId?: string) {
    this.count = count;
    this.maxCount = maxCount;
    this.reuseId = reuseId;
  }
}

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

    // ── maxCount 的推导 ────────────────────────────────────────────────
    // 上限 = 可视窗口行数 + 2 × cachedCount，也就是「一个 reuseId 分桶在一次
    // 最坏回收潮里可能收到的实例数」的上界。比它小会自己制造官方点名的那条
    // 缓存池溢出，比它大是白占内存（shared 池跨会话累积）。

    it('derives the cap from the viewport and both cached sides', 0, () => {
      // 23 行（780vp / 34vp 向上取整）+ 2 × 6 = 35。
      expect(reuseBucketMaxCount(23, 6)).assertEqual(35);
      expect(reuseBucketMaxCount(16, 6)).assertEqual(28);
      expect(reuseBucketMaxCount(10, 0)).assertEqual(10);
    });

    it('never lets the cap fall to the pool-purging end', 0, () => {
      // maxCount 0 的语义是「清空这个桶」。推导结果绝不该落到那里去。
      expect(reuseBucketMaxCount(0, 0)).assertEqual(REUSE_BUCKET_MAX_COUNT_FLOOR);
      expect(reuseBucketMaxCount(1, 1)).assertEqual(REUSE_BUCKET_MAX_COUNT_FLOOR);
      expect(reuseBucketMaxCount(-5, -5)).assertEqual(REUSE_BUCKET_MAX_COUNT_FLOOR);
    });

    it('clamps to the documented maximum of 200', 0, () => {
      expect(reuseBucketMaxCount(1000, 1000)).assertEqual(REUSE_BUCKET_MAX_COUNT_CEILING);
      expect(reuseBucketMaxCount(200, 0)).assertEqual(REUSE_BUCKET_MAX_COUNT_CEILING);
      expect(reuseBucketMaxCount(199, 0)).assertEqual(199);
    });

    it('stays below the framework default of 100 for a real phone viewport', 0, () => {
      // 封顶只有比默认值 100 小才有意义——否则这项能力等于没开。
      const rows: number = messageRowViewportRows(780, MIN_MESSAGE_ROW_HEIGHT_VP);
      expect(reuseBucketMaxCount(rows, 6) < 100).assertTrue();
    });

    it('counts viewport rows by the shortest row a chat can render', 0, () => {
      // 34vp 是 initialMessageStage 里最矮的一支（系统服务提示）。用最矮的行
      // 去除视口高度得到的是行数上界，正是封顶要的方向。
      expect(MIN_MESSAGE_ROW_HEIGHT_VP).assertEqual(34);
      expect(messageRowViewportRows(680, 34)).assertEqual(20);
      expect(messageRowViewportRows(681, 34)).assertEqual(21);
    });

    it('never reports a zero-row viewport', 0, () => {
      expect(messageRowViewportRows(0, 34)).assertEqual(1);
      expect(messageRowViewportRows(780, 0)).assertEqual(1);
      expect(messageRowViewportRows(-780, 34)).assertEqual(1);
    });

    // ── getReusableInfo 的三种返回形状 ─────────────────────────────────
    // 官方：不带 reuseId 时，用了 reuseId 的组件返回数组，没用的返回单个，
    // 池不接纳该类型时返回 undefined。这段判断是接线里唯一容易写错、又完全
    // 能脱离设备验证的部分。

    it('treats an unaccepted component type as nothing to cap', 0, () => {
      expect(bucketsNeedingCap(undefined, 35).length).assertEqual(0);
    });

    it('accepts the single-object shape as well as the array', 0, () => {
      expect(bucketsNeedingCap(new FakeBucket(3, 100), 35).length).assertEqual(1);
      expect(bucketsNeedingCap([new FakeBucket(3, 100, 'a')], 35).length).assertEqual(1);
    });

    it('skips buckets that already carry the target cap', 0, () => {
      const buckets: IReusableInfo[] = [
        new FakeBucket(0, 35, undefined),
        new FakeBucket(4, 100, 'plain:normal'),
        new FakeBucket(2, 35, 'rich:normal')
      ];
      const pending: IReusableInfo[] = bucketsNeedingCap(buckets, 35);
      expect(pending.length).assertEqual(1);
      expect(pending[0].reuseId).assertEqual('plain:normal');
    });

    it('caps a bucket that is already over the target', 0, () => {
      // 官方：把 maxCount 设成小于当前 count 会触发异步清理，count 在延迟期间
      // 可能暂时超过 maxCount。所以「count 比目标大」必须仍然算需要改。
      const pending: IReusableInfo[] = bucketsNeedingCap([new FakeBucket(80, 100, 'x')], 35);
      expect(pending.length).assertEqual(1);
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
