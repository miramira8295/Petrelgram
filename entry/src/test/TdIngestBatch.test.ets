import { describe, expect, it } from '@ohos/hypium';
import { TdIngestBatch, BatchTimerFns } from '../main/ets/tdkit/tdIngestBatch';

// 手动定时器：决定回调什么时候跑，测试不依赖真实时钟。
class ManualTimer implements BatchTimerFns {
  private cb: (() => void) | null = null;
  private nextId: number = 1;
  armed: boolean = false;
  firedCount: number = 0;

  setTimeout(cb: () => void, _ms: number): number {
    this.cb = cb;
    this.armed = true;
    return this.nextId++;
  }

  clearTimeout(_id: number): void {
    this.cb = null;
    this.armed = false;
  }

  fire(): void {
    const cb = this.cb;
    this.cb = null;
    this.armed = false;
    if (cb !== null) {
      this.firedCount += 1;
      cb();
    }
  }
}

function obj(tag: string): object {
  const value: Record<string, Object> = { '@type': tag };
  return value;
}

function tagsOf(batches: object[][]): string {
  return batches.map((batch: object[]): string =>
    batch.map((item: object): string => (item as Record<string, Object>)['@type'] as string).join(',')).join('|');
}

export default function tdIngestBatchTest() {
  describe('tdIngestBatch', () => {
    it('窗口内的多条合成一批，顺序即到达序', 0, (): void => {
      const batches: object[][] = [];
      const timer = new ManualTimer();
      const batch = new TdIngestBatch((items: object[]): void => { batches.push(items); }, timer, 8, 64);
      batch.push(obj('a'));
      batch.push(obj('b'));
      batch.push(obj('c'));
      expect(batches.length).assertEqual(0);
      expect(batch.pending()).assertEqual(3);
      expect(timer.armed).assertTrue();
      timer.fire();
      expect(batches.length).assertEqual(1);
      expect(tagsOf(batches)).assertEqual('a,b,c');
      expect(batch.pending()).assertEqual(0);
    });

    it('到上限立即发，不等定时器', 0, (): void => {
      const batches: object[][] = [];
      const timer = new ManualTimer();
      const batch = new TdIngestBatch((items: object[]): void => { batches.push(items); }, timer, 8, 4);
      batch.push(obj('1'));
      batch.push(obj('2'));
      batch.push(obj('3'));
      expect(batches.length).assertEqual(0);
      batch.push(obj('4'));
      expect(batches.length).assertEqual(1);
      expect(tagsOf(batches)).assertEqual('1,2,3,4');
      // 发完之后定时器应当已被取消，不会再多打一枪。
      expect(timer.armed).assertFalse();
    });

    it('flush() 立即发且空批不发', 0, (): void => {
      const batches: object[][] = [];
      const timer = new ManualTimer();
      const batch = new TdIngestBatch((items: object[]): void => { batches.push(items); }, timer, 8, 64);
      batch.flush();
      expect(batches.length).assertEqual(0);
      batch.push(obj('x'));
      batch.flush();
      expect(batches.length).assertEqual(1);
      expect(tagsOf(batches)).assertEqual('x');
      batch.flush();
      expect(batches.length).assertEqual(1);
    });

    it('reset() 丢掉积压且不发', 0, (): void => {
      const batches: object[][] = [];
      const timer = new ManualTimer();
      const batch = new TdIngestBatch((items: object[]): void => { batches.push(items); }, timer, 8, 64);
      batch.push(obj('stale'));
      batch.reset();
      expect(batches.length).assertEqual(0);
      expect(batch.pending()).assertEqual(0);
      expect(timer.armed).assertFalse();
      timer.fire();
      expect(batches.length).assertEqual(0);
    });

    it('多批之间保持各自的时间段顺序', 0, (): void => {
      const batches: object[][] = [];
      const timer = new ManualTimer();
      const batch = new TdIngestBatch((items: object[]): void => { batches.push(items); }, timer, 8, 2);
      batch.push(obj('a'));
      batch.push(obj('b'));
      batch.push(obj('c'));
      timer.fire();
      expect(batches.length).assertEqual(2);
      expect(tagsOf(batches)).assertEqual('a,b|c');
    });
  });
}
