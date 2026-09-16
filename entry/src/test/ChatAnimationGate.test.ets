import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  resetChatAnimationGateForTest, setChatAnimationSuspended, setChatGateTimersForTest, subscribeChatAnimationGate
} from '../main/ets/util/chatAnimationGate';

// 会话动画总闸：关闸同一刻全部生效，开闸按「屏幕上 → 不知道 → 屏幕外」逐个放出
// （2026-09-15，停稳那一下所有贴纸一起起播，弱设备上卡一下）。

interface PendingTimer {
  id: number;
  run: () => void;
  cancelled: boolean;
}

class FakeTimers {
  pending: PendingTimer[] = [];
  private nextId: number = 1;

  install(): void {
    setChatGateTimersForTest((run: () => void, _delayMs: number): number => {
      const timer: PendingTimer = { id: this.nextId++, run: run, cancelled: false };
      this.pending.push(timer);
      return timer.id;
    }, (id: number): void => {
      for (const t of this.pending) {
        if (t.id === id) {
          t.cancelled = true;
        }
      }
    });
  }

  // 跑最早的一个还没被取消的定时器；没有就返回 false。
  runNext(): boolean {
    while (this.pending.length > 0) {
      const t: PendingTimer = this.pending.shift() as PendingTimer;
      if (!t.cancelled) {
        t.run();
        return true;
      }
    }
    return false;
  }
}

export default function chatAnimationGateTest() {
  describe('chatAnimationGate', () => {
    beforeEach(() => {
      resetChatAnimationGateForTest();
    });

    it('订阅时立刻拿到当前值', 0, () => {
      setChatAnimationSuspended(true);
      const got: boolean[] = [];
      subscribeChatAnimationGate((s: boolean): void => { got.push(s); });
      expect(got.join(',')).assertEqual('true');
    });

    it('关闸：所有订阅者同一刻收到 true', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      const log: string[] = [];
      subscribeChatAnimationGate((s: boolean): void => { log.push(`a${s}`); });
      subscribeChatAnimationGate((s: boolean): void => { log.push(`b${s}`); });
      log.length = 0;
      setChatAnimationSuspended(true);
      expect(log.join(',')).assertEqual('atrue,btrue');
      expect(timers.pending.length).assertEqual(0);
    });

    it('开闸：第一个立刻放，其余每隔一拍放一个', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      const log: string[] = [];
      setChatAnimationSuspended(true);
      subscribeChatAnimationGate((s: boolean): void => { log.push(`a${s}`); });
      subscribeChatAnimationGate((s: boolean): void => { log.push(`b${s}`); });
      subscribeChatAnimationGate((s: boolean): void => { log.push(`c${s}`); });
      log.length = 0;
      setChatAnimationSuspended(false);
      expect(log.join(',')).assertEqual('afalse');
      expect(timers.runNext()).assertTrue();
      expect(log.join(',')).assertEqual('afalse,bfalse');
      expect(timers.runNext()).assertTrue();
      expect(log.join(',')).assertEqual('afalse,bfalse,cfalse');
      expect(timers.runNext()).assertFalse();
    });

    it('屏幕上的先放，不知道的其次，屏幕外的最后', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      const log: string[] = [];
      setChatAnimationSuspended(true);
      subscribeChatAnimationGate((s: boolean): void => { if (!s) { log.push('off'); } }, (): boolean => false);
      subscribeChatAnimationGate((s: boolean): void => { if (!s) { log.push('unknown'); } });
      subscribeChatAnimationGate((s: boolean): void => { if (!s) { log.push('on'); } }, (): boolean => true);
      setChatAnimationSuspended(false);
      while (timers.runNext()) {
      }
      expect(log.join(',')).assertEqual('on,unknown,off');
    });

    it('放到一半又关闸：没放的不再放', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      const log: string[] = [];
      setChatAnimationSuspended(true);
      subscribeChatAnimationGate((s: boolean): void => { log.push(`a${s}`); });
      subscribeChatAnimationGate((s: boolean): void => { log.push(`b${s}`); });
      log.length = 0;
      setChatAnimationSuspended(false);
      setChatAnimationSuspended(true);
      expect(timers.runNext()).assertFalse();
      expect(log.join(',')).assertEqual('afalse,atrue,btrue');
    });

    it('排队期间退订的直接跳过', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      const log: string[] = [];
      setChatAnimationSuspended(true);
      subscribeChatAnimationGate((s: boolean): void => { log.push(`a${s}`); });
      const offB = subscribeChatAnimationGate((s: boolean): void => { log.push(`b${s}`); });
      subscribeChatAnimationGate((s: boolean): void => { log.push(`c${s}`); });
      log.length = 0;
      setChatAnimationSuspended(false);
      offB();
      while (timers.runNext()) {
      }
      expect(log.join(',')).assertEqual('afalse,cfalse');
    });
  });
}
