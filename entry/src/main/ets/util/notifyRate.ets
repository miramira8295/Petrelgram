// 本地通知的发送限频。
//
// 【为什么需要】系统对单个应用发布**新**通知的频次是硬限制：每秒 10 条，超了
// 直接抛错误码 1600009「The notification sending frequency reaches the upper
// limit.」（官方《通知概述》：「单个应用发布新通知的频次累计不能超过每秒 10 条，
// 更新通知的频次累计不能超过每秒 20 条。所有三方应用发布新通知的频次累计不能
// 超过每秒 15 条」）。
//
// 真机日志（2026-08-29 PLA-AL10，preview.5）里一段 3940 行中有 45 条这个错误，
// 而且是**连号成串**地失败（236671..236679 一瞬间全灭）。位置紧跟在一批
// `request timeout` 后面——网络恢复，TDLib 把离线期间的消息一次补推进来，
// NotificationService 逐条直发，瞬间撞穿上限。**被拒的那些通知用户根本没看见。**
//
// 所以不能直发，要排队按最小间隔放行。
//
// 【间隔为什么取 110 而不是 100】限制是每秒 10 条，理论间隔 100ms。但那 15 条/秒
// 的上限是**所有三方应用共享**的，别人也在发；踩着理论值走，一次抖动就又超了。
// 多留 10% 的余量，代价是一批 N 条要多花 N×10ms。
export const NOTIFY_MIN_GAP_MS: number = 110;

// 队列上限。积压超过这个数说明是极端补推，再排下去只是让通知拖着尾巴慢慢冒，
// 用户已经进应用看过了。
export const NOTIFY_QUEUE_MAX: number = 50;

// 距离上一次发布还要等多久才能发下一条。lastAt <= 0 表示还没发过，立即放行。
export function publishDelayMs(lastAt: number, now: number,
  gapMs: number = NOTIFY_MIN_GAP_MS): number {
  if (lastAt <= 0) {
    return 0;
  }
  const since: number = now - lastAt;
  // 时钟回拨（since < 0）按"刚发过"处理，等满一个间隔，别一次性放行一整队。
  if (since < 0) {
    return gapMs;
  }
  return since >= gapMs ? 0 : gapMs - since;
}

// 队列超长时该从**队首**丢掉几条。丢最旧的：用户最关心的是最新那几条消息。
export function overflowCount(queueLen: number, max: number = NOTIFY_QUEUE_MAX): number {
  return queueLen > max ? queueLen - max : 0;
}
