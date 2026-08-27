// 分页闸门：一次点火后立刻下膛，只有**真实用户输入**才重新上膛。
//
// 向上分页（older）早就有这套：`olderArmed` 打一发就关，靠 onTouch(Down) 的
// 新手势、或"视口自己滚离触发区"重新上膛。向下分页（newer）原来只有一道
// `end <= firedAtEnd` 的弱闸，挡不住自持回路——
//
//   滑进底部触发区 → 取一页 newer → 行追加到末尾 → stackFromEnd 底部锚定把
//   视口往下推 → end 变大 → 弱闸失效 → 再取一页 → …… 直到 hasMoreNewer 为假。
//
// 真机日志实测：一次开会话连锁拉了 9 页，rowsBefore 132 → 356。
//
// ── 为什么 7c83b32 的第一版闸会把用户锁死 ────────────────────────────────
//
// 第一版的重新上膛只有两条路，两条都够不着真机上的实际情形：
//
//   a) onTouch(TouchType.Down) 无条件上膛；
//   b) ChatPage.onScrollIndex 里 `end < rows - 5`（视口离开底部触发区）那一支，
//      叠一条 listUserScrollActive。
//
// 真机日志（探针 [NewerFire]，53 次被挡全部 blockedBy=disarmed）：
//
//   end=27 rows=28 firedAt=3 armed=false ... 一路到 end=80 rows=81
//
// firedAt=3 全程不变 —— 唯一那一枪是**首屏程序性定位**打掉的（落点在未读锚点
// 的会话走 loadAround，首屏之后有一次 scrollToIndex；那一刻 touch=false
// userScroll=false，没有任何用户手势）。此后：
//
//   · (b) 永远进不去：用户就停在最后几行，end 恒等于 rows - 1，
//     `end < rows - 5` 恒假。闸永久合死。
//   · (a) 救不回来：一次 tap 也上膛，而紧随其后的任何一次 onScrollIndex
//     （哪怕是锚点复位这种程序性位移引起的）都能把这一枪消耗掉。
//
// 用户可见的形状正是"落点异常 + 推不动同时发生"：落点正常（loadHistory(0)
// 直接到底）没有那次程序性定位，闸还是满膛的，所以滑得动。
//
// ── 现在的判据 ───────────────────────────────────────────────────────────
//
// 位置判据（"离末尾还有几行"）在向下这侧根本不可靠，两头都不对：
//   · 内容一追加 groups 就变长而视口没动，判据自动成立 —— 闸被内容增长自己
//     顶开，等于没加；
//   · 用户停在尾部时判据恒假 —— 闸再也上不了膛。
// 所以整条位置判据从重新上膛里拿掉了，换成**手指位移**：
//
//   重新上膛 ⟺ 自上一枪以来，ScrollState.Scroll 的累计位移 ≥ REARM_DRAG_VP
//
// ScrollState.Scroll 的官方语义是"手指拖动列表 / 拖动滚动条 / 鼠标滚轮"，
// 惯性（Fling）和控制器的非动画滚动（Idle）都不在其内。于是：
//
//   · 首屏定位、锚点复位、scrollToIndex、scrollEdge 一律报 Idle，累计量恒 0，
//     它们**烧不掉也开不了**这道闸；
//   · 自动连锁的特征是"没有新的用户输入却连续放行"——连锁里手指没有位移，
//     累计量永远到不了阈值，第二页就被挡死；
//   · 用户持续下滑则每 REARM_DRAG_VP 换一页，想要 N 页就得真拖 N×REARM_DRAG_VP，
//     这正是"限制自动连锁、不限制用户持续下滑"。
//
// 另外闸上记着**这一枪是谁扣的扳机**（armedByUser）。会话开局的那一发是给首屏
// 自动补页用的，armedByUser=false；只有位移上膛/显式用户上膛才是 true。
// 向下追加的锚点复位据此判断这一页是不是用户翻出来的（见 util/appendAnchor）。
export interface PageGate {
  armed: boolean;
  // 当前这一膛是不是用户输入压上去的。会话开局那一发是程序性的。
  armedByUser: boolean;
  firedAtEnd: number;
  // 自上一枪以来累计的用户拖动位移（vp）。只有 ScrollState.Scroll 计入。
  dragSinceFire: number;
}

// 重新上膛需要的手指位移（vp）。约 1/6 屏高：够短，用户"往下推"时不会觉得
// 卡；够长，任何没有手指参与的连锁都到不了。
export const PAGE_GATE_REARM_DRAG_VP: number = 120;

// 完全上膛的初始态。-1 表示"还没开过枪"。
// byUser 默认假：不明确说是用户压的膛，就当成程序性的。
export function armedPageGate(byUser: boolean = false): PageGate {
  const gate: PageGate = {
    armed: true, armedByUser: byUser, firedAtEnd: -1, dragSinceFire: 0
  };
  return gate;
}

// 能不能打这一发。两个条件都要满足：闸在膛上，且视口确实比上次开枪时更靠下。
export function canFirePageGate(gate: PageGate, end: number): boolean {
  return gate.armed && end > gate.firedAtEnd;
}

// 这一枪是不是用户扣的扳机。请求发出时取值，一路带到发布点。
//
// 为什么不能在发布时回头看"用户是不是恰好还在滑"：那是时序巧合，一次轻扫打出
// 的页往往在手指离开之后才回来。也不能用 armed 本身代替——armed 表达的是
// "还能不能再打一枪"，不是"这一枪是谁扣的"。
export function pageGateShotIsUserDriven(gate: PageGate): boolean {
  return gate.armedByUser;
}

// 打完这一发之后的新状态。不改原对象。位移累计一并清零：下一页要重新攒。
export function firedPageGate(gate: PageGate, end: number): PageGate {
  const next: PageGate = {
    armed: false, armedByUser: false, firedAtEnd: end, dragSinceFire: 0
  };
  return next;
}

// 重新上膛的判据。
//
// userDriven 为假时原样返回——程序性位移（贴底、prepend 复位、首屏定位、分级
// 揭示把行撑高推着视口走）都不该上膛，那正是跑飞的动力来源。
// 已经处在完全上膛态时也原样返回，省掉一次没必要的对象分配。
export function rearmPageGate(gate: PageGate, userDriven: boolean): PageGate {
  if (!userDriven) {
    return gate;
  }
  if (gate.armed && gate.firedAtEnd === -1) {
    return gate;
  }
  return armedPageGate(true);
}

// 吃进一帧用户拖动位移，攒够阈值就重新上膛。
//
// 调用点只在 ScrollState.Scroll 那一支（见 ChatPage.onDidScroll）：这是"手指真
// 的在拖列表"唯一可靠的信号，而且**与视口位置无关**——用户停在最后几行照样能
// 上膛，这正是第一版锁死的那个洞。
//
// 取绝对值：List 的 scrollOffset 正负方向随实现约定，而"向上拖也能给 newer 闸
// 上膛"是无害的——canFirePageGate 还压着 end > firedAtEnd，往上拖只会让 end
// 变小；真正的连锁里则一帧手指位移都没有。这样判据不依赖符号约定，省掉一条
// 只能上机才能证伪的假设。
export function draggedPageGate(gate: PageGate, deltaVp: number,
  thresholdVp: number = PAGE_GATE_REARM_DRAG_VP): PageGate {
  if (gate.armed) {
    return gate;
  }
  const step: number = deltaVp < 0 ? -deltaVp : deltaVp;
  if (step <= 0) {
    return gate;
  }
  const total: number = gate.dragSinceFire + step;
  if (total < thresholdVp) {
    const next: PageGate = {
      armed: false, armedByUser: false,
      firedAtEnd: gate.firedAtEnd, dragSinceFire: total
    };
    return next;
  }
  return rearmPageGate(gate, true);
}
