import { describe, expect, it } from '@ohos/hypium';
import { FanoutResult, fanoutShare } from '../main/ets/util/shareFanout';

// 同一份分享内容发给多个会话。
//
// 这里只管编排（串行、计数、收集失败），不碰 ShareInbox 也不碰 MessageStore：
// 真正的发送由调用方喂进来的 send 回调完成。所以它能在宿主上单测，而
// util/shareArrival 那一层（要 TDLib）不能。
//
// **串行**是有意的：并发发送会同时挤占 TDLib 的上传队列，而且失败时归因困难
// （分不清是这一条的问题还是被别的拖垮）。
export default function shareFanoutTest() {
  describe('shareFanout', () => {
    it('空目标：不发也不报错', 0, async () => {
      let calls: number = 0;
      const r: FanoutResult = await fanoutShare([], (): Promise<void> => {
        calls++;
        return Promise.resolve();
      });
      expect(calls).assertEqual(0);
      expect(r.ok).assertEqual(0);
      expect(r.failed).assertEqual(0);
    });

    it('全部成功', 0, async () => {
      const seen: number[] = [];
      const r: FanoutResult = await fanoutShare([1, -2, -1003], (id: number): Promise<void> => {
        seen.push(id);
        return Promise.resolve();
      });
      expect(r.ok).assertEqual(3);
      expect(r.failed).assertEqual(0);
      expect(r.failedIds.length).assertEqual(0);
      expect(seen.join(',')).assertEqual('1,-2,-1003');
    });

    // 一个失败不能中断其余的——用户选了 5 个，不能因为第 2 个发不出去就把
    // 后面 3 个也吞掉。
    it('部分失败：其余照发，失败的记下来', 0, async () => {
      const seen: number[] = [];
      const r: FanoutResult = await fanoutShare([1, 2, 3], (id: number): Promise<void> => {
        seen.push(id);
        return id === 2 ? Promise.reject(new Error('boom')) : Promise.resolve();
      });
      expect(seen.length).assertEqual(3);
      expect(r.ok).assertEqual(2);
      expect(r.failed).assertEqual(1);
      expect(r.failedIds.join(',')).assertEqual('2');
    });

    it('全部失败也不抛，如实计数', 0, async () => {
      const r: FanoutResult = await fanoutShare([7, 8], (): Promise<void> =>
        Promise.reject(new Error('nope')));
      expect(r.ok).assertEqual(0);
      expect(r.failed).assertEqual(2);
      expect(r.failedIds.join(',')).assertEqual('7,8');
    });

    // 串行：上一条的 Promise 兑现之后才发下一条。并发的话 finished 会在
    // started 全部入列之后才开始累加，交错顺序就不是这个形状。
    it('串行发送，不并发', 0, async () => {
      const trace: string[] = [];
      let release: (() => void) | null = null;
      const r: FanoutResult = await fanoutShare([1, 2], (id: number): Promise<void> => {
        trace.push(`start${id}`);
        return new Promise<void>((resolve: () => void): void => {
          release = (): void => {
            trace.push(`end${id}`);
            resolve();
          };
          // 立刻放行，但要经过一次微任务——并发实现会在这里把两个 start 排到一起。
          Promise.resolve().then((): void => {
            if (release !== null) {
              release();
            }
          });
        });
      });
      expect(r.ok).assertEqual(2);
      expect(trace.join(',')).assertEqual('start1,end1,start2,end2');
    });

    // 同一个会话被选中两次是不可能的（选择态去重），但扇出这一层也不该重发：
    // 两处都守住，任何一处出错都不会真的发两遍。
    it('重复的 chatId 只发一次', 0, async () => {
      const seen: number[] = [];
      const r: FanoutResult = await fanoutShare([5, 5, 6], (id: number): Promise<void> => {
        seen.push(id);
        return Promise.resolve();
      });
      expect(seen.join(',')).assertEqual('5,6');
      expect(r.ok).assertEqual(2);
    });
  });
}
