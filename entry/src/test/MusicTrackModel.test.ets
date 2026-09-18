import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  filterMusicTracks, mergeMusicTracks, MusicCoverColors, musicBitrateLabel, musicCoverColors,
  musicDurationLabel, musicFormatLabel, musicSampleLabel, musicSizeLabel, MusicTrack,
  musicTrackFromMessage, musicTrackKey, MusicTrackRef, parseMusicTrackKey
} from '../main/ets/util/musicTrackModel';

// 音乐中心的曲目模型（2026-09-18，设计稿「Music Player」）。
//
// 这一层只做「TDLib 的一条 messageAudio → 播放页要显示的东西」，不读资源、不碰播放器，
// 所以能单测。设计稿里的格式/码率/采样这些字段，TDLib 并不直接给：
// - 格式取 mime_type，取不到退回文件名后缀；
// - 码率只能用「文件大小 ÷ 时长」估算（TDLib 没有这个字段）；
// - 采样率要另外用 AVMetadataExtractor 读本地文件，这里只负责把拿到的数字排成文案。

function audioMessage(chatId: number, messageId: number, patch: Record<string, Object>): TdObject {
  const file: TdObject = { '@type': 'file' };
  file['id'] = (patch['fileId'] as number | undefined) ?? 501;
  file['size'] = (patch['size'] as number | undefined) ?? 7_900_000;
  const local: TdObject = { '@type': 'localFile' };
  local['path'] = (patch['path'] as string | undefined) ?? '';
  local['is_downloading_completed'] = (patch['path'] as string | undefined) !== undefined;
  file['local'] = local;
  const audio: TdObject = { '@type': 'audio' };
  audio['duration'] = (patch['duration'] as number | undefined) ?? 198;
  audio['title'] = (patch['title'] as string | undefined) ?? '午夜电台';
  audio['performer'] = (patch['performer'] as string | undefined) ?? 'Sonder';
  audio['file_name'] = (patch['fileName'] as string | undefined) ?? 'midnight.mp3';
  audio['mime_type'] = (patch['mime'] as string | undefined) ?? 'audio/mpeg';
  audio['audio'] = file;
  const content: TdObject = { '@type': 'messageAudio' };
  content['audio'] = audio;
  const message: TdObject = { '@type': 'message' };
  message['id'] = messageId;
  message['chat_id'] = chatId;
  message['content'] = content;
  return message;
}

export default function musicTrackModelTest() {
  describe('musicTrackModel', () => {
    it('把一条音频消息解析成曲目', 0, (): void => {
      const patch: Record<string, Object> = {};
      patch['path'] = '/data/storage/el2/base/files/midnight.mp3';
      const track: MusicTrack | null = musicTrackFromMessage(audioMessage(-100123, 88, patch));
      expect(track !== null).assertTrue();
      expect(track!.chatId).assertEqual(-100123);
      expect(track!.messageId).assertEqual(88);
      expect(track!.title).assertEqual('午夜电台');
      expect(track!.artist).assertEqual('Sonder');
      expect(track!.durationSec).assertEqual(198);
      expect(track!.fileSize).assertEqual(7_900_000);
      expect(track!.localPath).assertEqual('/data/storage/el2/base/files/midnight.mp3');
      expect(track!.fileId).assertEqual(501);
    });

    // 音乐文件常常没写 title/performer，那时列表里必须还有东西可显示。
    it('缺少标题时退回文件名，非音频消息不解析', 0, (): void => {
      const patch: Record<string, Object> = {};
      patch['title'] = '';
      patch['performer'] = '';
      patch['fileName'] = 'track09.flac';
      const track: MusicTrack | null = musicTrackFromMessage(audioMessage(7, 9, patch));
      expect(track!.title).assertEqual('track09.flac');
      expect(track!.artist).assertEqual('');
      const text: TdObject = { '@type': 'message' };
      const textContent: TdObject = { '@type': 'messageText' };
      text['content'] = textContent;
      expect(musicTrackFromMessage(text) === null).assertTrue();
      expect(musicTrackFromMessage(undefined) === null).assertTrue();
    });

    // 同一首歌在不同会话里是两条消息，键必须带会话 id。
    it('曲目键按会话加消息', 0, (): void => {
      expect(musicTrackKey(-100123, 88)).assertEqual('-100123_88');
      expect(musicTrackKey(-100123, 88) === musicTrackKey(-100124, 88)).assertFalse();
    });

    it('时长按 m:ss 排，超过一小时补小时段', 0, (): void => {
      expect(musicDurationLabel(0)).assertEqual('0:00');
      expect(musicDurationLabel(9)).assertEqual('0:09');
      expect(musicDurationLabel(198)).assertEqual('3:18');
      expect(musicDurationLabel(3671)).assertEqual('1:01:11');
      expect(musicDurationLabel(-5)).assertEqual('0:00');
    });

    it('大小与码率的文案', 0, (): void => {
      expect(musicSizeLabel(7_900_000)).assertEqual('7.5 MB');
      expect(musicSizeLabel(940)).assertEqual('940 B');
      expect(musicSizeLabel(0)).assertEqual('');
      // 码率没有现成字段，用大小÷时长估算：7.9MB / 198s ≈ 319 kbps
      expect(musicBitrateLabel(7_900_000, 198)).assertEqual('319 kbps');
      expect(musicBitrateLabel(0, 198)).assertEqual('');
      expect(musicBitrateLabel(7_900_000, 0)).assertEqual('');
    });

    it('格式取 mime，取不到退回扩展名', 0, (): void => {
      expect(musicFormatLabel('audio/flac', 'a.bin')).assertEqual('FLAC');
      expect(musicFormatLabel('audio/mpeg', 'a.bin')).assertEqual('MP3');
      expect(musicFormatLabel('audio/mp4', 'a.bin')).assertEqual('AAC');
      expect(musicFormatLabel('audio/ogg', 'a.bin')).assertEqual('OGG');
      expect(musicFormatLabel('audio/x-wav', 'a.bin')).assertEqual('WAV');
      expect(musicFormatLabel('', 'song.opus')).assertEqual('OPUS');
      expect(musicFormatLabel('', 'song')).assertEqual('');
    });

    // 采样率由 AVMetadataExtractor 读出来（它给的是字符串型的赫兹数），位深它不给，所以不显示。
    it('采样率文案，读不到就空着', 0, (): void => {
      expect(musicSampleLabel(44100)).assertEqual('44.1 kHz');
      expect(musicSampleLabel(96000)).assertEqual('96 kHz');
      expect(musicSampleLabel(0)).assertEqual('');
      expect(musicSampleLabel(Number.NaN)).assertEqual('');
    });

    // 封面渐变按曲目键取色，同一首歌每次进来颜色一样。
    it('封面渐变稳定且落在调色板里', 0, (): void => {
      const a: MusicCoverColors = musicCoverColors('-100123_88');
      const b: MusicCoverColors = musicCoverColors('-100123_88');
      expect(a.from).assertEqual(b.from);
      expect(a.to).assertEqual(b.to);
      expect(a.from.startsWith('#')).assertTrue();
      expect(a.to.startsWith('#')).assertTrue();
      expect(musicCoverColors('').from.startsWith('#')).assertTrue();
    });

    it('搜索按标题、歌手、专辑过滤，忽略大小写与首尾空格', 0, (): void => {
      const patchA: Record<string, Object> = {};
      const patchB: Record<string, Object> = {};
      patchB['title'] = 'Glasshouse';
      patchB['performer'] = 'Mira Kell';
      const tracks: MusicTrack[] = [
        musicTrackFromMessage(audioMessage(1, 1, patchA))!,
        musicTrackFromMessage(audioMessage(1, 2, patchB))!
      ];
      expect(filterMusicTracks(tracks, '  glass ').length).assertEqual(1);
      expect(filterMusicTracks(tracks, 'mira').length).assertEqual(1);
      expect(filterMusicTracks(tracks, '电台').length).assertEqual(1);
      expect(filterMusicTracks(tracks, '').length).assertEqual(2);
      expect(filterMusicTracks(tracks, '没有这首').length).assertEqual(0);
    });

    // 曲库翻页：后一页可能和前一页重叠（消息在期间变动），同一首歌只能有一条；
    // 而且新来的那条更新（下载完成之后本地路径才有值），要顶掉旧的。
    it('翻页合并：去重、保序、新的顶掉旧的', 0, (): void => {
      const cloud: Record<string, Object> = {};
      const local: Record<string, Object> = {};
      local['path'] = '/files/a.mp3';
      const first: MusicTrack = musicTrackFromMessage(audioMessage(5, 1, cloud))!;
      const second: MusicTrack = musicTrackFromMessage(audioMessage(5, 2, cloud))!;
      const firstDownloaded: MusicTrack = musicTrackFromMessage(audioMessage(5, 1, local))!;
      const merged: MusicTrack[] = mergeMusicTracks([first, second], [firstDownloaded]);
      expect(merged.length).assertEqual(2);
      expect(merged[0].messageId).assertEqual(1);
      expect(merged[0].localPath).assertEqual('/files/a.mp3');
      expect(merged[1].messageId).assertEqual(2);
      // 追加的新曲目排在后面，原数组不动
      const existing: MusicTrack[] = [first];
      const appended: MusicTrack[] = mergeMusicTracks(existing, [second]);
      expect(appended.length).assertEqual(2);
      expect(existing.length).assertEqual(1);
    });
    it('parses a track key back into chat and message ids', 0, () => {
      // 超级群的会话 id 是负数，键里因此带一个减号——按最后一个下划线切才不会切错。
      const ref: MusicTrackRef | null = parseMusicTrackKey(musicTrackKey(-1001234567890, 4096));
      expect(ref !== null).assertTrue();
      expect(ref!.chatId).assertEqual(-1001234567890);
      expect(ref!.messageId).assertEqual(4096);
      // 不成形的键返回 null，调用方据此跳过而不是发一发空请求。
      expect(parseMusicTrackKey('') === null).assertTrue();
      expect(parseMusicTrackKey('12345') === null).assertTrue();
      expect(parseMusicTrackKey('12345_') === null).assertTrue();
      expect(parseMusicTrackKey('12345_0') === null).assertTrue();
    });

  });
}
