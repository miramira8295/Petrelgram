import { TdObject } from '../tdkit/TdTypes';

// 音乐中心的曲目模型（2026-09-18，设计稿「Music Player」）。
//
// 一条 TDLib 的 messageAudio 就是一首歌。这里只做「消息 → 播放页要显示的东西」，
// 不读资源文案、不碰播放器，所以全部可单测。
//
// 【设计稿要的几项数据，TDLib 并不都给】
// - 格式：取 mime_type，取不到退回文件名后缀；
// - 码率：**没有这个字段**，只能用「文件大小 ÷ 时长」估算，所以是近似值；
// - 采样率：要另外用 AVMetadataExtractor 读**本地已下载**的文件（见 services/AudioMetadataProbe），
//   这里只负责把拿到的赫兹数排成文案；
// - 位深：AVMetadataExtractor 也不给，界面上就不显示这一项。

export interface MusicTrack {
  chatId: number;
  messageId: number;
  // 已经回退过：没有 title 就是文件名。
  title: string;
  // '' = 未知，由界面用资源文案兜底（纯函数不读 str）。
  artist: string;
  album: string;
  durationSec: number;
  fileId: number;
  fileSize: number;
  mimeType: string;
  fileName: string;
  // '' = 还没下载到本地。
  localPath: string;
  // 专辑封面缩略图的文件 id，0 = 这首歌没有内嵌封面。
  coverFileId: number;
}

export interface MusicCoverColors {
  from: string;
  to: string;
}

// 设计稿里每首歌一对渐变色。曲目多了不可能手配，按曲目键散列到这张表上。
const COVER_PALETTE: MusicCoverColors[] = [
  { from: '#7bd4ff', to: '#3a4ef0' },
  { from: '#ff9ac4', to: '#8a2be2' },
  { from: '#ffbe6a', to: '#e0453a' },
  { from: '#b7f7d8', to: '#1d8a6e' },
  { from: '#c7d2ff', to: '#4b5bd6' },
  { from: '#ffe27a', to: '#c96b1e' }
];

// 会话内消息 id 跨会话高度重合，键必须带会话（同 geometryTransition 那条教训）。
export function musicTrackKey(chatId: number, messageId: number): string {
  return `${chatId}_${messageId}`;
}

function fileOf(audio: TdObject | undefined): TdObject | undefined {
  return audio !== undefined ? (audio['audio'] as TdObject | undefined) : undefined;
}

export function musicTrackFromMessage(message: TdObject | null | undefined): MusicTrack | null {
  if (message === undefined || message === null) {
    return null;
  }
  const content = message['content'] as TdObject | undefined;
  if (content === undefined || (content['@type'] as string | undefined) !== 'messageAudio') {
    return null;
  }
  const audio = content['audio'] as TdObject | undefined;
  const file = fileOf(audio);
  if (audio === undefined || file === undefined) {
    return null;
  }
  const local = file['local'] as TdObject | undefined;
  const cover = audio['album_cover_thumbnail'] as TdObject | undefined;
  const coverFile = cover !== undefined ? (cover['file'] as TdObject | undefined) : undefined;
  const fileName: string = (audio['file_name'] as string | undefined) ?? '';
  const title: string = ((audio['title'] as string | undefined) ?? '').trim();
  // size 为 0 的是还没下载过的文件，TDLib 把预估值放在 expected_size。
  const size: number = ((file['size'] as number | undefined) ?? 0) ||
    ((file['expected_size'] as number | undefined) ?? 0);
  return {
    chatId: (message['chat_id'] as number | undefined) ?? 0,
    messageId: (message['id'] as number | undefined) ?? 0,
    title: title !== '' ? title : fileName,
    artist: ((audio['performer'] as string | undefined) ?? '').trim(),
    album: ((audio['album'] as string | undefined) ?? '').trim(),
    durationSec: (audio['duration'] as number | undefined) ?? 0,
    fileId: (file['id'] as number | undefined) ?? 0,
    fileSize: size,
    mimeType: (audio['mime_type'] as string | undefined) ?? '',
    fileName: fileName,
    localPath: local !== undefined ? ((local['path'] as string | undefined) ?? '') : '',
    coverFileId: coverFile !== undefined ? ((coverFile['id'] as number | undefined) ?? 0) : 0
  };
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

// m:ss，超过一小时补出小时段。负数与非数当 0。
export function musicDurationLabel(seconds: number): string {
  const total: number = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
  const hours: number = Math.floor(total / 3600);
  const minutes: number = Math.floor((total % 3600) / 60);
  const secs: number = total % 60;
  if (hours > 0) {
    return `${hours}:${pad2(minutes)}:${pad2(secs)}`;
  }
  return `${minutes}:${pad2(secs)}`;
}

// 1024 进制，与系统「文件大小」的口径一致；0 表示不知道，界面上空着。
export function musicSizeLabel(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '';
  }
  if (bytes < 1024) {
    return `${Math.round(bytes)} B`;
  }
  const kb: number = bytes / 1024;
  if (kb < 1024) {
    return `${Math.round(kb)} KB`;
  }
  const mb: number = kb / 1024;
  if (mb < 1024) {
    return `${(Math.round(mb * 10) / 10).toFixed(1)} MB`;
  }
  return `${(Math.round(mb / 1024 * 100) / 100).toFixed(2)} GB`;
}

// 估算：TDLib 没有码率字段。按 1000 进制算 kbps（音频码率的惯例）。
export function musicBitrateLabel(bytes: number, durationSec: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0 || !Number.isFinite(durationSec) || durationSec <= 0) {
    return '';
  }
  return `${Math.round(bytes * 8 / durationSec / 1000)} kbps`;
}

const MIME_FORMATS: Map<string, string> = new Map([
  ['audio/mpeg', 'MP3'], ['audio/mp3', 'MP3'],
  ['audio/flac', 'FLAC'], ['audio/x-flac', 'FLAC'],
  ['audio/mp4', 'AAC'], ['audio/aac', 'AAC'], ['audio/m4a', 'AAC'], ['audio/x-m4a', 'AAC'],
  ['audio/ogg', 'OGG'], ['audio/vorbis', 'OGG'],
  ['audio/wav', 'WAV'], ['audio/x-wav', 'WAV'], ['audio/wave', 'WAV'],
  ['audio/opus', 'OPUS'], ['audio/amr', 'AMR']
]);

export function musicFormatLabel(mimeType: string, fileName: string): string {
  const mime: string = mimeType.trim().toLowerCase();
  const mapped: string | undefined = MIME_FORMATS.get(mime);
  if (mapped !== undefined) {
    return mapped;
  }
  const dot: number = fileName.lastIndexOf('.');
  if (dot < 0 || dot === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).toUpperCase();
}

// AVMetadataExtractor 给的是赫兹。44100 → 44.1 kHz，96000 → 96 kHz。
export function musicSampleLabel(sampleRateHz: number): string {
  if (!Number.isFinite(sampleRateHz) || sampleRateHz <= 0) {
    return '';
  }
  const khz: number = sampleRateHz / 1000;
  const rounded: number = Math.round(khz * 10) / 10;
  return Number.isInteger(rounded) ? `${rounded} kHz` : `${rounded.toFixed(1)} kHz`;
}

// 同一首歌每次进来颜色要一样，所以散列曲目键而不是用随机数或下标。
export function musicCoverColors(trackKey: string): MusicCoverColors {
  let hash: number = 0;
  for (let i = 0; i < trackKey.length; i++) {
    hash = (hash * 31 + trackKey.charCodeAt(i)) % 100000;
  }
  return COVER_PALETTE[hash % COVER_PALETTE.length];
}

// 搜索浮层里的即时过滤（服务端搜索之外的本地一层）。标题、歌手、专辑都算。
export function filterMusicTracks(tracks: MusicTrack[], query: string): MusicTrack[] {
  const needle: string = query.trim().toLowerCase();
  if (needle === '') {
    return tracks.slice();
  }
  return tracks.filter((track: MusicTrack): boolean =>
    track.title.toLowerCase().includes(needle) ||
    track.artist.toLowerCase().includes(needle) ||
    track.album.toLowerCase().includes(needle));
}

// 曲库翻页时把新一页并进来：同一首歌（曲目键相同）只留一条，且**后来的那条更新**
// ——下载完成之后 localPath 才有值、size 才从预估变成真实。顺序保持先到先得，
// 新曲目追加在后面。不改入参。
export function mergeMusicTracks(existing: MusicTrack[], incoming: MusicTrack[]): MusicTrack[] {
  const fresh: Map<string, MusicTrack> = new Map<string, MusicTrack>();
  incoming.forEach((track: MusicTrack): void => {
    fresh.set(musicTrackKey(track.chatId, track.messageId), track);
  });
  const merged: MusicTrack[] = existing.map((track: MusicTrack): MusicTrack => {
    const key: string = musicTrackKey(track.chatId, track.messageId);
    const update: MusicTrack | undefined = fresh.get(key);
    if (update !== undefined) {
      fresh.delete(key);
      return update;
    }
    return track;
  });
  fresh.forEach((track: MusicTrack): void => { merged.push(track); });
  return merged;
}

export interface MusicTrackRef {
  chatId: number;
  messageId: number;
}

// musicTrackKey 的逆运算。合集里存的是键，要把歌重新取回来就得先拆出会话与消息 id
// （取数在 services/MusicTrackResolver）。**按最后一个下划线切**：会话 id 可能是负数
// （超级群是 -100…），但不含下划线，而分隔符只有一个，从后往前找最稳。
// 不成形的键返回 null，调用方跳过它而不是发一发空请求。
export function parseMusicTrackKey(key: string): MusicTrackRef | null {
  const cut: number = key.lastIndexOf('_');
  if (cut <= 0 || cut === key.length - 1) {
    return null;
  }
  const chatId: number = Number.parseInt(key.substring(0, cut), 10);
  const messageId: number = Number.parseInt(key.substring(cut + 1), 10);
  if (!Number.isFinite(chatId) || !Number.isFinite(messageId) || messageId <= 0) {
    return null;
  }
  return { chatId: chatId, messageId: messageId };
}
