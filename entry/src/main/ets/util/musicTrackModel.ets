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
  // 内联封面小图的 data URL（~40px、约 1KB，消息/内联结果里直接带着，**零网络**）。
  // '' = 这首没有。真封面 coverFileId 要走下载，先画这张能省掉整段等待。
  coverMini: string;
  // 机器人内联搜索来的结果 id；'' = 这首来自会话里的音频消息。
  // 机器人结果没有 chatId/messageId，身份只能靠它，键也另走 musicBotTrackKey。
  botResultId: string;
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

// 机器人搜索结果的键。**必须和会话消息的键分得开**：合集、收藏、音源探测缓存
// 全按这个键存，撞了就会把别的歌的采样率显示到这首上。
// 前缀是非数字，parseMusicTrackKey 那边 parseInt 出 NaN 自然会拒掉（有单测钉住）。
export const MUSIC_BOT_KEY_PREFIX: string = 'bot_';

export function musicBotTrackKey(resultId: string): string {
  return `${MUSIC_BOT_KEY_PREFIX}${resultId}`;
}

export function isMusicBotKey(key: string): boolean {
  return key.startsWith(MUSIC_BOT_KEY_PREFIX);
}

// 这首歌的键：机器人结果走 bot_ 前缀，会话消息走 chatId_messageId。
export function trackKeyOf(track: MusicTrack): string {
  return track.botResultId !== ''
    ? musicBotTrackKey(track.botResultId) : musicTrackKey(track.chatId, track.messageId);
}

// 专辑封面的内联小图 → data URL。messageAudio 与 inlineQueryResultAudio 里的
// audio 对象是同一个形状，两边共用。
export function audioCoverMiniUrl(audio: TdObject | undefined): string {
  if (audio === undefined) {
    return '';
  }
  const mini = audio['album_cover_minithumbnail'] as TdObject | undefined;
  const data: string = mini !== undefined ? ((mini['data'] as string | undefined) ?? '') : '';
  return data !== '' ? `data:image/jpeg;base64,${data}` : '';
}

function fileOf(audio: TdObject | undefined): TdObject | undefined {
  return audio !== undefined ? (audio['audio'] as TdObject | undefined) : undefined;
}

// 本地路径**只在整首下完之后才算数**。
//
// TDLib 对只下了前缀的文件一样会给 local.path——音源探测为了解文件头会
// downloadFile(offset 0, limit 64KB)，于是本地凭空多出一个几百 KB 的残片。
// 拿它当"本地已有"去起播，AVPlayer 走 fd 分支直接读残片，ffmpeg 报
// 「partial file / Call av_read_frame failed」，表现是点了没声音
// （2026-09-20 真机日志钉死）。
//
// 判据用 is_downloading_completed，不是 path 非空，也不是
// downloaded_size == size（后者在 size 未知时是 0==0）。
function completedLocalPath(file: TdObject | undefined): string {
  const local = file !== undefined ? (file['local'] as TdObject | undefined) : undefined;
  if (local === undefined) {
    return '';
  }
  const done: boolean = (local['is_downloading_completed'] as boolean | undefined) ?? false;
  return done ? ((local['path'] as string | undefined) ?? '') : '';
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
    localPath: completedLocalPath(file),
    coverFileId: coverFile !== undefined ? ((coverFile['id'] as number | undefined) ?? 0) : 0,
    coverMini: audioCoverMiniUrl(audio),
    botResultId: ''
  };
}

// 机器人内联搜索结果 → 曲目。
//
// inlineQueryResultAudio 里那个 audio 对象和 messageAudio 里的**完全同构**
// （2026-09-20 对 @LyBot 真机实测确认：duration/title/performer/file_name/
// mime_type/album_cover_minithumbnail/album_cover_thumbnail/audio:file 全有），
// 所以取字段的写法和上面那段一致，只是身份换成 result.id。
//
// 关键的一条：这个 file 不发消息就能 downloadFile（同一次实测，三首全过）——
// 这正是这条路走得通的前提，也是 @Music163bot 那种只回 Article 的 bot 走不通的原因。
export function musicTrackFromInlineAudio(result: TdObject | null | undefined): MusicTrack | null {
  if (result === undefined || result === null) {
    return null;
  }
  if ((result['@type'] as string | undefined) !== 'inlineQueryResultAudio') {
    return null;
  }
  const resultId: string = (result['id'] as string | undefined) ?? '';
  const audio = result['audio'] as TdObject | undefined;
  const file = fileOf(audio);
  if (resultId === '' || audio === undefined || file === undefined) {
    return null;
  }
  const cover = audio['album_cover_thumbnail'] as TdObject | undefined;
  const coverFile = cover !== undefined ? (cover['file'] as TdObject | undefined) : undefined;
  const fileName: string = (audio['file_name'] as string | undefined) ?? '';
  const title: string = ((audio['title'] as string | undefined) ?? '').trim();
  const size: number = ((file['size'] as number | undefined) ?? 0) ||
    ((file['expected_size'] as number | undefined) ?? 0);
  return {
    chatId: 0,
    messageId: 0,
    title: title !== '' ? title : fileName,
    artist: ((audio['performer'] as string | undefined) ?? '').trim(),
    album: ((audio['album'] as string | undefined) ?? '').trim(),
    durationSec: (audio['duration'] as number | undefined) ?? 0,
    fileId: (file['id'] as number | undefined) ?? 0,
    fileSize: size,
    mimeType: (audio['mime_type'] as string | undefined) ?? '',
    fileName: fileName,
    localPath: completedLocalPath(file),
    coverFileId: coverFile !== undefined ? ((coverFile['id'] as number | undefined) ?? 0) : 0,
    coverMini: audioCoverMiniUrl(audio),
    botResultId: resultId
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
