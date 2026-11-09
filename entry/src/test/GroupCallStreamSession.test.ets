import { describe, it, expect } from '@ohos/hypium';
import { GroupCallStreamSession, SegmentFetcher, SegmentSink } from '../main/ets/services/GroupCallStreamSession';
import { TimerFns } from '../main/ets/tdkit/TdClient';

export default function groupCallStreamSessionTest() {
  describe('GroupCallStreamSession', () => {
    it('fetches_from_start_offset_and_steps_forward', 0, async () => {
      const asked: number[] = [];
      const fetch: SegmentFetcher = (ch: number, off: number, scale: number): Promise<Uint8Array> => {
        asked.push(off);
        return Promise.resolve(new Uint8Array([1]));
      };
      const delivered: number[] = [];
      const sink: SegmentSink = (ch: number, off: number, bytes: Uint8Array): void => { delivered.push(off); };
      const session = new GroupCallStreamSession(fetch, sink);
      // edge 20000, scale 0 (1000ms), back 2 -> start 18000
      session.start(1, 0, 20000, 2);
      // 让若干个 microtask 轮转,凑够至少 3 段
      for (let i = 0; i < 10; i++) { await Promise.resolve(); }
      session.stop();
      expect(asked[0]).assertEqual(18000);
      expect(asked[1]).assertEqual(19000);
      expect(delivered[0]).assertEqual(18000);
    });

    it('retries_same_offset_then_succeeds', 0, async () => {
      const fired: Array<() => void> = [];
      const timer: TimerFns = {
        setTimeout: (cb: () => void, _ms: number): number => { fired.push(cb); return fired.length; },
        clearTimeout: (_id: number): void => { }
      };
      const asked: number[] = [];
      let failOnce = true;
      const fetch: SegmentFetcher = (ch: number, off: number, scale: number): Promise<Uint8Array> => {
        asked.push(off);
        if (failOnce) {
          failOnce = false;
          return Promise.reject(new Error('boom'));
        }
        return Promise.resolve(new Uint8Array([1]));
      };
      const delivered: number[] = [];
      const sink: SegmentSink = (ch: number, off: number, bytes: Uint8Array): void => { delivered.push(off); };
      const session = new GroupCallStreamSession(fetch, sink, timer);
      session.start(1, 0, 20000, 2);
      // 让首个 fetch 的 reject 被 catch 处理,进入重试排程
      for (let i = 0; i < 5; i++) { await Promise.resolve(); }
      expect(fired.length).assertEqual(1);
      // 手动触发重试定时器:同一 offset 应被重新请求并在这次成功后立即停止,
      // 避免后续段无限级联推进而污染断言
      fired[0]();
      await Promise.resolve();
      session.stop();
      expect(asked[0]).assertEqual(18000);
      expect(asked[1]).assertEqual(18000);
      expect(delivered.length).assertEqual(1);
      expect(delivered[0]).assertEqual(18000);
    });

    it('gives_up_after_max_retries_and_advances', 0, async () => {
      const fired: Array<() => void> = [];
      const timer: TimerFns = {
        setTimeout: (cb: () => void, _ms: number): number => { fired.push(cb); return fired.length; },
        clearTimeout: (_id: number): void => { }
      };
      const asked: number[] = [];
      const fetch: SegmentFetcher = (ch: number, off: number, scale: number): Promise<Uint8Array> => {
        asked.push(off);
        return Promise.reject(new Error('boom'));
      };
      const delivered: number[] = [];
      const sink: SegmentSink = (ch: number, off: number, bytes: Uint8Array): void => { delivered.push(off); };
      const session = new GroupCallStreamSession(fetch, sink, timer);
      session.start(1, 0, 20000, 2);
      // 初次 fetch 失败并排程第 1 次重试
      for (let i = 0; i < 5; i++) { await Promise.resolve(); }
      // 依次手动触发 5 次重试(达到 MAX_RETRIES),之后应放弃并前进到下一段
      for (let round = 0; round < 5; round++) {
        expect(fired.length).assertEqual(round + 1);
        fired[round]();
        for (let i = 0; i < 5; i++) { await Promise.resolve(); }
      }
      session.stop();
      // 前 6 次都是对 18000 的请求(初次 + 5 次重试),第 7 次前进到 19000
      expect(asked.length).assertEqual(7);
      for (let i = 0; i < 6; i++) { expect(asked[i]).assertEqual(18000); }
      expect(asked[6]).assertEqual(19000);
      expect(delivered.length).assertEqual(0);
    });

    it('start_twice_clears_prior_retry_timer', 0, async () => {
      const fired: Array<() => void> = [];
      const cleared: number[] = [];
      const timer: TimerFns = {
        setTimeout: (cb: () => void, _ms: number): number => { fired.push(cb); return fired.length; },
        clearTimeout: (id: number): void => { cleared.push(id); }
      };
      const asked: number[] = [];
      const fetch: SegmentFetcher = (ch: number, off: number, scale: number): Promise<Uint8Array> => {
        asked.push(off);
        return Promise.reject(new Error('boom'));
      };
      const delivered: number[] = [];
      const sink: SegmentSink = (ch: number, off: number, bytes: Uint8Array): void => { delivered.push(off); };
      const session = new GroupCallStreamSession(fetch, sink, timer);
      session.start(1, 0, 20000, 2);
      // 首次 fetch 失败,排程第 1 次重试定时器(id=1)
      for (let i = 0; i < 5; i++) { await Promise.resolve(); }
      expect(fired.length).assertEqual(1);
      const priorRetryTimerId = fired.length;
      // 未调用 stop(),直接再次 start():应清理上一次残留的重试定时器
      session.start(1, 0, 20000, 2);
      session.stop();
      expect(cleared.includes(priorRetryTimerId)).assertTrue();
    });

    it('no_delivery_after_stop', 0, async () => {
      let resolveFetch: ((bytes: Uint8Array) => void) | null = null;
      const asked: number[] = [];
      const fetch: SegmentFetcher = (ch: number, off: number, scale: number): Promise<Uint8Array> => {
        asked.push(off);
        return new Promise<Uint8Array>((resolve) => { resolveFetch = resolve; });
      };
      const delivered: number[] = [];
      const sink: SegmentSink = (ch: number, off: number, bytes: Uint8Array): void => { delivered.push(off); };
      const session = new GroupCallStreamSession(fetch, sink);
      session.start(1, 0, 20000, 2);
      await Promise.resolve();
      session.stop();
      expect(asked.length).assertEqual(1);
      expect(asked[0]).assertEqual(18000);
      resolveFetch!(new Uint8Array([1]));
      for (let i = 0; i < 5; i++) { await Promise.resolve(); }
      expect(delivered.length).assertEqual(0);
    });
  });
}
