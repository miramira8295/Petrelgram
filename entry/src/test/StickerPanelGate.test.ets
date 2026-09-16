import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  chatAnimationSuspended, resetChatAnimationGateForTest, setChatAnimationSuspended
} from '../main/ets/util/chatAnimationGate';
import {
  pauseStickerPanelForScroll, resetStickerPanelGate, resetStickerPanelGateForTest, resumeStickerPanelAfterScroll,
  STICKER_PANEL_RESUME_DELAY_MS, stickerPanelGateForTest, stickerPanelSuspended, subscribeAnimationGateFor
} from '../main/ets/util/stickerPanelGate';

// 贴纸抽屉的动画闸门：滑动即停，停稳后延迟开闸、屏幕上的先放；与会话那道互不牵连（2026-09-15）。

interface PendingTimer {
  id: number;
  delayMs: number;
  run: () => void;
  cancelled: boolean;
}

class FakeTimers {
  pending: PendingTimer[] = [];
  private nextId: number = 1;

  install(): void {
    stickerPanelGateForTest().setTimersForTest((run: () => void, delayMs: number): number => {
      const timer: PendingTimer = { id: this.nextId++, delayMs: delayMs, run: run, cancelled: false };
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

  live(): PendingTimer[] {
    return this.pending.filter((t: PendingTimer): boolean => !t.cancelled);
  }

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

export default function stickerPanelGateTest() {
  describe('stickerPanelGate', () => {
    beforeEach(() => {
      resetStickerPanelGateForTest();
      resetChatAnimationGateForTest();
    });

    it('滑动开始立刻关闸，抽屉里的格子同一刻收到', 0, () => {
      const log: string[] = [];
      subscribeAnimationGateFor(true, (s: boolean): void => { log.push(`p${s}`); });
      log.length = 0;
      pauseStickerPanelForScroll();
      expect(log.join(',')).assertEqual('ptrue');
      expect(stickerPanelSuspended()).assertTrue();
    });

    it('停下后等一拍才开闸', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      pauseStickerPanelForScroll();
      resumeStickerPanelAfterScroll();
      expect(stickerPanelSuspended()).assertTrue();
      expect(timers.live().length).assertEqual(1);
      expect(timers.live()[0].delayMs).assertEqual(STICKER_PANEL_RESUME_DELAY_MS);
      expect(timers.runNext()).assertTrue();
      expect(stickerPanelSuspended()).assertFalse();
    });

    it('等开闸期间又滑起来：那次开闸作废', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      pauseStickerPanelForScroll();
      resumeStickerPanelAfterScroll();
      pauseStickerPanelForScroll();
      expect(timers.live().length).assertEqual(0);
      expect(stickerPanelSuspended()).assertTrue();
    });

    it('开闸按屏幕优先逐个放', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      const log: string[] = [];
      pauseStickerPanelForScroll();
      subscribeAnimationGateFor(true, (s: boolean): void => { if (!s) { log.push('off'); } }, (): boolean => false);
      subscribeAnimationGateFor(true, (s: boolean): void => { if (!s) { log.push('on'); } }, (): boolean => true);
      resumeStickerPanelAfterScroll();
      while (timers.runNext()) {
      }
      expect(log.join(',')).assertEqual('on,off');
    });

    it('抽屉那道和会话那道互不牵连', 0, () => {
      const log: string[] = [];
      subscribeAnimationGateFor(true, (s: boolean): void => { log.push(`p${s}`); });
      subscribeAnimationGateFor(false, (s: boolean): void => { log.push(`c${s}`); });
      log.length = 0;
      pauseStickerPanelForScroll();
      expect(log.join(',')).assertEqual('ptrue');
      expect(chatAnimationSuspended()).assertFalse();
      setChatAnimationSuspended(true);
      expect(log.join(',')).assertEqual('ptrue,ctrue');
    });

    it('收起抽屉直接复位成开着，等着的开闸也作废', 0, () => {
      const timers = new FakeTimers();
      timers.install();
      pauseStickerPanelForScroll();
      resumeStickerPanelAfterScroll();
      resetStickerPanelGate();
      expect(timers.live().length).assertEqual(0);
      expect(stickerPanelSuspended()).assertFalse();
    });
  });
}
