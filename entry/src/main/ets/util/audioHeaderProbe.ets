// 音源信息（格式/采样率/位深/声道/码率）的文件头解析。2026-09-18，音乐中心。
//
// 【为什么自己解】这三项数据没有一个现成来源能全给：
//   · TDLib 只有 mime_type、时长、大小；
//   · 系统的 AVMetadataExtractor 只给采样率，没有码率、没有位深；
//   · 随包的 ijkplayer 里那份 FFmpeg 能给码率与采样率，**位深仍然没有**，而且它的符号
//     没从 .so 导出（nm -D 查过），没法自己调 avformat。
// 而这几种格式的头部本来就明写着这些数。自己解还多两个好处：只需要文件**开头**几十 KB
// （配合 TDLib 的分段下载，云端歌曲不用整首下完），以及纯函数可单测。
// 认不出来的格式退回 ijk 探测（services/AudioMetadataProbe），那条路要整首在本地。
//
// 【形状】每种格式一个 parseXxx(reader) → AudioSourceInfo | null，probeAudioHeader 依次试，
// 第一个认领的说了算。任何越界都由 Reader 兜成 -1/false，解析函数据此返回 null——
// 头部被截断（分段下载只到一半）时必须是"不知道"，不能抛。

// 取文件开头这么多字节就够认出上面几种格式。64 KB 能容下 ID3v2 封面图之后的第一帧，
// 也能容下 m4a 前置的 moov。
export const AUDIO_HEADER_PREFIX_BYTES: number = 64 * 1024;

export interface AudioSourceInfo {
  // 'FLAC' | 'WAV' | 'MP3' | 'AAC' | 'OGG' | 'OPUS'，'' = 没认出来
  format: string;
  // 0 = 未知。
  sampleRateHz: number;
  // 0 = 未知，或有损格式本来就没有位深。
  bitDepth: number;
  channels: number;
  // 0 = 头部给不出（无损格式要靠文件大小 ÷ 时长算）。
  bitrateKbps: number;
  // 0 = 未知。只有 FLAC 的头里直接写了总样本数。
  durationSec: number;
}

export function audioSourceKnown(info: AudioSourceInfo): boolean {
  return info.sampleRateHz > 0 || info.bitrateKbps > 0;
}

function unknownSource(): AudioSourceInfo {
  return { format: '', sampleRateHz: 0, bitDepth: 0, channels: 0, bitrateKbps: 0, durationSec: 0 };
}

// 只读游标。**越界一律返回 -1 / false**，不抛——调用方看到 -1 自己放弃。
class Reader {
  private readonly data: Uint8Array;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  get length(): number {
    return this.data.length;
  }

  u8(at: number): number {
    return at >= 0 && at < this.data.length ? this.data[at] : -1;
  }

  u16be(at: number): number {
    const a: number = this.u8(at);
    const b: number = this.u8(at + 1);
    return a < 0 || b < 0 ? -1 : (a << 8) | b;
  }

  u16le(at: number): number {
    const a: number = this.u8(at);
    const b: number = this.u8(at + 1);
    return a < 0 || b < 0 ? -1 : (b << 8) | a;
  }

  u32be(at: number): number {
    const a: number = this.u16be(at);
    const b: number = this.u16be(at + 2);
    return a < 0 || b < 0 ? -1 : a * 0x10000 + b;
  }

  u32le(at: number): number {
    const a: number = this.u16le(at);
    const b: number = this.u16le(at + 2);
    return a < 0 || b < 0 ? -1 : b * 0x10000 + a;
  }

  // 从 at 起是不是这几个 ASCII 字符。
  matches(at: number, ascii: string): boolean {
    for (let i = 0; i < ascii.length; i++) {
      if (this.u8(at + i) !== ascii.charCodeAt(i)) {
        return false;
      }
    }
    return true;
  }

  // 找标记的起始下标；找不到返回 -1。limit 限制扫描范围，别为一个找不到的标记扫满 64 KB。
  find(ascii: string, from: number, limit: number): number {
    const end: number = Math.min(this.data.length, from + limit);
    for (let i = Math.max(0, from); i < end; i++) {
      if (this.matches(i, ascii)) {
        return i;
      }
    }
    return -1;
  }
}

// ---- FLAC ------------------------------------------------------------------
//
// 'fLaC' + 元数据块头(4) + STREAMINFO：最小/最大块大小(2+2)、最小/最大帧大小(3+3)，
// 然后 8 个字节打包着采样率 20 位、声道-1 3 位、位深-1 5 位、总样本数 36 位。
function parseFlac(r: Reader): AudioSourceInfo | null {
  if (!r.matches(0, 'fLaC')) {
    return null;
  }
  const at: number = 18;
  const b0: number = r.u8(at);
  const b1: number = r.u8(at + 1);
  const b2: number = r.u8(at + 2);
  const b3: number = r.u8(at + 3);
  const tail: number = r.u32be(at + 4);
  if (b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0 || tail < 0) {
    return null;
  }
  const sampleRate: number = (b0 << 12) | (b1 << 4) | (b2 >> 4);
  const channels: number = ((b2 >> 1) & 0x07) + 1;
  const bitDepth: number = ((((b2 & 0x01) << 4) | (b3 >> 4)) & 0x1f) + 1;
  const totalSamples: number = (b3 & 0x0f) * 0x100000000 + tail;
  if (sampleRate <= 0) {
    return null;
  }
  return {
    format: 'FLAC', sampleRateHz: sampleRate, bitDepth: bitDepth, channels: channels,
    // 无损格式的码率随内容浮动，头里没有，交给调用方用文件大小算。
    bitrateKbps: 0,
    durationSec: totalSamples > 0 ? Math.round(totalSamples / sampleRate) : 0
  };
}

// ---- WAV -------------------------------------------------------------------
//
// 'RIFF' + 大小 + 'WAVE'，随后是若干块；'fmt ' 块里有声道、采样率、字节率、位深。
function parseWav(r: Reader): AudioSourceInfo | null {
  if (!r.matches(0, 'RIFF') || !r.matches(8, 'WAVE')) {
    return null;
  }
  const fmt: number = r.find('fmt ', 12, 4096);
  if (fmt < 0) {
    return null;
  }
  const body: number = fmt + 8;
  const channels: number = r.u16le(body + 2);
  const sampleRate: number = r.u32le(body + 4);
  const byteRate: number = r.u32le(body + 8);
  const bitDepth: number = r.u16le(body + 14);
  if (channels < 0 || sampleRate <= 0 || byteRate < 0 || bitDepth < 0) {
    return null;
  }
  return {
    format: 'WAV', sampleRateHz: sampleRate, bitDepth: bitDepth, channels: channels,
    bitrateKbps: byteRate > 0 ? Math.round(byteRate * 8 / 1000) : 0,
    durationSec: 0
  };
}

// ---- Ogg（Opus / Vorbis）----------------------------------------------------
//
// 页头之后才是编解码器的标识头，位置不固定，所以在前几 KB 里找标记。
function parseOgg(r: Reader): AudioSourceInfo | null {
  if (!r.matches(0, 'OggS')) {
    return null;
  }
  const opus: number = r.find('OpusHead', 0, 4096);
  if (opus >= 0) {
    const channels: number = r.u8(opus + 9);
    const inputRate: number = r.u32le(opus + 12);
    if (channels < 0) {
      return null;
    }
    return {
      format: 'OPUS',
      // Opus 一律解码到 48 kHz，头里那个是原始输入采样率，取不到就按 48k 说。
      sampleRateHz: inputRate > 0 ? inputRate : 48000,
      bitDepth: 0, channels: channels, bitrateKbps: 0, durationSec: 0
    };
  }
  const vorbis: number = r.find('vorbis', 0, 4096);
  if (vorbis < 0 || r.u8(vorbis - 1) !== 0x01) {
    return null;
  }
  const body: number = vorbis + 6;
  const channels: number = r.u8(body + 4);
  const sampleRate: number = r.u32le(body + 5);
  const nominal: number = r.u32le(body + 13);
  if (channels < 0 || sampleRate <= 0) {
    return null;
  }
  return {
    format: 'OGG', sampleRateHz: sampleRate, bitDepth: 0, channels: channels,
    bitrateKbps: nominal > 0 ? Math.round(nominal / 1000) : 0,
    durationSec: 0
  };
}

// ---- MP4 / M4A（AAC、ALAC）---------------------------------------------------
//
// 采样率与声道写在 stsd 的 'mp4a' 表项里：表项头 8 字节 + 保留 8 字节之后是
// 声道(2)、样本大小(2)、pre_defined(2)、保留(2)、采样率(4，16.16 定点)。
// moov 在文件尾部的（边下边播优化过的）文件在头部找不到它，那就交给 ijk 兜底。
function parseMp4(r: Reader): AudioSourceInfo | null {
  if (!r.matches(4, 'ftyp')) {
    return null;
  }
  const entry: number = r.find('mp4a', 8, AUDIO_HEADER_PREFIX_BYTES);
  if (entry < 0) {
    return null;
  }
  const channels: number = r.u16be(entry + 20);
  const sampleSize: number = r.u16be(entry + 22);
  const fixedRate: number = r.u32be(entry + 28);
  if (channels < 0 || fixedRate < 0) {
    return null;
  }
  const sampleRate: number = Math.round(fixedRate / 65536);
  if (sampleRate <= 0) {
    return null;
  }
  return {
    format: 'AAC', sampleRateHz: sampleRate,
    // 有损 AAC 的"样本大小"恒是 16，没有实际意义，不当位深显示。
    bitDepth: 0,
    channels: channels, bitrateKbps: 0, durationSec: 0
  };
}

// ---- MP3 --------------------------------------------------------------------

// Layer III 的码率表（kbps）。MPEG1 与 MPEG2/2.5 各一张，下标就是帧头里的 4 位。
const MP3_BITRATES_V1: number[] = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0];
const MP3_BITRATES_V2: number[] = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0];
const MP3_RATES_V1: number[] = [44100, 48000, 32000, 0];
const MP3_RATES_V2: number[] = [22050, 24000, 16000, 0];
const MP3_RATES_V25: number[] = [11025, 12000, 8000, 0];

function parseMp3(r: Reader): AudioSourceInfo | null {
  let at: number = 0;
  if (r.matches(0, 'ID3')) {
    // ID3v2 的长度是 4 个 7 位组（最高位留给同步保护）。封面图常常几百 KB，
    // 所以标签之后的第一帧未必落在我们取的这段里——那时按认不出处理。
    const size: number = (r.u8(6) & 0x7f) * 0x200000 + (r.u8(7) & 0x7f) * 0x4000 +
      (r.u8(8) & 0x7f) * 0x80 + (r.u8(9) & 0x7f);
    if (size < 0) {
      return null;
    }
    at = 10 + size;
  }
  // 帧头以 11 位同步字开始。标签长度写得不准时往后找一小段。
  let sync: number = -1;
  const limit: number = Math.min(r.length, at + 8192);
  for (let i = at; i + 3 < limit; i++) {
    if (r.u8(i) === 0xff && (r.u8(i + 1) & 0xe0) === 0xe0) {
      sync = i;
      break;
    }
  }
  if (sync < 0) {
    return null;
  }
  const b1: number = r.u8(sync + 1);
  const b2: number = r.u8(sync + 2);
  const b3: number = r.u8(sync + 3);
  if (b1 < 0 || b2 < 0 || b3 < 0) {
    return null;
  }
  const versionBits: number = (b1 >> 3) & 0x03;
  const layerBits: number = (b1 >> 1) & 0x03;
  if (versionBits === 0x01) {
    return null;  // 保留值，不是合法帧头
  }
  const rates: number[] = versionBits === 0x03 ? MP3_RATES_V1
    : (versionBits === 0x02 ? MP3_RATES_V2 : MP3_RATES_V25);
  const sampleRate: number = rates[(b2 >> 2) & 0x03];
  if (sampleRate <= 0) {
    return null;
  }
  // Layer III 以外（I/II）在音乐里极少见，码率表不带了：采样率与声道仍然给得出。
  const isLayer3: boolean = layerBits === 0x01;
  const table: number[] = versionBits === 0x03 ? MP3_BITRATES_V1 : MP3_BITRATES_V2;
  const bitrate: number = isLayer3 ? table[(b2 >> 4) & 0x0f] : 0;
  const channels: number = ((b3 >> 6) & 0x03) === 0x03 ? 1 : 2;
  return {
    format: 'MP3', sampleRateHz: sampleRate, bitDepth: 0, channels: channels,
    bitrateKbps: bitrate, durationSec: 0
  };
}

// 依次试，谁认出来算谁的。顺序按标记的独特程度排：前四种都有确定的魔数，MP3 最宽松，放最后。
export function probeAudioHeader(bytes: Uint8Array): AudioSourceInfo {
  const r: Reader = new Reader(bytes);
  const info: AudioSourceInfo | null = parseFlac(r) ?? parseWav(r) ?? parseOgg(r)
    ?? parseMp4(r) ?? parseMp3(r);
  return info ?? unknownSource();
}
