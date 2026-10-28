import { describe, it, expect } from '@ohos/hypium';
import { DeleteRowGroup, RowLeaveChannel, wholeDeleteRowIds } from '../main/ets/util/rowLeaveChannel';

// 删除动画：删之前等待可见气泡消散，随后 TDLib 的删除到达，
// 走 publishGroupsNow 里现成的 animateTo 塌陷。旁路通道，只惊动被删的那几行。
export default function rowLeaveChannelTest(): void {
  describe('rowLeaveChannel', (): void => {
    it('整组删除只标记完整被选中的相册行', 0, (): void => {
      const entries: DeleteRowGroup[] = [{ head: { rowId: 10 }, memberIds: [1, 2] },
        { head: { rowId: 30 }, memberIds: [3] }];
      expect(wholeDeleteRowIds(entries, [1, 3]).join(',')).assertEqual('30');
      expect(wholeDeleteRowIds(entries, [1, 2]).join(',')).assertEqual('10');
    });
    it('等待所有挂载行完成并共享粒子预算，离屏行不阻塞', 0, async (): Promise<void> => {
      const ch = new RowLeaveChannel();
      ch.subscribe(1, (): void => {}); ch.subscribe(2, (): void => {});
      let done = false;
      const playing = ch.play([1, 1, 2, 3], true).then((): void => { done = true; });
      expect(ch.particleBudget()).assertEqual(4000);
      expect(ch.value(3)).assertEqual(0);
      ch.complete(1); await Promise.resolve(); expect(done).assertFalse();
      ch.complete(2); await playing; expect(done).assertTrue();
    });
    it('回收和失败清理释放等待，关闭动效不标记行', 0, async (): Promise<void> => {
      const ch = new RowLeaveChannel();
      const off = ch.subscribe(1, (): void => {});
      await ch.play([1], false); expect(ch.value(1)).assertEqual(0);
      const recycled = ch.play([1], true); off(); await recycled;
      ch.clear(); ch.subscribe(1, (): void => {});
      const cancelled = ch.play([1], true); ch.clear(); await cancelled;
      expect(ch.value(1)).assertEqual(0);
    });
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
