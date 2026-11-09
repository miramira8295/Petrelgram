import { TimerFns } from '../tdkit/TdClient';
import { nextTimeOffset, startOffset } from './StreamSegmentMath';

export type SegmentFetcher = (channelId: number, timeOffset: number, scale: number) => Promise<Uint8Array>;
export type SegmentSink = (channelId: number, timeOffset: number, bytes: Uint8Array) => void;

const MAX_RETRIES: number = 5;

export class GroupCallStreamSession {
  private fetch: SegmentFetcher;
  private sink: SegmentSink;
  private timer: TimerFns;
  private stopped: boolean = false;
  private channelId: number = 0;
  private scale: number = 0;
  private cursor: number = 0;
  private generation: number = 0;
  private retryTimerId: number = -1;

  constructor(fetch: SegmentFetcher, sink: SegmentSink, timer?: TimerFns) {
    this.fetch = fetch;
    this.sink = sink;
    this.timer = timer ?? {
      setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
  }

  start(channelId: number, scale: number, liveEdgeMs: number, backSegments: number): void {
    if (this.retryTimerId !== -1) {
      this.timer.clearTimeout(this.retryTimerId);
      this.retryTimerId = -1;
    }
    this.stopped = false;
    this.channelId = channelId;
    this.scale = scale;
    this.cursor = startOffset(liveEdgeMs, scale, backSegments);
    this.generation = this.generation + 1;
    const generation = this.generation;
    this.pump(0, generation);
  }

  stop(): void {
    this.stopped = true;
    this.generation = this.generation + 1;
    if (this.retryTimerId !== -1) {
      this.timer.clearTimeout(this.retryTimerId);
      this.retryTimerId = -1;
    }
  }

  private pump(attempt: number, generation: number): void {
    if (this.stopped || generation !== this.generation) { return; }
    const offset = this.cursor;
    this.fetch(this.channelId, offset, this.scale).then((bytes: Uint8Array) => {
      if (this.stopped || generation !== this.generation) { return; }
      this.sink(this.channelId, offset, bytes);
      this.cursor = nextTimeOffset(this.cursor, this.scale);
      this.pump(0, generation);
    }).catch(() => {
      if (this.stopped || generation !== this.generation) { return; }
      if (attempt + 1 <= MAX_RETRIES) {
        const delay = Math.min(4000, 300 * Math.pow(2, attempt));
        this.retryTimerId = this.timer.setTimeout(() => {
          if (this.stopped || generation !== this.generation) { return; }
          this.retryTimerId = -1;
          this.pump(attempt + 1, generation);
        }, delay);
      } else {
        // 放弃这一段,前进以免卡死
        this.cursor = nextTimeOffset(this.cursor, this.scale);
        this.pump(0, generation);
      }
    });
  }
}
