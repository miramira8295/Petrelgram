// 只接管能准确还原时间线的短方形 AVC 头像；其余继续交给 AVPlayer。
export const AVATAR_SOURCE_MAX_BYTES: number = 2 * 1024 * 1024;
export const AVATAR_FRAME_MAX_COUNT: number = 24;
export const AVATAR_FRAME_MAX_BYTES: number = 4 * 1024 * 1024;
export const AVATAR_CACHE_MAX_BYTES: number = 16 * 1024 * 1024;

export interface AvatarFramePlan {
  size: number;
  timesUs: number[];
  durationsMs: number[];
  bytes: number;
}
interface Box { type: string; start: number; end: number; }

export function avatarFrameSize(pixels: number): number {
  if (!Number.isFinite(pixels) || pixels <= 0 || pixels > 192) { return 0; }
  return Math.max(96, Math.ceil(pixels / 32) * 32);
}

function boxes(v: DataView, start: number, end: number): Box[] {
  const out: Box[] = [];
  while (start < end) {
    if (start + 8 > end || out.length >= 256) { throw new Error('invalid MP4 boxes'); }
    const length = v.getUint32(start);
    // 扩展长度、无界box、碎片等格式不进入这条快速路径。
    if (length < 8 || start + length > end) { throw new Error('invalid MP4 size'); }
    const type = String.fromCharCode(v.getUint8(start + 4), v.getUint8(start + 5),
      v.getUint8(start + 6), v.getUint8(start + 7));
    out.push({ type: type, start: start, end: start + length });
    start += length;
  }
  return out;
}
function child(v: DataView, parent: Box, type: string): Box {
  const matches = boxes(v, parent.start + 8, parent.end).filter((b: Box): boolean => b.type === type);
  if (matches.length !== 1) { throw new Error('missing or duplicate MP4 box'); }
  return matches[0];
}
function need(b: Box, bytes: number): void {
  if (b.end - b.start < bytes) { throw new Error('short MP4 box'); }
}

export function avatarFramePlan(buffer: ArrayBuffer, pixels: number): AvatarFramePlan | null {
  const size = avatarFrameSize(pixels);
  if (size === 0 || buffer.byteLength > AVATAR_SOURCE_MAX_BYTES) { return null; }
  try {
    const v = new DataView(buffer);
    const roots = boxes(v, 0, buffer.byteLength);
    if (roots.some((b: Box): boolean => b.type === 'moof')) { return null; }
    const moovs = roots.filter((b: Box): boolean => b.type === 'moov');
    if (moovs.length !== 1) { return null; }
    const tracks = boxes(v, moovs[0].start + 8, moovs[0].end)
      .filter((b: Box): boolean => b.type === 'trak');
    // 头像应为无音轨单视频；多轨、编辑时间线、B帧重排序暂不做近似处理。
    if (tracks.length !== 1) { return null; }
    const track = tracks[0];
    if (boxes(v, track.start + 8, track.end).some((b: Box): boolean => b.type === 'edts')) { return null; }
    const tkhd = child(v, track, 'tkhd');
    need(tkhd, 92);
    if (v.getUint8(tkhd.start + 8) !== 0) { return null; }
    const matrix: number[] = [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824];
    for (let i = 0; i < matrix.length; i++) {
      if (v.getUint32(tkhd.start + 48 + i * 4) !== matrix[i]) { return null; }
    }
    const mdia = child(v, track, 'mdia');
    const handler = child(v, mdia, 'hdlr');
    need(handler, 20);
    if (v.getUint32(handler.start + 16) !== 0x76696465) { return null; } // vide
    const mdhd = child(v, mdia, 'mdhd');
    need(mdhd, 32);
    if (v.getUint8(mdhd.start + 8) !== 0) { return null; }
    const scale = v.getUint32(mdhd.start + 20);
    const duration = v.getUint32(mdhd.start + 24);
    if (scale === 0 || duration === 0 || duration * 1000 / scale > 1500) { return null; }
    const stbl = child(v, child(v, mdia, 'minf'), 'stbl');
    if (boxes(v, stbl.start + 8, stbl.end).some((b: Box): boolean => b.type === 'ctts')) { return null; }
    const stsd = child(v, stbl, 'stsd');
    need(stsd, 16);
    if (v.getUint32(stsd.start + 12) !== 1) { return null; }
    const descriptions = boxes(v, stsd.start + 16, stsd.end);
    if (descriptions.length !== 1 || descriptions[0].type !== 'avc1') { return null; }
    const avc = descriptions[0];
    need(avc, 86);
    const width = v.getUint16(avc.start + 32);
    const height = v.getUint16(avc.start + 34);
    if (width !== height || width < 1 || width > 2048) { return null; }
    const stts = child(v, stbl, 'stts');
    need(stts, 16);
    const entries = v.getUint32(stts.start + 12);
    if (entries < 1 || entries > AVATAR_FRAME_MAX_COUNT) { return null; }
    need(stts, 16 + entries * 8);
    const times: number[] = [];
    const durations: number[] = [];
    let ticks = 0;
    for (let i = 0; i < entries; i++) {
      const count = v.getUint32(stts.start + 16 + i * 8);
      const delta = v.getUint32(stts.start + 20 + i * 8);
      if (count < 1 || times.length + count > AVATAR_FRAME_MAX_COUNT || delta * 1000 / scale < 16) { return null; }
      for (let j = 0; j < count; j++) {
        times.push(Math.round(ticks * 1000000 / scale));
        const endMs = Math.round((ticks + delta) * 1000 / scale);
        durations.push(endMs - Math.round(ticks * 1000 / scale));
        ticks += delta;
      }
    }
    const stsz = child(v, stbl, 'stsz');
    need(stsz, 20);
    if (times.length < 2 || v.getUint32(stsz.start + 16) !== times.length || ticks !== duration) { return null; }
    const bytes = size * size * 4 * times.length;
    return bytes <= AVATAR_FRAME_MAX_BYTES ? { size: size, timesUs: times, durationsMs: durations, bytes: bytes } : null;
  } catch (_) { return null; }
}
