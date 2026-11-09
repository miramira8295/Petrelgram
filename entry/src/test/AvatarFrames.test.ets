import { describe, expect, it } from '@ohos/hypium';
import { avatarFramePlan, avatarFrameSize } from '../main/ets/util/avatarFramePlan';
import { AvatarFrameAsset, AvatarFramePool } from '../main/ets/util/avatarFramePool';

function u32(n: number): number[] { return [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]; }
function box(type: string, payload: number[]): number[] {
  return u32(payload.length + 8).concat(Array.from(type).map((c: string): number => c.charCodeAt(0)), payload);
}
function zeros(n: number): number[] { return new Array<number>(n).fill(0); }
function fixture(deltas: number[] = [30, 30, 30, 30, 30, 30], extra: string = '', width: number = 800): ArrayBuffer {
  const tkhd = zeros(84);
  [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824].forEach((n: number, i: number): void => {
    tkhd.splice(40 + i * 4, 4, ...u32(n));
  });
  const mdhd = zeros(12).concat(u32(1000), u32(deltas.reduce((a: number, b: number): number => a + b, 0)), zeros(4));
  const avc = zeros(78); avc.splice(24, 4, (width >> 8) & 255, width & 255, 3, 32);
  const stsd = box('stsd', zeros(4).concat(u32(1), box('avc1', avc)));
  let timing = zeros(4).concat(u32(deltas.length));
  deltas.forEach((d: number): void => { timing = timing.concat(u32(1), u32(d)); });
  const tables = stsd.concat(box('stts', timing), box('stsz', zeros(8).concat(u32(deltas.length))),
    extra === 'ctts' ? box('ctts', zeros(8)) : []);
  const media = box('mdia', box('mdhd', mdhd).concat(
    box('hdlr', zeros(8).concat([118, 105, 100, 101])), box('minf', box('stbl', tables))));
  const track = box('trak', box('tkhd', tkhd).concat(media, extra === 'edts' ? box('edts', []) : []));
  const bytes = box('moov', track.concat(extra === 'multi' ? track : []));
  return new Uint8Array(bytes).buffer;
}
function asset(bytes: number, id: number = 1): AvatarFrameAsset<number> {
  return { frames: [id], durationsMs: [30], size: 160, bytes: bytes };
}
async function turns(): Promise<void> { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); }

export default function avatarFramesTest() {
  describe('AvatarFramePlan', () => {
    it('六帧头像保持180ms原始节奏和微秒提帧时间', 0, () => {
      const p = avatarFramePlan(fixture(), 133);
      expect(p !== null).assertTrue();
      expect(p!.size).assertEqual(160);
      expect(p!.timesUs.join(',')).assertEqual('0,30000,60000,90000,120000,150000');
      expect(p!.durationsMs.join(',')).assertEqual('30,30,30,30,30,30');
      expect(p!.bytes).assertEqual(614400);
    });
    it('变帧间隔逐帧保留', 0, () => {
      const p = avatarFramePlan(fixture([20, 40, 60]), 160);
      expect(p!.timesUs.join(',')).assertEqual('0,20000,60000');
      expect(p!.durationsMs.join(',')).assertEqual('20,40,60');
    });
    it('同尺寸档共用且大头像不放大缓存', 0, () => {
      expect(avatarFrameSize(133)).assertEqual(avatarFrameSize(159));
      expect(avatarFrameSize(193)).assertEqual(0);
      expect(avatarFrameSize(NaN)).assertEqual(0);
    });
    it('帧数超预算回退', 0, () => {
      expect(avatarFramePlan(fixture(new Array<number>(25).fill(30)), 160) === null).assertTrue();
    });
    it('长片和超过60fps回退', 0, () => {
      expect(avatarFramePlan(fixture([800, 800]), 160) === null).assertTrue();
      expect(avatarFramePlan(fixture([10, 10]), 160) === null).assertTrue();
    });
    it('重排序和编辑时间线不猜测时间', 0, () => {
      expect(avatarFramePlan(fixture(undefined, 'ctts'), 160) === null).assertTrue();
      expect(avatarFramePlan(fixture(undefined, 'edts'), 160) === null).assertTrue();
    });
    it('多轨和非方形交给原播放器', 0, () => {
      expect(avatarFramePlan(fixture(undefined, 'multi'), 160) === null).assertTrue();
      expect(avatarFramePlan(fixture(undefined, '', 640), 160) === null).assertTrue();
    });
    it('截断和越界box安全拒绝', 0, () => {
      const b = fixture();
      expect(avatarFramePlan(b.slice(0, b.byteLength - 1), 160) === null).assertTrue();
      new DataView(b).setUint32(0, 0xffffffff);
      expect(avatarFramePlan(b, 160) === null).assertTrue();
    });
    it('样本数量与时间表不一致拒绝', 0, () => {
      const b = fixture(); new DataView(b).setUint32(b.byteLength - 4, 5);
      expect(avatarFramePlan(b, 160) === null).assertTrue();
    });
    it('大文件和无界box不分配帧缓存', 0, () => {
      expect(avatarFramePlan(new ArrayBuffer(2097153), 160) === null).assertTrue();
      const b = fixture(); new DataView(b).setUint32(0, 0);
      expect(avatarFramePlan(b, 160) === null).assertTrue();
    });
  });
  describe('AvatarFramePool', () => {
    it('两个头像共用一次准备和同一帧对象', 0, async () => {
      let loads = 0;
      const p = new AvatarFramePool<number>(100, 40, (): void => {});
      const load = async (): Promise<AvatarFrameAsset<number>> => { loads++; return asset(20); };
      const a = p.acquire('same', load); const b = p.acquire('same', load);
      expect(await a.ready === await b.ready).assertTrue(); expect(loads).assertEqual(1);
      a.release(); a.release(); expect(p.retainedBytes()).assertEqual(20);
      p.clearIdle(); expect(p.retainedBytes()).assertEqual(20);
      b.release(); p.clearIdle(); expect(p.retainedBytes()).assertEqual(0);
    });
    it('未开始就离屏不启动解码', 0, async () => {
      let loads = 0;
      const p = new AvatarFramePool<number>(100, 40, (): void => {});
      const a = p.acquire('gone', async (): Promise<AvatarFrameAsset<number>> => { loads++; return asset(20); });
      a.release(); expect(await a.ready === null).assertTrue(); expect(loads).assertEqual(0);
    });
    it('进行中最后一个引用离开时释放迟到结果', 0, async () => {
      let finish: ((a: AvatarFrameAsset<number>) => void) | null = null;
      let disposed = 0;
      const p = new AvatarFramePool<number>(100, 40, (): void => { disposed++; });
      const a = p.acquire('gone', (): Promise<AvatarFrameAsset<number>> => new Promise((resolve) => { finish = resolve; }));
      await turns(); a.release(); finish!(asset(20));
      expect(await a.ready === null).assertTrue(); expect(disposed).assertEqual(1); expect(p.retainedBytes()).assertEqual(0);
    });
    it('素材准备串行执行', 0, async () => {
      let finish: ((a: AvatarFrameAsset<number>) => void) | null = null;
      let second = false;
      const p = new AvatarFramePool<number>(100, 40, (): void => {});
      const a = p.acquire('a', (): Promise<AvatarFrameAsset<number>> => new Promise((resolve) => { finish = resolve; }));
      const b = p.acquire('b', async (): Promise<AvatarFrameAsset<number>> => { second = true; return asset(20); });
      await turns(); expect(second).assertFalse(); finish!(asset(20)); await a.ready; await b.ready;
      expect(second).assertTrue(); a.release(); b.release(); p.clearIdle();
    });
    it('LRU只淘汰空闲素材为解码预留空间', 0, async () => {
      const disposed: number[] = [];
      const p = new AvatarFramePool<number>(60, 40, (a): void => { disposed.push(a.frames[0]); });
      const a = p.acquire('a', async (): Promise<AvatarFrameAsset<number>> => asset(30, 1)); await a.ready; a.release();
      const b = p.acquire('b', async (): Promise<AvatarFrameAsset<number>> => asset(30, 2)); await b.ready;
      expect(disposed.join(',')).assertEqual('1'); expect(p.retainedBytes()).assertEqual(30); b.release(); p.clearIdle();
    });
    it('被使用的缓存占满预算时回退而不释放使用中的帧', 0, async () => {
      let loads = 0;
      const p = new AvatarFramePool<number>(60, 40, (): void => {});
      const a = p.acquire('a', async (): Promise<AvatarFrameAsset<number>> => asset(30)); await a.ready;
      const b = p.acquire('b', async (): Promise<AvatarFrameAsset<number>> => { loads++; return asset(20); });
      expect(await b.ready === null).assertTrue(); expect(loads).assertEqual(0); expect(p.retainedBytes()).assertEqual(30);
      a.release(); b.release(); p.clearIdle();
    });
    it('异常不堵住后续素材并可重新获取', 0, async () => {
      const p = new AvatarFramePool<number>(100, 40, (): void => {});
      const a = p.acquire('a', async (): Promise<AvatarFrameAsset<number>> => { throw new Error('decode'); });
      expect(await a.ready === null).assertTrue(); a.release();
      const b = p.acquire('a', async (): Promise<AvatarFrameAsset<number>> => asset(20));
      expect(await b.ready !== null).assertTrue(); b.release(); p.clearIdle();
    });
    it('超出预留预算的结果释放而不纳入缓存', 0, async () => {
      let disposed = 0;
      const p = new AvatarFramePool<number>(100, 40, (): void => { disposed++; });
      const a = p.acquire('big', async (): Promise<AvatarFrameAsset<number>> => asset(41));
      expect(await a.ready === null).assertTrue(); expect(disposed).assertEqual(1); a.release();
    });
  });
}
