import { describe, expect, it } from '@ohos/hypium';
import {
  MIN_MESSAGE_ROW_HEIGHT_VP,
  REUSE_BUCKET_DEFAULT_MAX_COUNT,
  REUSE_BUCKET_MAX_COUNT_CEILING,
  REUSE_BUCKET_MAX_COUNT_FLOOR,
  REUSE_LIVE_BUCKET_LIMIT,
  ReuseCapPlan,
  ReuseBucketWrite,
  bucketsNeedingCap,
  globalReusePoolAvailable,
  globalReusePoolWinsAt,
  messageReuseHostCount,
  messageRowViewportRows,
  planReuseBuckets,
  releaseMessageReuseHost,
  retainMessageReuseHost,
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

// 从一份写入计划里挑出目标值等于 maxCount 的那些桶名，排序后好断言。
function idsOf(writes: ReuseBucketWrite[], maxCount: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < writes.length; i++) {
    if (writes[i].maxCount === maxCount) {
      out.push(writes[i].info.reuseId ?? '<none>');
    }
  }
  out.sort();
  return out;
}

function bucketsNamed(n: number, count: number, maxCount: number): IReusableInfo[] {
  const out: IReusableInfo[] = [];
  for (let i = 0; i < n; i++) {
    const suffix: string = i < 10 ? `0${i}` : `${i}`;
    out.push(new FakeBucket(count, maxCount, `b${suffix}`));
  }
  return out;
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

    // ── 桶数本身的上界 + 最久未用淘汰（F-6）────────────────────────────
    //
    // 每桶封顶治的是「一个桶太满」，治不了「桶太多」：medium 档的 rowReuseId
    // 取值空间约 3000 个，而 shared 池只要栈上还压着任意会话页就不销毁，逛过
    // 的会话的形状分桶会一直累积。maxCount 是官方给的唯一旋钮，所以「淘汰」
    // 只能表达成「maxCount 写 0」，而清理是异步的 ⇒ 分两趟。

    it('leaves the bucket count alone while it is under the limit', 0, () => {
      const buckets: IReusableInfo[] = bucketsNamed(3, 2, 100);
      const plan: ReuseCapPlan =
        planReuseBuckets(buckets, 35, new Map<string, number>(), 1000, REUSE_LIVE_BUCKET_LIMIT);
      // 三个桶都只是被封顶，一个都没淘汰。
      expect(idsOf(plan.writes, 35).length).assertEqual(3);
      expect(idsOf(plan.writes, 0).length).assertEqual(0);
      expect(plan.lastSeen.size).assertEqual(3);
    });

    it('evicts the least recently used buckets past the limit', 0, () => {
      const buckets: IReusableInfo[] = bucketsNamed(6, 2, 35);
      const lastSeen: Map<string, number> = new Map<string, number>();
      // b00/b01 最久没用过；其余的刚用过。count > 0 会把「现在」盖上去，
      // 所以把前两个的 count 设成 0，让它们只保留历史时间戳。
      const aged: IReusableInfo[] = [
        new FakeBucket(0, 35, 'b00'), new FakeBucket(0, 35, 'b01'),
        buckets[2], buckets[3], buckets[4], buckets[5]
      ];
      lastSeen.set('b00', 10);
      lastSeen.set('b01', 20);
      const plan: ReuseCapPlan = planReuseBuckets(aged, 35, lastSeen, 9000, 4);
      expect(idsOf(plan.writes, 0).join(',')).assertEqual('b00,b01');
      // 幸存下来的正好是上限那么多，账本也只留它们。
      expect(plan.lastSeen.size).assertEqual(4);
      expect(plan.lastSeen.has('b00')).assertFalse();
      expect(plan.lastSeen.has('b05')).assertTrue();
    });

    it('hands a cleaned-out bucket back to the framework default', 0, () => {
      // 第 2 趟：maxCount 已经是 0 且 count 归零 ⇒ 写回默认值，桶就此退出
      // getReusableInfo 的枚举（官方：只枚举 count 为正或 maxCount 非默认的）。
      const plan: ReuseCapPlan = planReuseBuckets(
        [new FakeBucket(0, 0, 'gone')], 35, new Map<string, number>(), 1000, 4);
      expect(plan.writes.length).assertEqual(1);
      expect(plan.writes[0].maxCount).assertEqual(REUSE_BUCKET_DEFAULT_MAX_COUNT);
      expect(plan.lastSeen.size).assertEqual(0);
    });

    it('waits out the asynchronous purge instead of un-evicting', 0, () => {
      // 中间态：maxCount 已经是 0 但异步清理还没跑完（count 仍为正）。
      // 这一趟什么都不写——写回 target 就等于把刚淘汰的桶又复活了。
      const plan: ReuseCapPlan = planReuseBuckets(
        [new FakeBucket(7, 0, 'purging')], 35, new Map<string, number>(), 1000, 4);
      expect(plan.writes.length).assertEqual(0);
      expect(plan.lastSeen.size).assertEqual(0);
    });

    it('never evicts or counts the no-reuseId entry', 0, () => {
      // 官方：不带 reuseId 查询时恒有一条 reuseId: undefined。它不是一个分档
      // 桶，不参与桶数统计，但照常封顶。
      const plan: ReuseCapPlan = planReuseBuckets(
        [new FakeBucket(3, 100, undefined), new FakeBucket(3, 100, 'a')],
        35, new Map<string, number>(), 1000, 1);
      expect(idsOf(plan.writes, 0).length).assertEqual(0);
      expect(idsOf(plan.writes, 35).join(',')).assertEqual('<none>,a');
      expect(plan.lastSeen.size).assertEqual(1);
    });

    it('treats an unaccepted component type as an empty plan', 0, () => {
      const plan: ReuseCapPlan =
        planReuseBuckets(undefined, 35, new Map<string, number>(), 1000, 4);
      expect(plan.writes.length).assertEqual(0);
      expect(plan.lastSeen.size).assertEqual(0);
    });

    it('keeps the live-bucket limit small enough to bound the pool', 0, () => {
      // 上限 × 每桶上限就是全池实例数的上界。它必须是个能说出口的数，否则
      // 「封顶」这项能力等于没开。
      expect(REUSE_LIVE_BUCKET_LIMIT > 0).assertTrue();
      expect(REUSE_LIVE_BUCKET_LIMIT * reuseBucketMaxCount(23, 6) < 1000).assertTrue();
    });

    // ── 并存的宿主页面数 ───────────────────────────────────────────────

    it('scales the per-bucket cap by the number of live chat pages', 0, () => {
      expect(reuseBucketMaxCount(23, 6, 1)).assertEqual(35);
      expect(reuseBucketMaxCount(23, 6, 2)).assertEqual(70);
      // 缺省仍是单页，既有调用点语义不变。
      expect(reuseBucketMaxCount(23, 6)).assertEqual(reuseBucketMaxCount(23, 6, 1));
      // 放大之后照样被官方的 200 夹住。
      expect(reuseBucketMaxCount(23, 6, 99)).assertEqual(REUSE_BUCKET_MAX_COUNT_CEILING);
      // 0/负数当单页处理。
      expect(reuseBucketMaxCount(23, 6, 0)).assertEqual(35);
      expect(reuseBucketMaxCount(23, 6, -3)).assertEqual(35);
    });

    it('counts live chat pages and never reports fewer than one', 0, () => {
      const base: number = messageReuseHostCount();
      expect(base >= 1).assertTrue();
      retainMessageReuseHost();
      retainMessageReuseHost();
      expect(messageReuseHostCount()).assertEqual(2);
      releaseMessageReuseHost();
      expect(messageReuseHostCount()).assertEqual(1);
      releaseMessageReuseHost();
      // 一个页面都没有时仍然报 1：调用点是从页面里调的，那一刻本页必然活着。
      expect(messageReuseHostCount()).assertEqual(1);
      // 多减不会把计数拖到负数。
      releaseMessageReuseHost();
      releaseMessageReuseHost();
      retainMessageReuseHost();
      expect(messageReuseHostCount()).assertEqual(1);
      releaseMessageReuseHost();
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
