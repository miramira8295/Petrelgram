import { describe, expect, it } from '@ohos/hypium';
import {
  AUDIO_HEADER_PREFIX_BYTES, AudioSourceInfo, audioSourceKnown, probeAudioHeader
} from '../main/ets/util/audioHeaderProbe';

// 音源信息的文件头解析（2026-09-18，音乐中心）。
//
// 【为什么自己解而不是用解码器】码率/采样率/位深这三项：系统的 AVMetadataExtractor 只给
// 采样率；已经随包的 ijkplayer 里那份 FFmpeg 能给码率与采样率，但 **位深它不给**，而且
// 符号没从 .so 导出，没法自己调。这几种常见格式的头部本来就写着这些数，自己解还有两个
// 额外好处：不用整首下完（头部在文件最前面，配合 TDLib 分段下载即可），以及可单测。
// 解不出来的格式再退回 ijk 探测（services/AudioMetadataProbe）。

function bytes(values: number[]): Uint8Array {
  return new Uint8Array(values);
}

function ascii(text: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    out.push(text.charCodeAt(i));
  }
  return out;
}

function u32be(value: number): number[] {
  return [(value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff];
}

function u32le(value: number): number[] {
  return [value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff];
}

// STREAMINFO 的后 64 位是打包的：采样率 20 位、声道-1 3 位、位深-1 5 位、总样本数 36 位。
function flacStreamInfo(sampleRate: number, channels: number, bits: number, totalSamples: number): number[] {
  const packed: number[] = [
    (sampleRate >>> 12) & 0xff,
    (sampleRate >>> 4) & 0xff,
    ((sampleRate & 0x0f) << 4) | (((channels - 1) & 0x07) << 1) | (((bits - 1) >>> 4) & 0x01),
    (((bits - 1) & 0x0f) << 4) | ((Math.floor(totalSamples / 0x100000000)) & 0x0f),
    (totalSamples >>> 24) & 0xff, (totalSamples >>> 16) & 0xff,
    (totalSamples >>> 8) & 0xff, totalSamples & 0xff
  ];
  const md5: number[] = new Array<number>(16).fill(0);
  return ascii('fLaC')
    .concat([0x00, 0x00, 0x00, 0x22])            // 元数据块头：STREAMINFO，长度 34
    .concat([0x10, 0x00, 0x10, 0x00])            // 最小/最大块大小
    .concat([0, 0, 0, 0, 0, 0])                  // 最小/最大帧大小
    .concat(packed).concat(md5);
}

function wavHeader(sampleRate: number, channels: number, bits: number): number[] {
  const byteRate: number = sampleRate * channels * bits / 8;
  return ascii('RIFF').concat(u32le(0)).concat(ascii('WAVE'))
    .concat(ascii('fmt ')).concat(u32le(16))
    .concat([1, 0])                               // PCM
    .concat([channels & 0xff, 0])
    .concat(u32le(sampleRate))
    .concat(u32le(byteRate))
    .concat([(channels * bits / 8) & 0xff, 0])
    .concat([bits & 0xff, 0]);
}

export default function audioHeaderProbeTest() {
  describe('audioHeaderProbe', () => {
    // 只取文件头这一段就够：解析全靠开头这几十 KB。
    it('取头部的字节数是个合理的小数目', 0, (): void => {
      expect(AUDIO_HEADER_PREFIX_BYTES >= 16 * 1024).assertTrue();
      expect(AUDIO_HEADER_PREFIX_BYTES <= 256 * 1024).assertTrue();
    });

    it('FLAC：采样率、声道、位深、时长全都有', 0, (): void => {
      const info: AudioSourceInfo = probeAudioHeader(bytes(flacStreamInfo(96000, 2, 24, 96000 * 254)));
      expect(info.format).assertEqual('FLAC');
      expect(info.sampleRateHz).assertEqual(96000);
      expect(info.channels).assertEqual(2);
      expect(info.bitDepth).assertEqual(24);
      expect(info.durationSec).assertEqual(254);
      // 无损格式的码率要靠文件大小算，头部本身没有
      expect(info.bitrateKbps).assertEqual(0);
      expect(audioSourceKnown(info)).assertTrue();
    });

    it('WAV：字节率直接给出码率', 0, (): void => {
      const info: AudioSourceInfo = probeAudioHeader(bytes(wavHeader(44100, 2, 16)));
      expect(info.format).assertEqual('WAV');
      expect(info.sampleRateHz).assertEqual(44100);
      expect(info.channels).assertEqual(2);
      expect(info.bitDepth).assertEqual(16);
      expect(info.bitrateKbps).assertEqual(1411);
    });

    // 真实的 mp3 前面几乎都挂着 ID3v2，跳过它才找得到第一帧。
    it('MP3：跳过 ID3v2 后读帧头', 0, (): void => {
      const id3: number[] = ascii('ID3').concat([3, 0, 0]).concat([0, 0, 0, 10])
        .concat(new Array<number>(10).fill(0));
      const frame: number[] = [0xff, 0xfb, 0xe0, 0x00];  // MPEG1 Layer3 320kbps 44.1kHz 立体声
      const info: AudioSourceInfo = probeAudioHeader(bytes(id3.concat(frame)));
      expect(info.format).assertEqual('MP3');
      expect(info.sampleRateHz).assertEqual(44100);
      expect(info.channels).assertEqual(2);
      expect(info.bitrateKbps).assertEqual(320);
      // 有损格式没有位深这一说
      expect(info.bitDepth).assertEqual(0);
    });

    it('Opus：取头里的输入采样率，声道数在固定位置', 0, (): void => {
      const head: number[] = ascii('OggS').concat(new Array<number>(20).fill(0))
        .concat(ascii('OpusHead')).concat([1, 2]).concat([0x38, 0x01]).concat(u32le(48000));
      const info: AudioSourceInfo = probeAudioHeader(bytes(head));
      expect(info.format).assertEqual('OPUS');
      expect(info.sampleRateHz).assertEqual(48000);
      expect(info.channels).assertEqual(2);
    });

    it('Vorbis：标识头里的声道与采样率', 0, (): void => {
      const head: number[] = ascii('OggS').concat(new Array<number>(20).fill(0))
        .concat([0x01]).concat(ascii('vorbis')).concat(u32le(0))
        .concat([2]).concat(u32le(44100)).concat(u32le(0)).concat(u32le(192000));
      const info: AudioSourceInfo = probeAudioHeader(bytes(head));
      expect(info.format).assertEqual('OGG');
      expect(info.sampleRateHz).assertEqual(44100);
      expect(info.channels).assertEqual(2);
      expect(info.bitrateKbps).assertEqual(192);
    });

    // m4a/aac：采样率写在 mp4a 表项里，是 16.16 定点数。
    it('MP4：从 mp4a 表项取声道与采样率', 0, (): void => {
      const entry: number[] = ascii('mp4a')
        .concat(new Array<number>(6).fill(0)).concat([0, 1])   // 保留 + data_reference_index
        .concat(new Array<number>(8).fill(0))                  // 保留
        .concat([0, 2])                                        // 声道
        .concat([0, 16])                                       // 样本大小
        .concat([0, 0]).concat([0, 0])                         // pre_defined + 保留
        .concat(u32be(44100 * 65536));                         // 采样率 16.16
      const head: number[] = ascii('    ').concat(ascii('ftypM4A ')).concat(entry);
      const info: AudioSourceInfo = probeAudioHeader(bytes(head));
      expect(info.format).assertEqual('AAC');
      expect(info.sampleRateHz).assertEqual(44100);
      expect(info.channels).assertEqual(2);
    });

    it('认不出来就老实说不知道，不猜', 0, (): void => {
      const unknown: AudioSourceInfo = probeAudioHeader(bytes([1, 2, 3, 4, 5, 6, 7, 8]));
      expect(unknown.format).assertEqual('');
      expect(unknown.sampleRateHz).assertEqual(0);
      expect(unknown.channels).assertEqual(0);
      expect(audioSourceKnown(unknown)).assertFalse();
      expect(probeAudioHeader(new Uint8Array(0)).format).assertEqual('');
    });

    // 头部被截断（分段下载只到一半）时不能抛异常，只能当不知道。
    it('半截头部不抛异常', 0, (): void => {
      const half: number[] = flacStreamInfo(44100, 2, 16, 1000).slice(0, 12);
      expect(audioSourceKnown(probeAudioHeader(bytes(half)))).assertFalse();
      expect(probeAudioHeader(bytes(ascii('RIFF'))).format).assertEqual('');
    });
  });
}
