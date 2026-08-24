import { EBML_UNKNOWN_SIZE, readElementId, readFloat, readInt, readUint, readVarSize } from './EbmlReader';

// Telegram 的视频贴纸是 VP9 + alpha。alpha 不是编码器扩展，而是**容器层技巧**：
// 一路独立的普通 VP9 灰度流，塞在 WebM 的 BlockAdditional（BlockAddID=1）里，
// 它的 luma 就是 alpha。TrackEntry/Video 下的 AlphaMode=1 是这件事的声明。
//
// 系统解封装不认 WebM/VP9，ijkplayer 里的 ffmpeg 原生 VP9 解码器又只在
// libvpxdec 里实现了 alpha 拼装——两边都拿不到这一路，所以只能自己拆。
// 这里只做拆包：拆出来的两路码流各自交给系统 VP9 解码器。

const ID_SEGMENT: number = 0x18538067;
const ID_INFO: number = 0x1549A966;
const ID_TIMESTAMP_SCALE: number = 0x2AD7B1;
const ID_DURATION: number = 0x4489;
const ID_TRACKS: number = 0x1654AE6B;
const ID_TRACK_ENTRY: number = 0xAE;
const ID_TRACK_NUMBER: number = 0xD7;
const ID_TRACK_TYPE: number = 0x83;
const ID_CODEC_ID: number = 0x86;
const ID_VIDEO: number = 0xE0;
const ID_PIXEL_WIDTH: number = 0xB0;
const ID_PIXEL_HEIGHT: number = 0xBA;
const ID_ALPHA_MODE: number = 0x53C0;
const ID_CLUSTER: number = 0x1F43B675;
const ID_CLUSTER_TIMESTAMP: number = 0xE7;
const ID_SIMPLE_BLOCK: number = 0xA3;
const ID_BLOCK_GROUP: number = 0xA0;
const ID_BLOCK: number = 0xA1;
const ID_BLOCK_ADDITIONS: number = 0x75A1;
const ID_BLOCK_MORE: number = 0xA6;
const ID_BLOCK_ADD_ID: number = 0xEE;
const ID_BLOCK_ADDITIONAL: number = 0xA5;

const TRACK_TYPE_VIDEO: number = 1;
const DEFAULT_TIMESTAMP_SCALE: number = 1000000; // 纳秒，即刻度本身就是毫秒
const NS_PER_MS: number = 1000000;
// BlockAddID 缺省即 1；Telegram 的 alpha 就用这个号。
const BLOCK_ADD_ID_ALPHA: number = 1;

export interface WebmAlphaTrack {
  trackNumber: number;
  width: number;
  height: number;
  hasAlpha: boolean;
  isVp9: boolean;
}

export interface WebmAlphaFrame {
  timeMs: number;
  color: Uint8Array;
  alpha: Uint8Array | null;
}

export interface WebmAlphaClip {
  track: WebmAlphaTrack;
  frames: WebmAlphaFrame[];
  durationMs: number;
}

// 一个已定位的子元素。
interface EbmlChild {
  id: number;
  start: number;   // 负载首字节
  end: number;     // 负载末字节的下一个位置
  next: number;    // 下一个兄弟元素的位置
}

// 逐个读出 [from, to) 里的子元素。任何一步读坏就返回 null，调用方一律回退。
function children(data: Uint8Array, from: number, to: number): EbmlChild[] | null {
  const out: EbmlChild[] = [];
  let pos = from;
  while (pos < to) {
    const id = readElementId(data, pos);
    if (!id.ok) {
      return null;
    }
    const size = readVarSize(data, pos + id.length);
    if (!size.ok) {
      return null;
    }
    const start = pos + id.length + size.length;
    // 长度未知只在 Segment 上容忍（见 demux）；这里当成"吃到父元素结尾"，
    // 由调用方决定要不要接受。
    const end = size.value === EBML_UNKNOWN_SIZE ? to : Math.min(to, start + size.value);
    if (start > to || end < start) {
      return null;
    }
    out.push({ id: id.value, start: start, end: end, next: end });
    if (size.value === EBML_UNKNOWN_SIZE) {
      break;
    }
    pos = end;
  }
  return out;
}

function findChild(list: EbmlChild[], id: number): EbmlChild | null {
  for (const c of list) {
    if (c.id === id) {
      return c;
    }
  }
  return null;
}

// EBML 头之后的 Segment。文件必须以 EBML 头（0x1A45DFA3）开始，否则不是 WebM。
function findSegment(data: Uint8Array): EbmlChild | null {
  const top = children(data, 0, data.length);
  if (top === null) {
    return null;
  }
  return findChild(top, ID_SEGMENT);
}

function parseVideoTrack(data: Uint8Array, entry: EbmlChild): WebmAlphaTrack | null {
  const fields = children(data, entry.start, entry.end);
  if (fields === null) {
    return null;
  }
  let trackType = 0;
  let trackNumber = 0;
  let codecId = '';
  let width = 0;
  let height = 0;
  let hasAlpha = false;
  for (const f of fields) {
    const len = f.end - f.start;
    if (f.id === ID_TRACK_TYPE) {
      trackType = readUint(data, f.start, len);
    } else if (f.id === ID_TRACK_NUMBER) {
      trackNumber = readUint(data, f.start, len);
    } else if (f.id === ID_CODEC_ID) {
      let s = '';
      for (let i = 0; i < len; i++) {
        const b = data[f.start + i];
        if (b !== 0) {
          s += String.fromCharCode(b);
        }
      }
      codecId = s;
    } else if (f.id === ID_VIDEO) {
      const vf = children(data, f.start, f.end);
      if (vf === null) {
        return null;
      }
      for (const v of vf) {
        const vlen = v.end - v.start;
        if (v.id === ID_PIXEL_WIDTH) {
          width = readUint(data, v.start, vlen);
        } else if (v.id === ID_PIXEL_HEIGHT) {
          height = readUint(data, v.start, vlen);
        } else if (v.id === ID_ALPHA_MODE) {
          hasAlpha = readUint(data, v.start, vlen) === 1;
        }
      }
    }
  }
  if (trackType !== TRACK_TYPE_VIDEO || trackNumber <= 0 || width <= 0 || height <= 0) {
    return null;
  }
  return {
    trackNumber: trackNumber, width: width, height: height,
    hasAlpha: hasAlpha, isVp9: codecId === 'V_VP9'
  };
}

// 只读头部：拿 AlphaMode / 尺寸 / 编码，不碰 Cluster。用于"这张贴纸值不值得
// 走新链路"的快速判定——不带 alpha 的一律原路返回 ijkplayer。
export function readWebmTrack(data: Uint8Array): WebmAlphaTrack | null {
  const segment = findSegment(data);
  if (segment === null) {
    return null;
  }
  const top = children(data, segment.start, segment.end);
  if (top === null) {
    return null;
  }
  const tracks = findChild(top, ID_TRACKS);
  if (tracks === null) {
    return null;
  }
  const entries = children(data, tracks.start, tracks.end);
  if (entries === null) {
    return null;
  }
  for (const e of entries) {
    if (e.id !== ID_TRACK_ENTRY) {
      continue;
    }
    const t = parseVideoTrack(data, e);
    if (t !== null) {
      return t;
    }
  }
  return null;
}

interface BlockHeader {
  trackNumber: number;
  relTime: number;
  frameStart: number;
}

// SimpleBlock / Block 的公共头：轨道号(vint) + 2 字节有符号相对时间 + 标志位。
// lacing（一个 Block 打包多帧）会让帧边界变成另一套编码，贴纸从来不用它——
// 真碰上就返回 null 让整条链路回退，而不是猜。
function parseBlockHeader(data: Uint8Array, start: number, end: number): BlockHeader | null {
  const track = readVarSize(data, start);
  if (!track.ok || track.value === EBML_UNKNOWN_SIZE) {
    return null;
  }
  const headerEnd = start + track.length + 3;
  if (headerEnd > end) {
    return null;
  }
  const flags = data[start + track.length + 2];
  if (((flags >> 1) & 0x03) !== 0) {
    return null;
  }
  return {
    trackNumber: track.value,
    relTime: readInt(data, start + track.length, 2),
    frameStart: headerEnd
  };
}

// BlockGroup 下找 BlockAddID=1 的 BlockAdditional，也就是 alpha 那一路。
function findAlphaAddition(data: Uint8Array, group: EbmlChild[]): Uint8Array | null {
  const additions = findChild(group, ID_BLOCK_ADDITIONS);
  if (additions === null) {
    return null;
  }
  const mores = children(data, additions.start, additions.end);
  if (mores === null) {
    return null;
  }
  for (const m of mores) {
    if (m.id !== ID_BLOCK_MORE) {
      continue;
    }
    const fields = children(data, m.start, m.end);
    if (fields === null) {
      continue;
    }
    const idEl = findChild(fields, ID_BLOCK_ADD_ID);
    const addId = idEl === null ? BLOCK_ADD_ID_ALPHA : readUint(data, idEl.start, idEl.end - idEl.start);
    const payload = findChild(fields, ID_BLOCK_ADDITIONAL);
    if (addId === BLOCK_ADD_ID_ALPHA && payload !== null && payload.end > payload.start) {
      return data.subarray(payload.start, payload.end);
    }
  }
  return null;
}

function collectCluster(data: Uint8Array, cluster: EbmlChild, track: number,
  scaleNs: number, out: WebmAlphaFrame[]): boolean {
  const items = children(data, cluster.start, cluster.end);
  if (items === null) {
    return false;
  }
  let clusterTime = 0;
  for (const item of items) {
    if (item.id === ID_CLUSTER_TIMESTAMP) {
      clusterTime = readUint(data, item.start, item.end - item.start);
      continue;
    }
    let blockStart = 0;
    let blockEnd = 0;
    let alpha: Uint8Array | null = null;
    if (item.id === ID_SIMPLE_BLOCK) {
      blockStart = item.start;
      blockEnd = item.end;
    } else if (item.id === ID_BLOCK_GROUP) {
      const group = children(data, item.start, item.end);
      if (group === null) {
        return false;
      }
      const block = findChild(group, ID_BLOCK);
      if (block === null) {
        continue;
      }
      blockStart = block.start;
      blockEnd = block.end;
      alpha = findAlphaAddition(data, group);
    } else {
      continue;
    }
    const header = parseBlockHeader(data, blockStart, blockEnd);
    if (header === null) {
      return false;
    }
    if (header.trackNumber !== track || header.frameStart >= blockEnd) {
      continue;
    }
    out.push({
      timeMs: (clusterTime + header.relTime) * scaleNs / NS_PER_MS,
      color: data.subarray(header.frameStart, blockEnd),
      alpha: alpha
    });
  }
  return true;
}

// 拆出色彩流 + alpha 流。返回 null = 这个文件走不了新链路，调用方回退。
// 注意帧里的 Uint8Array 是原 buffer 的视图，没有复制——WebM 贴纸只有几十 KB，
// 真正吃内存的是解码后的 RGBA，不是这里。
export function demuxWebmAlpha(data: Uint8Array): WebmAlphaClip | null {
  const segment = findSegment(data);
  if (segment === null) {
    return null;
  }
  const top = children(data, segment.start, segment.end);
  if (top === null) {
    return null;
  }
  const tracksEl = findChild(top, ID_TRACKS);
  if (tracksEl === null) {
    return null;
  }
  const entries = children(data, tracksEl.start, tracksEl.end);
  if (entries === null) {
    return null;
  }
  let track: WebmAlphaTrack | null = null;
  for (const e of entries) {
    if (e.id === ID_TRACK_ENTRY) {
      const t = parseVideoTrack(data, e);
      if (t !== null) {
        track = t;
        break;
      }
    }
  }
  if (track === null || !track.hasAlpha || !track.isVp9) {
    return null;
  }
  let scaleNs = DEFAULT_TIMESTAMP_SCALE;
  let durationTicks = 0;
  const info = findChild(top, ID_INFO);
  if (info !== null) {
    const fields = children(data, info.start, info.end);
    if (fields === null) {
      return null;
    }
    for (const f of fields) {
      if (f.id === ID_TIMESTAMP_SCALE) {
        const v = readUint(data, f.start, f.end - f.start);
        if (v > 0) {
          scaleNs = v;
        }
      } else if (f.id === ID_DURATION) {
        durationTicks = readFloat(data, f.start, f.end - f.start);
      }
    }
  }
  const frames: WebmAlphaFrame[] = [];
  for (const c of top) {
    if (c.id === ID_CLUSTER && !collectCluster(data, c, track.trackNumber, scaleNs, frames)) {
      return null;
    }
  }
  if (frames.length === 0) {
    return null;
  }
  // 每一帧都必须带 alpha：缺一帧就意味着那一帧要用不透明兜底，画面会闪。
  for (const f of frames) {
    if (f.alpha === null) {
      return null;
    }
  }
  const lastTime = frames[frames.length - 1].timeMs;
  const durationMs = durationTicks > 0 ? durationTicks * scaleNs / NS_PER_MS : lastTime;
  return { track: track, frames: frames, durationMs: Math.max(durationMs, lastTime) };
}

// 交给原生的载荷：两路码流各拼成一整块字节 + 一张 int32 长度表。
// 拼而不是传数组，是为了只跨一次 NAPI —— 90 帧两路就是 180 次对象转换。
export interface AlphaStreamPayload {
  colorData: ArrayBuffer;
  colorLengths: ArrayBuffer;
  alphaData: ArrayBuffer;
  alphaLengths: ArrayBuffer;
  // 只含**保留下来**的那些帧的时间戳，和原生返回的帧一一对应。
  keptTimesMs: number[];
}

function packStream(packets: Uint8Array[]): ArrayBuffer[] {
  let total = 0;
  for (const p of packets) {
    total += p.length;
  }
  const data = new Uint8Array(total);
  const lengths = new Int32Array(packets.length);
  let offset = 0;
  for (let i = 0; i < packets.length; i++) {
    data.set(packets[i], offset);
    lengths[i] = packets[i].length;
    offset += packets[i].length;
  }
  return [data.buffer as ArrayBuffer, lengths.buffer as ArrayBuffer];
}

// frameStep 只决定**留下**哪几帧：VP9 是帧间预测的，包一个都不能少喂，
// 少喂一个后面全花。所以两路码流照样整段打包，抽帧发生在解码之后。
export function packAlphaStreams(frames: WebmAlphaFrame[], frameStep: number): AlphaStreamPayload | null {
  if (frames.length === 0 || frameStep < 1) {
    return null;
  }
  const color: Uint8Array[] = [];
  const alpha: Uint8Array[] = [];
  const keptTimesMs: number[] = [];
  for (let i = 0; i < frames.length; i++) {
    const f = frames[i];
    if (f.alpha === null || f.color.length === 0 || f.alpha.length === 0) {
      return null;
    }
    color.push(f.color);
    alpha.push(f.alpha);
    if (i % frameStep === 0) {
      keptTimesMs.push(f.timeMs);
    }
  }
  const packedColor = packStream(color);
  const packedAlpha = packStream(alpha);
  return {
    colorData: packedColor[0], colorLengths: packedColor[1],
    alphaData: packedAlpha[0], alphaLengths: packedAlpha[1],
    keptTimesMs: keptTimesMs
  };
}
