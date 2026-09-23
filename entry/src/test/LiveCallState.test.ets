import { describe, it, expect } from '@ohos/hypium';
import { groupCallErrorKeepsState, groupCallGone, groupCallIsLive } from '../main/ets/util/liveCallState';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function call(over: Record<string, Object>): TdObject {
  const base: TdObject = { '@type': 'groupCall', 'id': 7, 'is_active': true };
  for (const k of Object.keys(over)) {
    base[k] = over[k];
  }
  return base;
}

export default function liveCallStateTest() {
  describe('LiveCallState', () => {
    // 404 = 通话在服务端已经没了 = 直播结束。原来两处调用方都把它当"没拿到
    // 信息"吞掉，于是徽标永远消不掉。
    it('404 表示通话已经结束', 0, () => {
      expect(groupCallGone(404)).assertTrue();
      expect(groupCallErrorKeepsState(404)).assertFalse();
    });

    // 网络/超时/限流只说明这次没问到，不能据此撤掉已确认在直播的通话——
    // 撤掉再由推送加回来会让徽标闪烁。
    it('其余错误码维持现状', 0, () => {
      expect(groupCallGone(500)).assertFalse();
      expect(groupCallGone(420)).assertFalse();
      expect(groupCallGone(-1)).assertFalse();
      expect(groupCallGone(0)).assertFalse();
      expect(groupCallErrorKeepsState(500)).assertTrue();
    });

    // ── is_active 不等于"有人在播" ────────────────────────────────────
    //
    // 真机实测（用户那个误报的频道，[LiveDiag] 探针）：
    //   is_active=true participants=0 rtmp=false scheduled=0 joined=false
    // 也就是说 td 的 is_active 只表示"这个通话对象还没被销毁"。频道里建过一次
    // 视频聊天、所有人退光之后，它就长期停在这个状态——横幅于是永远挂着。
    // 判"在不在播"必须看**人**：有参与者、或我自己在里面，才算。
    it('没有参与者的空通话不算在播', 0, () => {
      expect(groupCallIsLive(call({ 'participant_count': 0 }))).assertFalse();
    });

    it('有参与者才算在播', 0, () => {
      expect(groupCallIsLive(call({ 'participant_count': 1 }))).assertTrue();
      expect(groupCallIsLive(call({ 'participant_count': 128 }))).assertTrue();
    });

    // RTMP 推流（频道直播）是特例：主播从 OBS 推流并不作为"参与者"入座，
    // 一个还没有观众的直播 participant_count 就是 0，但它确实在播。
    it('RTMP 推流即使零观众也算在播', 0, () => {
      expect(groupCallIsLive(call({ 'participant_count': 0, 'is_rtmp_stream': true }))).assertTrue();
    });

    // 我自己在通话里，participant_count 还没同步回来也不能说"没在播"。
    it('自己已加入就算在播', 0, () => {
      expect(groupCallIsLive(call({ 'participant_count': 0, 'is_joined': true }))).assertTrue();
    });

    // is_active=false 是明确的"结束了"，任何其他字段都不能翻案。
    it('is_active 为假时一票否决', 0, () => {
      expect(groupCallIsLive(call({
        'is_active': false, 'participant_count': 20, 'is_rtmp_stream': true, 'is_joined': true
      }))).assertFalse();
    });

    // 预约中的通话（scheduled_start_date > 0）还没开始。防御性判断：真机上
    // 这类通话 is_active 本来就是 false，但这条不能靠"通常如此"来省。
    it('预约中的通话不算在播', 0, () => {
      expect(groupCallIsLive(call({
        'participant_count': 3, 'scheduled_start_date': 1900000000
      }))).assertFalse();
    });

    // 字段缺失时按"不在播"处理：宁可少挂一个横幅，也不要挂一个消不掉的。
    it('字段缺失一律当没在播', 0, () => {
      const empty: TdObject = { '@type': 'groupCall', 'id': 7 };
      expect(groupCallIsLive(empty)).assertFalse();
      expect(groupCallIsLive(call({}))).assertFalse();
    });
  });
}
