import { describe, it, expect } from '@ohos/hypium';
import {
  PrependChunker, PrependChunkClock, PrependChunkHost, headOffsetOf, PREPEND_CHUNK_GAP_MS
} from '../main/ets/util/prependChunker';

// 头插分批（方案 A）。背景：Repeat(reusable:false) 一次头插超过 List.cachedCount
// 行，可视行全部新建（翻历史每页 29 行 ⇒ 每次翻页整屏重建）。分批器每次只放出
// 紧贴已显示内容的一批，其余到点续发；中间态永远是完整快照的一个后缀。

class FakeTimer {
  id: number;
  at: number;
  callback: () => void;
  live: boolean = true;

  constructor(id: number, at: number, callback: () => void) {
    this.id = id;
    this.at = at;
    this.callback = callback;
  }
}

class FakeClock implements PrependChunkClock {
  t: number = 10000;
  private seq: number = 0;
  private timers: FakeTimer[] = [];

  now(): number {
    return this.t;
  }

  schedule(callback: () => void, delayMs: number): number {
    this.seq++;
    this.timers.push(new FakeTimer(this.seq, this.t + delayMs, callback));
    return this.seq;
  }

  cancel(handle: number): void {
    for (const timer of this.timers) {
      if (timer.id === handle) {
        timer.live = false;
      }
    }
  }

  armed(): number {
    let count: number = 0;
    for (const timer of this.timers) {
      if (timer.live) {
        count++;
      }
    }
    return count;
  }

  // 时间前进 ms，按到点顺序触发定时器；触发时 now() 就是它的到点时刻。
  advance(ms: number): void {
    const end: number = this.t + ms;
    while (true) {
      let due: FakeTimer | null = null;
      for (const timer of this.timers) {
        if (timer.live && timer.at <= end && (due === null || timer.at < due.at)) {
          due = timer;
        }
      }
      if (due === null) {
        break;
      }
      due.live = false;
      this.t = Math.max(this.t, due.at);
      due.callback();
    }
    this.t = end;
  }
}

// 模拟 ChatPage：发布 = 过一遍 shape，结果当作新的已显示行；续发 = 拿最近的 target 再发。
class TestPage {
  displayed: string[];
  chunker: PrependChunker<string>;

  constructor(displayed: string[], chunker: PrependChunker<string>) {
    this.displayed = displayed;
    this.chunker = chunker;
  }

  publish(target: string[]): void {
    this.displayed = this.chunker.shape(this.displayed, target);
  }

  republish(): void {
    const target: string[] | null = this.chunker.latestTarget();
    if (target !== null) {
      this.publish(target);
    }
  }
}

class TestHost implements PrependChunkHost {
  k: number = 3;
  ok: boolean = true;
  republished: number = 0;
  page: TestPage | null = null;

  chunkRows: () => number = (): number => this.k;
  allowed: () => boolean = (): boolean => this.ok;
  republish: () => void = (): void => {
    this.republished++;
    if (this.page !== null) {
      this.page.republish();
    }
  };
}

function identityOf(row: string): string {
  return row;
}

function rows(prefix: string, count: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < count; i++) {
    out.push(`${prefix}${i}`);
  }
  return out;
}

class Rig {
  clock: FakeClock = new FakeClock();
  host: TestHost = new TestHost();
  chunker: PrependChunker<string>;
  page: TestPage;

  constructor(displayed: string[]) {
    this.chunker = new PrependChunker<string>(identityOf, true, this.clock);
    this.chunker.bind(this.host);
    this.page = new TestPage(displayed, this.chunker);
    this.host.page = this.page;
  }
}

export default function prependChunkerTest(): void {
  describe('prependChunker', (): void => {
    it('headOffsetOf：先试提示下标，不准再顺序找；找不到或超出扫描上限返回 -1', 0, (): void => {
      const shown: string[] = rows('d', 4);
      const target: string[] = rows('n', 5).concat(shown);
      expect(headOffsetOf<string>(shown, target, identityOf, 5, 8)).assertEqual(5);
      expect(headOffsetOf<string>(shown, target, identityOf, -1, 8)).assertEqual(5);
      expect(headOffsetOf<string>(shown, rows('x', 9), identityOf, 5, 8)).assertEqual(-1);
      expect(headOffsetOf<string>([], target, identityOf, 5, 8)).assertEqual(-1);
      expect(headOffsetOf<string>(shown, target, identityOf, 5, 3)).assertEqual(-1);
    });

    it('总开关关、没绑宿主、已显示为空：原样发布，不排定时器', 0, (): void => {
      const clock: FakeClock = new FakeClock();
      const host: TestHost = new TestHost();
      const shown: string[] = rows('d', 4);
      const target: string[] = rows('n', 20).concat(shown);
      const off: PrependChunker<string> = new PrependChunker<string>(identityOf, false, clock);
      off.bind(host);
      expect(off.shape(shown, target) === target).assertTrue();
      const unbound: PrependChunker<string> = new PrependChunker<string>(identityOf, true, clock);
      expect(unbound.shape(shown, target) === target).assertTrue();
      const on: PrependChunker<string> = new PrependChunker<string>(identityOf, true, clock);
      on.bind(host);
      expect(on.shape([], target) === target).assertTrue();
      expect(clock.armed()).assertEqual(0);
    });

    it('头插不超过一批：一次发完，不排定时器', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      const target: string[] = rows('n', 3).concat(rig.page.displayed);
      rig.page.publish(target);
      expect(rig.page.displayed === target).assertTrue();
      expect(rig.chunker.pendingRows()).assertEqual(0);
      expect(rig.clock.armed()).assertEqual(0);
    });

    it('头插超过一批：只放出紧贴已显示内容的 k 行，其余扣着并排一个定时器', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      rig.page.publish(rows('n', 10).concat(rig.page.displayed));
      expect(rig.page.displayed.length).assertEqual(7);
      expect(rig.page.displayed[0]).assertEqual('n7');
      expect(rig.page.displayed[3]).assertEqual('d0');
      expect(rig.chunker.pendingRows()).assertEqual(7);
      expect(rig.clock.armed()).assertEqual(1);
    });

    it('到点逐批续发直到发完：10 行每批 3 行 = 立即 1 批 + 续发 3 次', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      rig.page.publish(rows('n', 10).concat(rig.page.displayed));
      rig.clock.advance(PREPEND_CHUNK_GAP_MS);
      expect(rig.page.displayed[0]).assertEqual('n4');
      rig.clock.advance(PREPEND_CHUNK_GAP_MS);
      expect(rig.page.displayed[0]).assertEqual('n1');
      rig.clock.advance(PREPEND_CHUNK_GAP_MS);
      expect(rig.page.displayed[0]).assertEqual('n0');
      expect(rig.page.displayed.length).assertEqual(14);
      expect(rig.host.republished).assertEqual(3);
      expect(rig.chunker.pendingRows()).assertEqual(0);
      expect(rig.clock.armed()).assertEqual(0);
    });

    it('间隔没到时来的其它发布（尾部追加）照常发，头部照样扣着，也不重复排定时器', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      const target: string[] = rows('n', 10).concat(rig.page.displayed);
      rig.page.publish(target);
      rig.clock.advance(10);
      const appended: string[] = target.concat(['z']);
      rig.page.publish(appended);
      expect(rig.page.displayed.length).assertEqual(8);
      expect(rig.page.displayed[0]).assertEqual('n7');
      expect(rig.page.displayed[7]).assertEqual('z');
      expect(rig.clock.armed()).assertEqual(1);
      rig.clock.advance(PREPEND_CHUNK_GAP_MS);
      expect(rig.page.displayed[0]).assertEqual('n4');
      expect(rig.page.displayed[rig.page.displayed.length - 1]).assertEqual('z');
    });

    it('已显示的第一行在新快照里找不到（跳转落地/整窗替换）：原样发布并清掉在途批次', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      rig.page.publish(rows('n', 10).concat(rig.page.displayed));
      const jumped: string[] = rows('j', 12);
      rig.page.publish(jumped);
      expect(rig.page.displayed === jumped).assertTrue();
      expect(rig.chunker.pendingRows()).assertEqual(0);
      expect(rig.clock.armed()).assertEqual(0);
      rig.clock.advance(PREPEND_CHUNK_GAP_MS * 3);
      expect(rig.host.republished).assertEqual(0);
    });

    it('宿主此刻不允许（页面隐藏/首屏揭示期）：一次发完并清掉在途批次', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      const target: string[] = rows('n', 10).concat(rig.page.displayed);
      rig.page.publish(target);
      rig.host.ok = false;
      rig.page.publish(target);
      expect(rig.page.displayed.length).assertEqual(14);
      expect(rig.chunker.pendingRows()).assertEqual(0);
      expect(rig.clock.armed()).assertEqual(0);
    });

    it('刚插过一小批，紧接着来一大页：整页先扣着，到点再按批放', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      const small: string[] = rows('s', 2).concat(rig.page.displayed);
      rig.page.publish(small);
      expect(rig.page.displayed === small).assertTrue();
      expect(rig.clock.armed()).assertEqual(0);
      rig.clock.advance(20);
      rig.page.publish(rows('n', 10).concat(small));
      expect(rig.page.displayed.length).assertEqual(6);
      expect(rig.page.displayed[0]).assertEqual('s0');
      expect(rig.chunker.pendingRows()).assertEqual(10);
      expect(rig.clock.armed()).assertEqual(1);
      rig.clock.advance(PREPEND_CHUNK_GAP_MS);
      expect(rig.page.displayed.length).assertEqual(9);
      expect(rig.page.displayed[0]).assertEqual('n7');
    });

    it('扣着头部期间尾部被裁（行数变少）：头部仍然扣着，只发裁剪', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 10));
      rig.page.publish(rows('n', 10).concat(rig.page.displayed));
      expect(rig.page.displayed.length).assertEqual(13);
      const trimmed: string[] = rows('n', 10).concat(['d0', 'd1']);
      rig.page.publish(trimmed);
      expect(rig.page.displayed.length).assertEqual(5);
      expect(rig.page.displayed[0]).assertEqual('n7');
      expect(rig.page.displayed[4]).assertEqual('d1');
      expect(rig.chunker.pendingRows()).assertEqual(7);
    });

    it('dispose 之后定时器不再续发', 0, (): void => {
      const rig: Rig = new Rig(rows('d', 4));
      rig.page.publish(rows('n', 10).concat(rig.page.displayed));
      rig.chunker.dispose();
      expect(rig.clock.armed()).assertEqual(0);
      rig.clock.advance(PREPEND_CHUNK_GAP_MS * 2);
      expect(rig.host.republished).assertEqual(0);
    });
  });
}
