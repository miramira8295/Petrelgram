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
// 这里把 older 的语义抄成一个可测的小状态机，两侧共用一套说法：
//   armed=true      上膛，可以打一发
//   点火成功        armed=false，同时记下开枪时的 end（弱闸继续留着，防同一
//                   个 end 被重复敲）
//   重新上膛        只认用户驱动的输入。位置判据（"离末尾还有几行"）在向下
//                   这侧单独不可靠：内容一追加 groups 就变长，而视口没动，
//                   判据自动成立、闸门被内容增长自己顶开，等于没加。
export interface PageGate {
  armed: boolean;
  firedAtEnd: number;
}

// 完全上膛的初始态。-1 表示"还没开过枪"。
export function armedPageGate(): PageGate {
  const gate: PageGate = { armed: true, firedAtEnd: -1 };
  return gate;
}

// 能不能打这一发。两个条件都要满足：闸在膛上，且视口确实比上次开枪时更靠下。
export function canFirePageGate(gate: PageGate, end: number): boolean {
  return gate.armed && end > gate.firedAtEnd;
}

// 打完这一发之后的新状态。不改原对象。
export function firedPageGate(gate: PageGate, end: number): PageGate {
  const next: PageGate = { armed: false, firedAtEnd: end };
  return next;
}

// 重新上膛的判据。
//
// userDriven 为假时原样返回——程序性位移（贴底、prepend 复位、分级揭示把行
// 撑高推着视口走）都不该上膛，那正是跑飞的动力来源。
// 已经处在完全上膛态时也原样返回，省掉一次没必要的对象分配。
export function rearmPageGate(gate: PageGate, userDriven: boolean): PageGate {
  if (!userDriven) {
    return gate;
  }
  if (gate.armed && gate.firedAtEnd === -1) {
    return gate;
  }
  return armedPageGate();
}
