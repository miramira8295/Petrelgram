import { describe, expect, it } from '@ohos/hypium';
import { PlaySlotDriver, PlaySlotHost } from '../main/ets/pages/chat/PlaySlotDriver';
import { slotKey } from '../main/ets/pages/chat/playSlot';

// 播放位竞选簇（第二轮 R2-C）搬进 PlaySlotDriver 之后的**契约**测试。
//
// PlaySlotRegistry.test.ets 的 24 条用例钉的是"谁该当选"（入选线、驻留、pin、
// 视口中心）。那些不用重复。这里钉的是搬迁本身最容易坏、又最没有本地手段
// 发现的三件事：
//   1. 起播位置必须在 playSlotKey 之前落下——applySlot 是**一个动作**；
//   2. 三重闸门（查看器开着 / 页面不可见 / 总闸门关）缺一不可；
//   3. 两处查看器交接的取值与顺序。
//
// 【为什么走 report + pin 路径而不是等驻留】
// PLAY_SLOT_DWELL_MS = 400，而 PlaySlotDriver 内部一律用 Date.now()（不像
// PlaySlotRegistry 那样把 now 当参数收），测试没法把时间调快。pin 之后
// tick 一次即可当选，不必攒满驻留，下面用它把换届驱动起来。
//
// **但 pin 之前必须先 report。** pin 只是给候选表里**已存在**的条目加锁，
// 候选表是空的时候 elect() 无从选起——这正是 closeViewer 里那句原注释说的
// 「pin() 记的目标在候选表补上之前一样选不出来，是同一个幂等收敛」。
// PlaySlotRegistry.test.ets 里 pin 那条用例前面同样先 report 了两条。
// 第一版这里漏了 report，三条用例全红，红的是用例前提不是被测代码。

class AppliedSlot {
  key: string = '';
  startMs: number = -1;
}

class FakeHost implements PlaySlotHost {
  viewerId: number = 0;
  visible: boolean = true;
  compete: boolean = true;
  applied: AppliedSlot[] = [];

  viewerMsgId: () => number = (): number => this.viewerId;
  pageVisible: () => boolean = (): boolean => this.visible;
  competeEnabled: () => boolean = (): boolean => this.compete;
  applySlot: (key: string, startMs: number) => void = (key: string, startMs: number): void => {
    const slot: AppliedSlot = new AppliedSlot();
    slot.key = key;
    slot.startMs = startMs;
    this.applied.push(slot);
  };
}

function driverOn(host: FakeHost): PlaySlotDriver {
  const driver: PlaySlotDriver = new PlaySlotDriver();
  driver.bind(host);
  driver.subscribe();
  return driver;
}

export default function playSlotDriverTest() {
  describe('PlaySlotDriver', () => {

    // 【1】本批最重要的一条：换届时下发的起播位置来自气泡进度表。
    //
    // 把 recordPosition 记下的 12000 删掉、或者把 applySlot 里那句取值改成 0，
    // 这条立刻红。故障在真机上是**静默**的——不崩不报，只是每次从全屏查看器
    // 退回来的那条视频都从头播。
    it('换届时把气泡记录的进度作为起播位置一起下发', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      // 先让候选表里有这一条，pin 才有东西可锁。
      d.setViewportCenter(500);
      d.reportMedia(7, -1, 0.95, 500);
      d.recordPosition(7, 12000);
      // pin 让它立刻具备当选资格（不必攒满驻留）；armSettle 里的 tick 完成换届。
      d.handoffFromViewer(7, -1, 12000);
      d.armSettle();

      expect(host.applied.length).assertEqual(1);
      expect(host.applied[0].key).assertEqual(slotKey(7, -1));
      expect(host.applied[0].startMs).assertEqual(12000);
      d.dispose();
    });

    // 【2】没有记录过进度的那条，起播位置是 0 而不是 NaN/undefined。
    it('没有进度记录时起播位置是 0', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      d.setViewportCenter(500);
      d.reportMedia(9, -1, 0.95, 500);
      d.handoffFromViewer(9, -1, 0);
      d.armSettle();

      expect(host.applied.length).assertEqual(1);
      expect(host.applied[0].startMs).assertEqual(0);
      d.dispose();
    });

    // 【3】三重闸门逐个验。任何一项被"简化"掉，查看器打开期间气泡播放器就还
    // 在跑，同一个文件两个播放器互抢下载分片。
    it('查看器开着时不接受气泡上报', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      host.viewerId = 5;
      d.reportMedia(1, -1, 0.95, 500);
      d.armSettle();

      expect(host.applied.length).assertEqual(0);
      d.dispose();
    });

    it('页面不可见时不接受气泡上报', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      host.visible = false;
      d.reportMedia(1, -1, 0.95, 500);
      d.armSettle();

      expect(host.applied.length).assertEqual(0);
      d.dispose();
    });

    it('总闸门关掉时不接受气泡上报', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      host.compete = false;
      d.reportMedia(1, -1, 0.95, 500);
      d.armSettle();

      expect(host.applied.length).assertEqual(0);
      d.dispose();
    });

    // 【4】闸门只挡"喂"，不挡"停"。策略关掉要真的把在播的那条停下来——
    // reset() 把播放位清空，订阅者把 playSlotKey 清成 ''，气泡的
    // VideoBubbleSurface 随之卸载，播放和下载一起停。
    it('总闸门关掉时把已当选的播放位清空', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      d.setViewportCenter(500);
      d.reportMedia(7, -1, 0.95, 500);
      d.handoffFromViewer(7, -1, 500);
      d.armSettle();
      expect(host.applied[0].key).assertEqual(slotKey(7, -1));

      host.compete = false;
      d.onPolicyDisabled();

      expect(host.applied.length).assertEqual(2);
      expect(host.applied[1].key).assertEqual('');
      expect(host.applied[1].startMs).assertEqual(0);
      d.dispose();
    });

    // 【5】气泡 → 查看器：取的是这条消息记下的进度。
    it('handoffToViewer 返回该条气泡记录的进度', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      d.recordPosition(3, 8500);
      expect(d.handoffToViewer(3)).assertEqual(8500);
      // 没记录过的那条回 0。
      expect(d.handoffToViewer(4)).assertEqual(0);
      d.dispose();
    });

    // 【6】查看器 → 气泡：写回的是查看器交出来的那个值，不是气泡的旧值。
    // 这条同时守住 closeViewer 里"必须在 animateTo 之前调"的时序——调用点挪到
    // animateTo 之后的话，传进来的 positionMs 会被 @Monitor 清成 0。
    it('handoffFromViewer 用查看器交出的进度覆盖气泡旧值', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      d.recordPosition(3, 1000);
      d.handoffFromViewer(3, -1, 26000);

      expect(d.handoffToViewer(3)).assertEqual(26000);
      d.dispose();
    });

    // 【7】会话退场后进度表清空——长会话里随刷屏无界增长过一次就够了。
    it('dispose 之后进度表清空', 0, () => {
      const host: FakeHost = new FakeHost();
      const d: PlaySlotDriver = driverOn(host);

      d.recordPosition(3, 8500);
      d.dispose();

      expect(d.handoffToViewer(3)).assertEqual(0);
    });
  });
}
