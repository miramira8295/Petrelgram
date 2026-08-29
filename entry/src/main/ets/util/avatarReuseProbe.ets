// ⚠️ **临时探针，验完即删**（issue #137「翻消息时头像会闪」/ #176 的复验）。
//
// 头像那条修法——回收时记下挂在谁身上、复用时若还是同一个人就不清 path——
// **一个字的日志都不打**。于是 2026-08-29 用户报「preview.5 好像也闪」时，手上
// 三份真机日志里关于头像什么都没有：视口位移那条线有数据可查，头像这条线只能
// 靠猜。这条探针就是来补那块空白的。
//
// 判读方式：
//   · kept=true  → 这次复用被修复救下来了（旧代码在这里会空一帧，翻得快就是
//     一闪一闪）；这个数越大说明修复越有用；
//   · kept=false → 真的换了发送者，清 path 是**对的**，但仍会空一帧直到新图
//     到位。这是固有代价，不是回归。
//   · 若用户报的闪次数 ≈ kept=false 的条数 → 闪来自这条固有路径，要治得换思路
//     （比如先画首字母底再淡入），不是再修一次复用；
//   · 若 kept=false 很少而用户仍报闪 → 头像不是元凶，回去查视口位移那条线。
//
// params= 回答「aboutToReuse 拿不拿得到新值」：按官方《@ReusableV2装饰器》
// aboutToReuse 没有入参，预期恒为 false，也就是恒走下一帧兜底。
//
// 删除清单（结论落地后一次删干净）：
//   1. 本文件；
//   2. MessageBubble.LiveSenderAvatar.aboutToReuse 里的调用与 import；
//   3. LightweightPlainTextBubble.LightweightSenderAvatar.aboutToReuse 里的同上。
import { logW } from './log';

// 诊断日志环攒够 300 行才落盘，样本上限压小一点，免得把别的探针挤出去。
const AVATAR_PROBE_LIMIT: number = 40;
let logged: number = 0;
let keptTotal: number = 0;
let clearedTotal: number = 0;

export function probeAvatarReuse(src: string, fromKey: string, toKey: string,
  keptPath: boolean, fromParams: boolean): void {
  if (logged >= AVATAR_PROBE_LIMIT) {
    return;
  }
  logged++;
  if (keptPath) {
    keptTotal++;
  } else {
    clearedTotal++;
  }
  logW(`[AvatarBlank] ${src} key=${fromKey === '' ? '-' : fromKey}->${toKey}` +
    ` kept=${keptPath} params=${fromParams}` +
    ` totals kept=${keptTotal} cleared=${clearedTotal}`);
}
