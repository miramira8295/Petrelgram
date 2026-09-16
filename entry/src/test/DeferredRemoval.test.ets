import { describe, it, expect } from '@ohos/hypium';
import { DeferredRemoval } from '../main/ets/util/deferredRemoval';

// 下载中心的撤销：藏起来 → 到点执行 / 撤销放回 / 新一批先执行旧的 / 执行后等数据源没了再解除隐藏（2026-09-15）。

class FakeTimers {
  private fns: Map<number, () => void> = new Map<number, () => void>();
  private next: number = 1;

  schedule(fn: () => void): number {
    const id: number = this.next++;
    this.fns.set(id, fn);
    return id;
  }

  cancel(id: number): void {
    this.fns.delete(id);
  }

  fireAll(): void {
    const all: (() => void)[] = Array.from(this.fns.values());
    this.fns.clear();
    all.forEach((fn: () => void): void => { fn(); });
  }

  size(): number {
    return this.fns.size;
  }
}

function removal(timers: FakeTimers): DeferredRemoval {
  return new DeferredRemoval((): void => {}, 4000,
    (fn: () => void, _ms: number): number => timers.schedule(fn), (id: number): void => { timers.cancel(id); });
}

export default function deferredRemovalTest() {
  describe('deferredRemoval', () => {
    it('先藏起来，到点才执行一次；执行后仍藏着，数据源里没了才解除', 0, () => {
      const timers: FakeTimers = new FakeTimers();
      const r: DeferredRemoval = removal(timers);
      let commits: number = 0;
      r.schedule({ ids: ['a', 'b'], message: 'gone', commit: (): void => { commits++; } });
      expect(r.isHidden('a')).assertTrue();
      expect(r.message()).assertEqual('gone');
      expect(commits).assertEqual(0);
      timers.fireAll();
      expect(commits).assertEqual(1);
      expect(r.message()).assertEqual('');
      expect(r.isHidden('a')).assertTrue();
      r.forgetMissing(new Set<string>(['b']));
      expect(r.isHidden('a')).assertFalse();
      expect(r.isHidden('b')).assertTrue();
    });

    it('撤销：放回、不执行、定时器取消', 0, () => {
      const timers: FakeTimers = new FakeTimers();
      const r: DeferredRemoval = removal(timers);
      let commits: number = 0;
      r.schedule({ ids: ['a'], message: 'm', commit: (): void => { commits++; } });
      r.undo();
      expect(r.isHidden('a')).assertFalse();
      expect(timers.size()).assertEqual(0);
      timers.fireAll();
      expect(commits).assertEqual(0);
    });

    it('新一批进来先执行上一批；执行失败可以放回；等待撤销的那批不会被 forgetMissing 解除', 0, () => {
      const timers: FakeTimers = new FakeTimers();
      const r: DeferredRemoval = removal(timers);
      const done: string[] = [];
      r.schedule({ ids: ['a'], message: 'first', commit: (): void => { done.push('a'); } });
      r.schedule({ ids: ['b'], message: 'second', commit: (): void => { done.push('b'); } });
      expect(done.join(',')).assertEqual('a');
      expect(r.message()).assertEqual('second');
      r.forgetMissing(new Set<string>());
      expect(r.isHidden('b')).assertTrue();
      r.restore(['a']);
      expect(r.isHidden('a')).assertFalse();
      r.flush();
      expect(done.join(',')).assertEqual('a,b');
    });
  });
}
