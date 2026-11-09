// 「共享内容」三个动作的防连点闸。从 ChatPage.ets 搬来（原
// `private utilityActionAllowed()`，判据逐字不变，只把 `Date.now()` 和
// `this.utilityActionAtMs` 换成显式参数）。
//
// 【一把闸，不是三把——这是有意的】
// 共享联系人卡片（`openSharedContact`）、拨号（`openSharedPhone`）、打开位置
// （`openSharedLocation`）三个动作读写**同一个** `utilityActionAtMs` 时间戳。
// 后果是跨动作的：点了联系人卡片之后的 550ms 内，电话和位置动作**也会**被挡
// 住。这不是 bug——三者都会拉起外部 Ability（拨号盘 / 地图 / 联系人页），在
// 拉起过程中页面还留在前台且可点，一把全局闸才挡得住"手抖点两下不同的卡片、
// 弹出两个外部应用"。
//
// 所以：将来若把它拆成三把独立的闸（每个动作各记各的时间戳），那是**行为
// 变更**，不是重构——必须走行为变更的评审与真机验收，不能当作"顺手简化"。
//
// ChatPage 侧保留 `utilityActionAtMs` 字段和一个薄包装：判定通过才写时间戳
// （判定与写入的先后同原实现——拒绝时不刷新时间戳，连点不会把闸无限续期）。

// 两次动作之间的最小间隔。549ms 拒、550ms 放（边界是「大于等于才放行」）。
export const UTILITY_ACTION_MIN_GAP_MS: number = 550;

// lastMs：上一次放行的时刻（从未放行过时页面传 0）。
// nowMs：本次点击的时刻。
// 返回 true 表示放行，调用方**随后**要把 lastMs 更新成 nowMs。
export function utilityActionAllowedAt(lastMs: number, nowMs: number): boolean {
  return nowMs - lastMs >= UTILITY_ACTION_MIN_GAP_MS;
}
