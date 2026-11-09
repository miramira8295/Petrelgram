import { describe, expect, it } from '@ohos/hypium';
import { LinkTapGate } from '../main/ets/util/linkTapGuard';

// 链接解析要往返一次服务器。网络一慢，用户看不到任何反馈就会再点，于是
// 一个链接开出好几层页面。闸门要保证的是：解析在飞的时候，第二次点击
// 什么也不做；解析结束（成功、失败、或者久到不该再等）之后，闸门必须开。
export default function linkTapGuardTest() {
  describe('linkTapGuard', () => {
    it('is idle before anything is tapped', 0, () => {
      const gate = new LinkTapGate();
      expect(gate.busyUrl()).assertEqual('');
    });

    it('admits the first tap and records the url', 0, () => {
      const gate = new LinkTapGate();
      expect(gate.begin('https://t.me/foo', 0)).assertTrue();
      expect(gate.busyUrl()).assertEqual('https://t.me/foo');
    });

    // 单飞是全局的而不是按 url 的：解析期间点另一个链接同样得挡住，
    // 否则两个链接会并排推两层页面。
    it('rejects a second tap while one is in flight', 0, () => {
      const gate = new LinkTapGate();
      gate.begin('https://t.me/foo', 0);
      expect(gate.begin('https://t.me/foo', 10)).assertFalse();
      expect(gate.begin('https://t.me/bar', 10)).assertFalse();
      expect(gate.busyUrl()).assertEqual('https://t.me/foo');
    });

    it('admits the next tap once the first ends', 0, () => {
      const gate = new LinkTapGate();
      gate.begin('https://t.me/foo', 0);
      gate.end();
      expect(gate.busyUrl()).assertEqual('');
      expect(gate.begin('https://t.me/bar', 10)).assertTrue();
    });

    // 看门狗是这个闸门唯一的安全网：解析的下游有十来条分支，其中若干条
    // 不通知任何人就结束了。没有它，一次没人收尾的解析会把链接永久锁死。
    it('reopens on its own after the watchdog window', 0, () => {
      const gate = new LinkTapGate();
      gate.begin('https://t.me/foo', 0);
      expect(gate.begin('https://t.me/bar', LinkTapGate.WATCHDOG_MS - 1)).assertFalse();
      expect(gate.begin('https://t.me/bar', LinkTapGate.WATCHDOG_MS)).assertTrue();
      expect(gate.busyUrl()).assertEqual('https://t.me/bar');
    });

    // 收尾晚于下一次点击时不能误伤：end 只该关掉自己那一次。
    it('ignores a stale end from a previous tap', 0, () => {
      const gate = new LinkTapGate();
      gate.begin('https://t.me/foo', 0);
      gate.end();
      gate.begin('https://t.me/bar', 10);
      gate.endIf('https://t.me/foo');
      expect(gate.busyUrl()).assertEqual('https://t.me/bar');
      gate.endIf('https://t.me/bar');
      expect(gate.busyUrl()).assertEqual('');
    });
  });
}
