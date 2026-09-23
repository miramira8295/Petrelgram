import { TdObject } from '../tdkit/TdTypes';

// 直播（群组视频通话）状态的判据。
//
// 【404 是答案，不是失败】getGroupCall 返回 404 意思是"这个通话在服务端已经
// 不存在了"——直播结束之后再问就是这个结果。两处调用方原来都把它当成"这次
// 没拿到信息"：ChatStore 里 `if (error.code !== 404) logE(...)` 直接吞掉，
// 会话页那边只置 loadState。于是 isLive / liveCallIsActive 永远停在 true，
// 表现就是用户报的「有些群组显示正在直播中，但实际上并没有」。
//
// 为什么这条值得单独成函数：它是"错误码 → 业务结论"的翻译，错一次的代价是
// 一个永远消不掉的徽标，而且两处调用方必须给出同一个答案。
export function groupCallGone(errorCode: number): boolean {
  return errorCode === 404;
}

// 其余错误码（网络、超时、限流）只说明这次没问到，**不能**据此撤掉一个已经
// 确认在直播的通话——撤掉再由推送加回来会让徽标闪烁。
export function groupCallErrorKeepsState(errorCode: number): boolean {
  return !groupCallGone(errorCode);
}

// 「在不在播」的判据——**不是 is_active**。
//
// 真机实测（2026-09-23，用户报的那个频道，[LiveDiag] 探针打的字段）：
//   is_active=true participants=0 rtmp=false scheduled=0 joined=false
// td 的 `is_active` 只说明"这个通话对象还没被销毁"。频道里建过一次视频聊天、
// 人全退光之后它就长期停在 true，getGroupCall 也不会返回 404（对象还在），
// 所以上面那条 404 判据一个都盖不到——用户复报"改了还是显示直播中"就是这个。
//
// 三条放行理由，缺一不可：
//   participant_count > 0  有人在里面；
//   is_rtmp_stream         OBS 推流的频道直播，主播不占参与者席位，
//                          零观众时 participant_count 就是 0，但它确实在播；
//   is_joined              我自己在里面，participant_count 还没回来也算。
// 另外预约中的通话（scheduled_start_date > 0）是"还没开始"，一律不算。
export function groupCallIsLive(groupCall: TdObject): boolean {
  if (((groupCall['is_active'] as boolean | undefined) ?? false) !== true) {
    return false;
  }
  if (((groupCall['scheduled_start_date'] as number | undefined) ?? 0) > 0) {
    return false;
  }
  if (((groupCall['is_rtmp_stream'] as boolean | undefined) ?? false) === true) {
    return true;
  }
  if (((groupCall['is_joined'] as boolean | undefined) ?? false) === true) {
    return true;
  }
  return ((groupCall['participant_count'] as number | undefined) ?? 0) > 0;
}
