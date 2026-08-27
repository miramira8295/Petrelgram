import { describe, expect, it } from '@ohos/hypium';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId, pendingNextFrameCount,
  resetNextFrameQueue, setNextFrameScheduler
} from '../main/ets/util/nextFrameQueue';

// 手动 flush 的假调度器。宿主环境里没有帧、也不想等真实的事件循环，而这一项
// 要断言的恰恰是时序性质（起了几个定时器、哪一批跑），所以调度必须可注入。
class FakeClock {
  // 起过几次定时器。合并的全部意义就在这个数字上。
  armed: number = 0;
  private due: (() => void)[] = [];

  schedule(run: () => void): void {
    this.armed++;
    this.due.push(run);
  }

  // 只跑此刻已经排上的那些。跑的过程中新排的留到下一次 flush——正好用来验
  // 「执行中 enqueue 进下一批」。
  flush(): void {
    const now: (() => void)[] = this.due;
    this.due = [];
    for (const run of now) {
      run();
    }
  }
}

function armFakeClock(): FakeClock {
  // reset 会把调度器恢复成默认的 setTimeout，所以必须先 reset 再注入。
  resetNextFrameQueue();
  const clock = new FakeClock();
  setNextFrameScheduler((run: () => void): void => { clock.schedule(run); });
  return clock;
}

export default function nextFrameQueueTest() {
  describe('nextFrameQueue', () => {
    // 一帧里复用 N 行 = N×(3~4) 次 enqueue，但只该起一个定时器。
    it('arms_one_timer_for_many_enqueues', 0, (): void => {
      const clock = armFakeClock();
      const ran: number[] = [];
      for (let i = 0; i < 6; i++) {
        const owner: number = nextFrameOwnerId();
        enqueueNextFrame(owner, (): void => { ran.push(i); });
      }
      expect(clock.armed).assertEqual(1);
      expect(ran.length).assertEqual(0);
      clock.flush();
      expect(ran.length).assertEqual(6);
      expect(ran.join(',')).assertEqual('0,1,2,3,4,5');
      resetNextFrameQueue();
    });

    // 组件在回调跑之前又被复用了一次：只有最后那次的回调该跑，否则会把订阅
    // 挂回上一条消息的参数上。
    it('keeps_only_the_last_task_per_owner', 0, (): void => {
      const clock = armFakeClock();
      const owner: number = nextFrameOwnerId();
      const ran: string[] = [];
      enqueueNextFrame(owner, (): void => { ran.push('stale'); });
      enqueueNextFrame(owner, (): void => { ran.push('fresh'); });
      expect(clock.armed).assertEqual(1);
      expect(pendingNextFrameCount()).assertEqual(1);
      clock.flush();
      expect(ran.length).assertEqual(1);
      expect(ran[0]).assertEqual('fresh');
      resetNextFrameQueue();
    });

    // 不同 owner 各留各的，覆盖只发生在同一个 owner 上。
    it('keeps_tasks_from_different_owners_apart', 0, (): void => {
      const clock = armFakeClock();
      const a: number = nextFrameOwnerId();
      const b: number = nextFrameOwnerId();
      expect(a === b).assertFalse();
      const ran: string[] = [];
      enqueueNextFrame(a, (): void => { ran.push('a'); });
      enqueueNextFrame(b, (): void => { ran.push('b'); });
      expect(pendingNextFrameCount()).assertEqual(2);
      clock.flush();
      expect(ran.join(',')).assertEqual('a,b');
      resetNextFrameQueue();
    });

    // 回调里再 enqueue 必须进下一帧。否则一次 flush 可能一路接下去，把「合并成
    // 一帧」变成「一帧里跑完所有后续帧的活」。
    it('defers_a_task_enqueued_during_the_flush', 0, (): void => {
      const clock = armFakeClock();
      const owner: number = nextFrameOwnerId();
      const later: number = nextFrameOwnerId();
      const ran: string[] = [];
      enqueueNextFrame(owner, (): void => {
        ran.push('first');
        enqueueNextFrame(later, (): void => { ran.push('second'); });
      });
      clock.flush();
      expect(ran.join(',')).assertEqual('first');
      // 新的一批要重新武装一个定时器。
      expect(clock.armed).assertEqual(2);
      expect(pendingNextFrameCount()).assertEqual(1);
      clock.flush();
      expect(ran.join(',')).assertEqual('first,second');
      resetNextFrameQueue();
    });

    // 一个组件的回调抛错不能吞掉后面所有组件的重挂。
    it('isolates_a_throwing_task', 0, (): void => {
      const clock = armFakeClock();
      const bad: number = nextFrameOwnerId();
      const good: number = nextFrameOwnerId();
      const ran: string[] = [];
      enqueueNextFrame(bad, (): void => { throw new Error('boom'); });
      enqueueNextFrame(good, (): void => { ran.push('good'); });
      clock.flush();
      expect(ran.join(',')).assertEqual('good');
      expect(pendingNextFrameCount()).assertEqual(0);
      resetNextFrameQueue();
    });

    // flush 之后队列必须为空，而且不会自己再武装一次。
    it('empties_the_queue_after_a_flush', 0, (): void => {
      const clock = armFakeClock();
      const owner: number = nextFrameOwnerId();
      enqueueNextFrame(owner, (): void => {});
      expect(pendingNextFrameCount()).assertEqual(1);
      clock.flush();
      expect(pendingNextFrameCount()).assertEqual(0);
      expect(clock.armed).assertEqual(1);
      // 空队列再 flush 一次也不该出事。
      clock.flush();
      expect(pendingNextFrameCount()).assertEqual(0);
      resetNextFrameQueue();
    });

    // 组件回收/销毁时撤掉待办：过期回调再跑一次会把订阅挂到一个不在树上的实例上。
    it('cancels_a_pending_task_for_one_owner', 0, (): void => {
      const clock = armFakeClock();
      const gone: number = nextFrameOwnerId();
      const alive: number = nextFrameOwnerId();
      const ran: string[] = [];
      enqueueNextFrame(gone, (): void => { ran.push('gone'); });
      enqueueNextFrame(alive, (): void => { ran.push('alive'); });
      cancelNextFrame(gone);
      expect(pendingNextFrameCount()).assertEqual(1);
      clock.flush();
      expect(ran.join(',')).assertEqual('alive');
      resetNextFrameQueue();
    });

    // 撤一个从没排过队的 owner 不该有副作用。
    it('ignores_a_cancel_for_an_unknown_owner', 0, (): void => {
      const clock = armFakeClock();
      const owner: number = nextFrameOwnerId();
      enqueueNextFrame(owner, (): void => {});
      cancelNextFrame(nextFrameOwnerId());
      expect(pendingNextFrameCount()).assertEqual(1);
      clock.flush();
      expect(pendingNextFrameCount()).assertEqual(0);
      resetNextFrameQueue();
    });
  });
}
