import { describe, expect, it } from '@ohos/hypium';
import { UTILITY_ACTION_MIN_GAP_MS, utilityActionAllowedAt } from '../main/ets/util/utilityActionGuard';

// `utilityActionAllowedAt` 是 B3 从 ChatPage 的 `private utilityActionAllowed()`
// 搬出来的判定（`Date.now()` 与 `this.utilityActionAtMs` 变成显式参数）。
//
// 页面侧的薄包装长这样，测试里用 `Gate` 复刻它，好把"三个动作共享一把闸"这条
// 语义也钉住——那才是这段代码最容易被"顺手简化"掉的地方：
//
//   private utilityActionAllowed(): boolean {
//     const now = Date.now();
//     if (!utilityActionAllowedAt(this.utilityActionAtMs, now)) { return false; }
//     this.utilityActionAtMs = now;
//     return true;
//   }
class Gate {
  atMs: number = 0;

  allow(nowMs: number): boolean {
    if (!utilityActionAllowedAt(this.atMs, nowMs)) {
      return false;
    }
    this.atMs = nowMs;
    return true;
  }
}

// 一个真实量级的 `Date.now()`。闸的入参永远来自 `Date.now()`，不是从 0 开始
// 计数的相对毫秒——下面"首次放行"那条用得着这个区别。
const REAL_NOW_MS: number = 1758000000000;

export default function utilityActionGuardTest() {
  describe('utilityActionAllowedAt', () => {
    it('间隔常量就是 550ms', 0, (): void => {
      expect(UTILITY_ACTION_MIN_GAP_MS).assertEqual(550);
    });

    // 边界：549 拒、550 放。写反成 `>` 会让恰好 550ms 的第二次点击被吞掉。
    // 这里故意写死字面量而不是引用常量：常量若被人改小，这三条要一起红。
    it('549ms 拒、550ms 放', 0, (): void => {
      expect(utilityActionAllowedAt(1000, 1000 + 549)).assertFalse();
      expect(utilityActionAllowedAt(1000, 1000 + 550)).assertTrue();
      expect(utilityActionAllowedAt(1000, 1000 + 551)).assertTrue();
    });

    // 同一毫秒内的第二次点击（双击最典型的样子）必须被挡。
    it('同一时刻的重复点击被挡', 0, (): void => {
      expect(utilityActionAllowedAt(1000, 1000)).assertFalse();
    });

    // 进页面后的第一次点击必须放行：`utilityActionAtMs` 初值是 0，而 nowMs 永远
    // 是 `Date.now()`（1.7e12 量级），差值远大于 550。
    //
    // 注意 0 是"从未放行过"的哨兵、不是一个真实时刻——判定里没有 `lastMs === 0`
    // 的特判，靠的就是真实时钟够大。所以别拿 `utilityActionAllowedAt(0, 1)` 当
    // 反例："nowMs = 1" 在真机上不存在。
    it('从未点过时第一次放行', 0, (): void => {
      const gate: Gate = new Gate();
      expect(gate.atMs).assertEqual(0);
      expect(utilityActionAllowedAt(0, REAL_NOW_MS)).assertTrue();
      expect(gate.allow(REAL_NOW_MS)).assertTrue();
      expect(gate.atMs).assertEqual(REAL_NOW_MS);
    });

    // 被拒时页面不刷新时间戳（判定通过才写）。所以连点不会把闸无限续期：
    // 从第一次放行算起满 550ms 就放行，中间点了多少次都一样。
    it('被拒的点击不续期', 0, (): void => {
      const gate: Gate = new Gate();
      expect(gate.allow(1000)).assertTrue();
      expect(gate.allow(1200)).assertFalse();
      expect(gate.allow(1400)).assertFalse();
      // 仍以 1000 为准，1550 就该放行——若被拒时也写了时间戳，这里会是 false。
      expect(gate.allow(1550)).assertTrue();
      expect(gate.atMs).assertEqual(1550);
    });

    // 【本批最要紧的一条】联系人 / 电话 / 位置三个动作共用**同一把**闸：
    // 点了联系人卡片，紧接着点电话或位置也会被挡。这是有意的（三者都会拉起
    // 外部 Ability，一把全局闸才挡得住"弹出两个外部应用"）。
    //
    // 将来若拆成三把独立的闸（每个动作各记各的时间戳），本用例会红——那说明
    // 发生的是**行为变更**，不是重构，别改测试，走行为变更的评审与真机验收。
    it('三个动作共享同一把闸', 0, (): void => {
      const gate: Gate = new Gate();
      // 点联系人卡片：放行。
      expect(gate.allow(1000)).assertTrue();
      // 100ms 后点电话：被同一把闸挡住（若各记各的时间戳，这里会变成 true）。
      expect(gate.allow(1100)).assertFalse();
      // 再 100ms 后点位置：还是被挡（同上）。
      expect(gate.allow(1200)).assertFalse();
      // 三个动作共用一个时间戳，所以窗口是从**第一次**放行算起的 550ms。
      expect(gate.allow(1550)).assertTrue();
    });

    // `openSharedContact` 在无 userId、无 vcard 时会以 skipGuard=true 直接调
    // `openSharedPhone`——同一次点击不该被自己刚写下的时间戳挡住。页面靠
    // skipGuard 参数跳过判定，这里记录该语义：不跳过就一定是 false。
    it('联系人转拨号若不跳过判定就会自锁', 0, (): void => {
      const gate: Gate = new Gate();
      expect(gate.allow(1000)).assertTrue();
      expect(gate.allow(1000)).assertFalse();
    });
  });
}
