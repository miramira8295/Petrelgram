// 「详细统计信息」面板的数据与格式化（2026-10-10，仿 YouTube 的 Stats for nerds）。纯函数，可单测。
//
// 数据两部分：ijk 的播放统计 JSON（自编 ijkplayer 的 getPlaybackStats，容器/视频/音频分开）
// 与实时属性（帧率、丢帧、缓冲），加上我们自己这边的来源、下载速度、档位。
// 标签照 YouTube 用英文技术名词：这些词本来就是行话，各语言用户都这么叫。

export interface StatsRow {
  label: string;
  value: string;
}

export interface VideoStatsSnapshot {
  statsJson: string;
  // ijk 的 FFP_PROPV_DECODER_*：1 = FFmpeg 软解，2 = 系统硬解，0 = 不知道。
  decoderKind: number;
  outputFps: number;
  decodeFps: number;
  dropFrameRate: number;      // 0..1
  videoCachedMs: number;
  audioCachedMs: number;
  videoCachedBytes: number;
  audioCachedBytes: number;
  speed: number;
  positionMs: number;
  durationMs: number;
  viewportWidth: number;      // vp
  viewportHeight: number;
  source: string;             // 'tdfile' | 'local' | 'http'
  fileId: number;
  fileSize: number;
  bufferedPercent: number;
  downloadBytesPerSec: number;
  network: string;
  quality: string;            // 档位说明，查看器填（'720p · h265' / 'Original'），'' = 不显示
}

interface StatsVideoJson {
  codec?: string;
  decoder?: string;
  profile?: string;
  level?: number;
  width?: number;
  height?: number;
  pix_fmt?: string;
  bit_depth?: number;
  fps?: number;
  bitrate?: number;
  color_primaries?: string;
  color_trc?: string;
  color_space?: string;
  color_range?: string;
}

interface StatsAudioJson {
  codec?: string;
  decoder?: string;
  profile?: string;
  sample_rate?: number;
  channels?: number;
  layout?: string;
  sample_fmt?: string;
  bitrate?: number;
}

interface StatsJson {
  format?: string;
  duration_ms?: number;
  bitrate?: number;
  video?: StatsVideoJson;
  audio?: StatsAudioJson;
}

export function emptyVideoStats(): VideoStatsSnapshot {
  return {
    statsJson: '', decoderKind: 0, outputFps: 0, decodeFps: 0, dropFrameRate: 0,
    videoCachedMs: 0, audioCachedMs: 0, videoCachedBytes: 0, audioCachedBytes: 0,
    speed: 1, positionMs: 0, durationMs: 0, viewportWidth: 0, viewportHeight: 0,
    source: '', fileId: 0, fileSize: 0, bufferedPercent: 0, downloadBytesPerSec: 0,
    network: '', quality: ''
  };
}

function fixed1(n: number): string {
  return (Math.round(n * 10) / 10).toFixed(1);
}

export function formatBitrate(bps: number): string {
  if (!(bps > 0)) {
    return '—';
  }
  if (bps >= 1_000_000) {
    return `${fixed1(bps / 1_000_000)} Mbps`;
  }
  return `${Math.round(bps / 1000)} kbps`;
}

export function formatBytes(bytes: number): string {
  if (!(bytes > 0)) {
    return '0 B';
  }
  if (bytes >= 1024 * 1024) {
    return `${fixed1(bytes / 1024 / 1024)} MB`;
  }
  if (bytes >= 1024) {
    return `${fixed1(bytes / 1024)} KB`;
  }
  return `${Math.round(bytes)} B`;
}

function formatDuration(ms: number): string {
  const total: number = Math.max(0, Math.floor(ms / 1000));
  const m: number = Math.floor(total / 60);
  const s: number = total % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

// 传输特性 -> HDR 种类。PQ（smpte2084）是 HDR10/HDR10+/杜比视界的基础层，HLG 是广电那套。
export function hdrLabel(colorTrc: string): string {
  if (colorTrc === 'smpte2084') {
    return 'HDR10 (PQ)';
  }
  if (colorTrc === 'arib-std-b67') {
    return 'HLG';
  }
  return 'SDR';
}

// FFmpeg 的 level 是码流里的原值：H.264 是 10×（41 = 4.1），HEVC 是 30×（150 = 5.0）。
function formatLevel(codec: string, level: number): string {
  if (!(level > 0)) {
    return '';
  }
  if (codec === 'hevc') {
    return `L${(level / 30).toFixed(1)}`;
  }
  if (codec === 'h264') {
    return `L${(level / 10).toFixed(1)}`;
  }
  return `L${level}`;
}

function parseStats(text: string): StatsJson | null {
  if (text === '') {
    return null;
  }
  try {
    return JSON.parse(text) as StatsJson;
  } catch (e) {
    return null;
  }
}

function videoCodecText(v: StatsVideoJson): string {
  const codec: string = v.codec ?? '';
  const extra: string[] = [];
  if ((v.profile ?? '') !== '') {
    extra.push(v.profile ?? '');
  }
  const level: string = formatLevel(codec, v.level ?? 0);
  if (level !== '') {
    extra.push(level);
  }
  return extra.length > 0 ? `${codec} (${extra.join(', ')})` : codec;
}

function audioCodecText(a: StatsAudioJson): string {
  const codec: string = a.codec ?? '';
  return (a.profile ?? '') !== '' ? `${codec} (${a.profile})` : codec;
}

function decoderKindText(kind: number): string {
  return kind === 2 ? 'Hardware' : (kind === 1 ? 'Software' : 'Unknown');
}

function sourceText(source: string): string {
  if (source === 'tdfile') {
    return 'TDLib stream (direct read)';
  }
  if (source === 'local') {
    return 'Local file';
  }
  if (source === 'http') {
    return 'TDLib stream (loopback HTTP)';
  }
  return source;
}

// 面板上的一行行。顺序照 YouTube：先「这是什么」，再「现在播得怎样」，最后「数据从哪来」。
export function videoStatsRows(s: VideoStatsSnapshot): StatsRow[] {
  const rows: StatsRow[] = [];
  const j: StatsJson | null = parseStats(s.statsJson);
  const v: StatsVideoJson | undefined = j !== null ? j.video : undefined;
  const a: StatsAudioJson | undefined = j !== null ? j.audio : undefined;
  const decoderName: string = v !== undefined ? (v.decoder ?? '') : '';
  rows.push({
    label: 'Decoder',
    value: decoderName !== '' ? `${decoderName} · ${decoderKindText(s.decoderKind)}` : decoderKindText(s.decoderKind)
  });
  if (v !== undefined || a !== undefined) {
    const parts: string[] = [];
    if (v !== undefined) {
      parts.push(videoCodecText(v));
    }
    if (a !== undefined) {
      parts.push(audioCodecText(a));
    }
    rows.push({ label: 'Codecs', value: parts.join(' / ') });
  }
  if (v !== undefined) {
    const fps: number = v.fps ?? 0;
    rows.push({
      label: 'Resolution',
      value: `${v.width ?? 0}x${v.height ?? 0}` + (fps > 0 ? ` @ ${Math.round(fps * 100) / 100} fps` : '')
    });
    rows.push({
      label: 'Pixel format',
      value: `${v.pix_fmt ?? ''}` + ((v.bit_depth ?? 0) > 0 ? ` · ${v.bit_depth}-bit` : '')
    });
    rows.push({
      label: 'Color',
      value: `${hdrLabel(v.color_trc ?? '')} · ${v.color_primaries ?? ''} / ${v.color_trc ?? ''} / ${v.color_range ?? ''}`
    });
  }
  if (s.viewportWidth > 0 && s.viewportHeight > 0) {
    rows.push({ label: 'Viewport', value: `${Math.round(s.viewportWidth)}x${Math.round(s.viewportHeight)} vp` });
  }
  rows.push({
    label: 'Frames',
    value: `output ${fixed1(s.outputFps)} / decode ${fixed1(s.decodeFps)} fps · dropped ${fixed1(s.dropFrameRate * 100)}%`
  });
  rows.push({ label: 'Speed', value: `${s.speed}x` });
  if (j !== null) {
    const videoRate: number = v !== undefined ? (v.bitrate ?? 0) : 0;
    rows.push({
      label: 'Bitrate',
      value: `container ${formatBitrate(j.bitrate ?? 0)} · video ${formatBitrate(videoRate)}`
    });
  }
  if (a !== undefined) {
    rows.push({
      label: 'Audio',
      value: `${Math.round((a.sample_rate ?? 0) / 1000)} kHz · ${a.layout ?? `${a.channels ?? 0}ch`} · ` +
        `${a.sample_fmt ?? ''} · ${formatBitrate(a.bitrate ?? 0)}`
    });
  }
  rows.push({
    label: 'Buffer',
    value: `video ${fixed1(s.videoCachedMs / 1000)} s (${formatBytes(s.videoCachedBytes)}) · ` +
      `audio ${fixed1(s.audioCachedMs / 1000)} s (${formatBytes(s.audioCachedBytes)})`
  });
  if (j !== null && (j.format ?? '') !== '') {
    rows.push({ label: 'Container', value: `${j.format} · ${formatDuration(j.duration_ms ?? s.durationMs)}` });
  }
  if (s.quality !== '') {
    rows.push({ label: 'Quality', value: s.quality });
  }
  rows.push({ label: 'Source', value: sourceText(s.source) });
  rows.push({
    label: 'Download',
    value: `${formatBytes(s.downloadBytesPerSec)}/s · buffered ${Math.round(s.bufferedPercent)}%`
  });
  rows.push({ label: 'File', value: `#${s.fileId} · ${formatBytes(s.fileSize)}` });
  if (s.network !== '') {
    rows.push({ label: 'Network', value: s.network });
  }
  return rows;
}
