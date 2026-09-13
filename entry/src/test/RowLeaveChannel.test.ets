import { describe, it, expect } from '@ohos/hypium';
import { RowLeaveChannel } from '../main/ets/util/rowLeaveChannel';

// 删除动画（issue #149）：删之前先把要走的行标记出来淡出，随后 TDLib 的删除到达，
// 走 publishGroupsNow 里现成的 animateTo 塌陷。旁路通道，只惊动被删的那几行。
export default function rowLeaveChannelTest(): void {
  describe('rowLeaveChannel', (): void => {
    it('标记的行值为 1，其余为 0；订阅立即拿到现值', 0, (): void => {
      const ch: RowLeaveChannel = new RowLeaveChannel();
      ch.mark([7, 9]);
      expect(ch.value(7)).assertEqual(1);
      expect(ch.value(8)).assertEqual(0);
      let seen: number = -1;
      ch.subscribe(9, (v: number): void => { seen = v; });
      expect(seen).assertEqual(1);
    });
    it('标记时只通知被标记的行', 0, (): void => {
      const ch: RowLeaveChannel = new RowLeaveChannel();
      let a: number = -1;
      let b: number = -1;
      ch.subscribe(1, (v: number): void => { a = v; });
      ch.subscribe(2, (v: number): void => { b = v; });
      a = -1; b = -1;
      ch.mark([1]);
      expect(a).assertEqual(1);
      expect(b).assertEqual(-1);
    });
    it('clear 归零并通知曾被标记的行（删除失败要还原）', 0, (): void => {
      const ch: RowLeaveChannel = new RowLeaveChannel();
      let a: number = -1;
      ch.subscribe(3, (v: number): void => { a = v; });
      ch.mark([3]);
      expect(a).assertEqual(1);
      ch.clear();
      expect(a).assertEqual(0);
      expect(ch.value(3)).assertEqual(0);
    });
    it('退订之后不再收到', 0, (): void => {
      const ch: RowLeaveChannel = new RowLeaveChannel();
      let hits: number = 0;
      const off: () => void = ch.subscribe(4, (): void => { hits++; });
      const before: number = hits;
      off();
      ch.mark([4]);
      expect(hits).assertEqual(before);
    });
  });
}
