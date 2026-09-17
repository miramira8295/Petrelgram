import { describe, expect, it } from '@ohos/hypium';
import {
  EBML_UNKNOWN_SIZE, readElementId, readFloat, readInt, readUint, readVarSize
} from '../main/ets/util/webm/EbmlReader';
import {
  demuxWebmAlpha, packAlphaStreams, readWebmTrack, WebmAlphaFrame
} from '../main/ets/util/webm/WebmAlphaDemuxer';
import {
  ALPHA_EMOJI_CHAT_MAX_BYTES, ALPHA_STICKER_MAX_BYTES, alphaStickerMaxBytes, planAlphaDecode
} from '../main/ets/util/webm/AlphaStickerBudget';
import { alphaStickerCandidate } from '../main/ets/util/webm/alphaStickerGate';
import {
  alphaCacheKey, alphaKeyBucket, alphaKeyHighBudget, alphaSizeBucket
} from '../main/ets/util/webm/alphaCacheKey';
import { alphaClipFps, alphaFrameIndexAt } from '../main/ets/util/webm/alphaPlayback';

// 透明 webm 贴纸链路里所有能在主机上跑的部分。
//
// 容器解析尤其值得钉死：解错一个字节，整段码流就是垃圾，而设备上的表现只是
// "贴纸没动"——查不出是哪一层错的。解码那半截要硬件，测不了，所以更要保证
// 送进解码器的东西是对的。

// --- 造一个最小 WebM ---------------------------------------------------------

// EBML 长度：取能装下这个值的最短形式（全 1 是"长度未知"，要避开）。
function sizeBytes(n: number): number[] {
  for (let len = 1; len <= 4; len++) {
    const limit = Math.pow(2, 7 * len) - 1;
    if (n < limit) {
      const out: number[] = [];
      let rest = n;
      for (let i = len - 1; i >= 0; i--) {
        out[i] = rest % 256;
        rest = Math.floor(rest / 256);
      }
      out[0] = out[0] | (0x80 >> (len - 1));
      return out;
    }
  }
  return [0xFF];
}

function idBytes(id: number): number[] {
  const out: number[] = [];
  let rest = id;
  while (rest > 0) {
    out.unshift(rest % 256);
    rest = Math.floor(rest / 256);
  }
  return out.length === 0 ? [0] : out;
}

function elem(id: number, payload: number[]): number[] {
  return idBytes(id).concat(sizeBytes(payload.length)).concat(payload);
}

function uintPayload(v: number): number[] {
  if (v === 0) {
    return [0];
  }
  const out: number[] = [];
  let rest = v;
  while (rest > 0) {
    out.unshift(rest % 256);
    rest = Math.floor(rest / 256);
  }
  return out;
}

function ascii(s: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    out.push(s.charCodeAt(i));
  }
  return out;
}

// track=1, 2 字节相对时间, flags
function blockPayload(relTime: number, flags: number, frame: number[]): number[] {
  const hi = (relTime < 0 ? relTime + 65536 : relTime) >> 8;
  const lo = (relTime < 0 ? relTime + 65536 : relTime) & 0xFF;
  return [0x81, hi & 0xFF, lo, flags].concat(frame);
}

function trackEntry(alphaMode: boolean, codec: string): number[] {
  const video: number[] = elem(0xB0, uintPayload(512))
    .concat(elem(0xBA, uintPayload(384)))
    .concat(alphaMode ? elem(0x53C0, uintPayload(1)) : []);
  return elem(0xAE, elem(0xD7, uintPayload(1))
    .concat(elem(0x83, uintPayload(1)))
    .concat(elem(0x86, ascii(codec)))
    .concat(elem(0xE0, video)));
}

interface FakeFrame {
  relTime: number;
  color: number[];
  alpha: number[] | null;
  flags: number;
}

function buildWebm(frames: FakeFrame[], alphaMode: boolean, codec: string): Uint8Array {
  let cluster: number[] = elem(0xE7, uintPayload(10)); // Cluster Timestamp = 10ms
  for (const f of frames) {
    const block = elem(0xA1, blockPayload(f.relTime, f.flags, f.color));
    let group = block;
    if (f.alpha !== null) {
      const more = elem(0xA6, elem(0xEE, uintPayload(1)).concat(elem(0xA5, f.alpha)));
      group = group.concat(elem(0x75A1, more));
    }
    cluster = cluster.concat(elem(0xA0, group));
  }
  const info = elem(0x1549A966, elem(0x2AD7B1, uintPayload(1000000)));
  const tracks = elem(0x1654AE6B, trackEntry(alphaMode, codec));
  const segment = elem(0x18538067, info.concat(tracks).concat(elem(0x1F43B675, cluster)));
  const header = elem(0x1A45DFA3, elem(0x4286, uintPayload(1)));
  return new Uint8Array(header.concat(segment));
}

function sampleFrames(): FakeFrame[] {
  return [
    { relTime: 0, color: [1, 2, 3, 4], alpha: [9, 9], flags: 0x80 },
    { relTime: 33, color: [5, 6, 7], alpha: [8], flags: 0x00 },
    { relTime: 66, color: [10, 11], alpha: [7, 7, 7], flags: 0x00 }
  ];
}

export default function webmAlphaTest() {
  describe('webmAlpha', () => {
    // --- EBML 原语 ---------------------------------------------------------

    it('reads element ids with their length marker intact', 0, () => {
      const data = new Uint8Array([0x1F, 0x43, 0xB6, 0x75]);
      const id = readElementId(data, 0);
      expect(id.ok).assertTrue();
      expect(id.value).assertEqual(0x1F43B675);
      expect(id.length).assertEqual(4);
    });

    it('strips the length marker from sizes', 0, () => {
      const one = readVarSize(new Uint8Array([0x85]), 0);
      expect(one.value).assertEqual(5);
      expect(one.length).assertEqual(1);
      const two = readVarSize(new Uint8Array([0x40, 0x7F]), 0);
      expect(two.value).assertEqual(127);
      expect(two.length).assertEqual(2);
    });

    it('reports an all-ones size as unknown rather than as a huge length', 0, () => {
      const unknown = readVarSize(new Uint8Array([0xFF]), 0);
      expect(unknown.ok).assertTrue();
      expect(unknown.value).assertEqual(EBML_UNKNOWN_SIZE);
    });

    it('refuses a zero first byte and a truncated tail', 0, () => {
      expect(readElementId(new Uint8Array([0x00]), 0).ok).assertFalse();
      expect(readVarSize(new Uint8Array([0x40]), 0).ok).assertFalse();
      expect(readElementId(new Uint8Array([0x81]), 5).ok).assertFalse();
    });

    it('reads integers past 32 bits without truncating', 0, () => {
      const data = new Uint8Array([0x01, 0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(readUint(data, 0, 6)).assertEqual(Math.pow(2, 40));
      expect(readInt(new Uint8Array([0xFF, 0xFB]), 0, 2)).assertEqual(-5);
      expect(readInt(new Uint8Array([0x00, 0x21]), 0, 2)).assertEqual(33);
    });

    it('decodes both float widths', 0, () => {
      expect(readFloat(new Uint8Array([0x3F, 0x80, 0x00, 0x00]), 0, 4)).assertEqual(1);
      const d = new Uint8Array([0x40, 0x59, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(readFloat(d, 0, 8)).assertEqual(100);
      expect(readFloat(d, 0, 3)).assertEqual(0);
    });

    // --- 轨道头 -------------------------------------------------------------

    it('reads size, codec and AlphaMode off the track header', 0, () => {
      const track = readWebmTrack(buildWebm(sampleFrames(), true, 'V_VP9'));
      expect(track !== null).assertTrue();
      expect(track!.width).assertEqual(512);
      expect(track!.height).assertEqual(384);
      expect(track!.hasAlpha).assertTrue();
      expect(track!.isVp9).assertTrue();
      expect(track!.trackNumber).assertEqual(1);
    });

    it('reports no alpha when AlphaMode is absent', 0, () => {
      const track = readWebmTrack(buildWebm(sampleFrames(), false, 'V_VP9'));
      expect(track !== null).assertTrue();
      expect(track!.hasAlpha).assertFalse();
    });

    it('returns null for bytes that are not a WebM at all', 0, () => {
      expect(readWebmTrack(new Uint8Array([1, 2, 3, 4, 5])) === null).assertTrue();
      expect(readWebmTrack(new Uint8Array(0)) === null).assertTrue();
    });

    // --- 拆包 ---------------------------------------------------------------

    it('pairs every block with its BlockAdditional alpha stream', 0, () => {
      const clip = demuxWebmAlpha(buildWebm(sampleFrames(), true, 'V_VP9'));
      expect(clip !== null).assertTrue();
      expect(clip!.frames.length).assertEqual(3);
      // Cluster 时间戳 10ms + 块内相对时间，刻度 1ms。
      expect(clip!.frames[0].timeMs).assertEqual(10);
      expect(clip!.frames[1].timeMs).assertEqual(43);
      expect(clip!.frames[2].timeMs).assertEqual(76);
      expect(clip!.frames[0].color.length).assertEqual(4);
      expect(clip!.frames[0].color[0]).assertEqual(1);
      expect(clip!.frames[1].alpha!.length).assertEqual(1);
      expect(clip!.frames[1].alpha![0]).assertEqual(8);
      expect(clip!.durationMs).assertEqual(76);
    });

    // 轨道声明了 AlphaMode=1 却一帧 alpha 都没有 = 文件坏了，整段退回播放器。
    it('refuses a clip that claims alpha but carries none', 0, () => {
      const frames: FakeFrame[] = [{ relTime: 0, color: [1, 2], alpha: null, flags: 0x80 }];
      expect(demuxWebmAlpha(buildWebm(frames, true, 'V_VP9')) === null).assertTrue();
    });

    // 2026-09-14 契约变更：不透明贴纸也走帧序列（alpha 恒 255），不再为它们
    // 各养一个原生播放器实例。
    it('accepts an opaque VP9 clip and packs it with empty alpha streams', 0, () => {
      const frames: FakeFrame[] = [
        { relTime: 0, color: [1, 2], alpha: null, flags: 0x80 },
        { relTime: 33, color: [3, 4, 5], alpha: null, flags: 0x00 }
      ];
      const clip = demuxWebmAlpha(buildWebm(frames, false, 'V_VP9'));
      expect(clip !== null).assertTrue();
      expect(clip!.track.hasAlpha).assertFalse();
      expect(clip!.frames.length).assertEqual(2);
      const payload = packAlphaStreams(clip!.frames, 1);
      expect(payload !== null).assertTrue();
      expect(payload!.colorData.byteLength).assertEqual(5);
      // 两块 alpha 缓冲为空 = 原生走 opaque 分支。
      expect(payload!.alphaData.byteLength).assertEqual(0);
      expect(payload!.alphaLengths.byteLength).assertEqual(0);
      expect(payload!.keptTimesMs.length).assertEqual(2);
    });

    it('refuses a mixed clip at pack time too', 0, () => {
      const mixed: WebmAlphaFrame[] = [
        { timeMs: 0, color: new Uint8Array([1]), alpha: new Uint8Array([2]) },
        { timeMs: 33, color: new Uint8Array([3]), alpha: null }
      ];
      expect(packAlphaStreams(mixed, 1) === null).assertTrue();
    });

    it('refuses a clip where only some blocks carry alpha', 0, () => {
      const frames: FakeFrame[] = [
        { relTime: 0, color: [1, 2], alpha: [3], flags: 0x80 },
        { relTime: 33, color: [4, 5], alpha: null, flags: 0x00 }
      ];
      // 缺一帧 alpha 就意味着那一帧要拿不透明兜底，画面会闪——宁可整段回退。
      expect(demuxWebmAlpha(buildWebm(frames, true, 'V_VP9')) === null).assertTrue();
    });

    // 非 VP9 仍然退回播放器：随包的 libvpx 只编了 VP9 解码器。
    it('leaves non-VP9 clips to the existing player', 0, () => {
      expect(demuxWebmAlpha(buildWebm(sampleFrames(), true, 'V_VP8')) === null).assertTrue();
    });

    it('bails out on laced blocks instead of guessing frame boundaries', 0, () => {
      const frames: FakeFrame[] = [{ relTime: 0, color: [1, 2], alpha: [3], flags: 0x06 }];
      expect(demuxWebmAlpha(buildWebm(frames, true, 'V_VP9')) === null).assertTrue();
    });

    // --- 打包给原生 ---------------------------------------------------------

    it('packs every packet even when only some frames are kept', 0, () => {
      const clip = demuxWebmAlpha(buildWebm(sampleFrames(), true, 'V_VP9'));
      const payload = packAlphaStreams(clip!.frames, 2);
      expect(payload !== null).assertTrue();
      // VP9 是帧间预测的：包必须一个不落地喂进去，抽的只是解出来的帧。
      const lengths = new Int32Array(payload!.colorLengths);
      expect(lengths.length).assertEqual(3);
      expect(lengths[0]).assertEqual(4);
      expect(lengths[1]).assertEqual(3);
      expect(lengths[2]).assertEqual(2);
      expect(payload!.colorData.byteLength).assertEqual(9);
      const bytes = new Uint8Array(payload!.colorData);
      expect(bytes[0]).assertEqual(1);
      expect(bytes[4]).assertEqual(5);
      expect(payload!.alphaData.byteLength).assertEqual(6);
      // 保留的是第 0 和第 2 帧。
      expect(payload!.keptTimesMs.length).assertEqual(2);
      expect(payload!.keptTimesMs[0]).assertEqual(10);
      expect(payload!.keptTimesMs[1]).assertEqual(76);
    });

    it('rejects an empty or malformed frame list', 0, () => {
      expect(packAlphaStreams([], 1) === null).assertTrue();
      // 空的色彩包才是真坏：alpha 为 null 现在是合法的"不透明"，见上面那条。
      const broken: WebmAlphaFrame[] = [{ timeMs: 0, color: new Uint8Array(0), alpha: null }];
      expect(packAlphaStreams(broken, 1) === null).assertTrue();
      const opaque: WebmAlphaFrame[] = [{ timeMs: 0, color: new Uint8Array([1]), alpha: null }];
      expect(packAlphaStreams(opaque, 0) === null).assertTrue();
    });

    // --- 内存预算 -----------------------------------------------------------

    it('decodes to the display size, never to the sticker native size', 0, () => {
      const plan = planAlphaDecode(512, 512, 160, 90, ALPHA_STICKER_MAX_BYTES);
      expect(plan.accept).assertTrue();
      expect(plan.targetW <= 256).assertTrue();
      expect(plan.targetW).assertEqual(plan.targetH);
      expect(plan.bytes).assertEqual(plan.targetW * plan.targetH * 4 * plan.frameCount);
      expect(plan.bytes <= ALPHA_STICKER_MAX_BYTES).assertTrue();
    });

    it('keeps the source aspect ratio', 0, () => {
      const plan = planAlphaDecode(512, 256, 200, 60, ALPHA_STICKER_MAX_BYTES);
      expect(plan.accept).assertTrue();
      expect(plan.targetW).assertEqual(plan.targetH * 2);
    });

    it('never upscales past the source', 0, () => {
      const plan = planAlphaDecode(100, 100, 512, 30, ALPHA_STICKER_MAX_BYTES);
      expect(plan.accept).assertTrue();
      expect(plan.targetW <= 100).assertTrue();
    });

    it('trades quality then frame rate as the budget shrinks', 0, () => {
      const roomy = planAlphaDecode(512, 512, 256, 90, ALPHA_STICKER_MAX_BYTES);
      const tight = planAlphaDecode(512, 512, 256, 90, 2 * 1024 * 1024);
      expect(roomy.accept).assertTrue();
      expect(tight.accept).assertTrue();
      expect(tight.bytes <= 2 * 1024 * 1024).assertTrue();
      // 先糊后卡：同样的预算下降分辨率比降帧率更不容易被看出来。
      expect(tight.targetW <= roomy.targetW).assertTrue();
    });

    it('gives up instead of decoding something unplayable', 0, () => {
      expect(planAlphaDecode(512, 512, 160, 90, 4096).accept).assertFalse();
      expect(planAlphaDecode(0, 512, 160, 90, ALPHA_STICKER_MAX_BYTES).accept).assertFalse();
      expect(planAlphaDecode(512, 512, 160, 0, ALPHA_STICKER_MAX_BYTES).accept).assertFalse();
      // 帧数远超 Telegram 贴纸的约定（≤3 秒 30fps），抽到 1/3 都装不下。
      expect(planAlphaDecode(512, 512, 160, 900, ALPHA_STICKER_MAX_BYTES).accept).assertFalse();
    });

    // --- 素材门控 -----------------------------------------------------------
    //
    // 这里原本还有一条"API 23 才开门"的门控，随解码器换成随包自带的 libvpx
    // 一并删掉了：那条门控挡的是"系统有没有 VP9"，而现在系统有没有已经与本
    // 功能无关。剩下的唯一运行期条件是原生模块加载成功（nativeAvailable），
    // 那个没法在单测里伪造。

    it('only offers the new path to asset classes that can carry alpha', 0, () => {
      expect(alphaStickerCandidate('sticker')).assertTrue();
      expect(alphaStickerCandidate('emojiChat')).assertTrue();
      expect(alphaStickerCandidate('emojiStatus')).assertTrue();
      // GIF 和视频本来就不透明，让它们去试一次纯属浪费。
      expect(alphaStickerCandidate('gif')).assertFalse();
      expect(alphaStickerCandidate('video')).assertFalse();
      expect(alphaStickerCandidate('')).assertFalse();
    });
    // 2026-09-17：会话里单发的 WebM 大表情放宽单张解码预算。256px 一帧 262,144 字节，
    // 12MB 只装得下 48 帧，3 秒 30fps（90 帧）只能隔帧取 → 实际 15fps，看着一顿一顿。
    it('大表情放宽预算后 256px 保住整段 90 帧，普通贴纸仍隔帧', 0, (): void => {
      const wide = planAlphaDecode(512, 512, 256, 90, ALPHA_EMOJI_CHAT_MAX_BYTES, ALPHA_EMOJI_CHAT_MAX_BYTES);
      expect(wide.accept).assertTrue();
      expect(wide.targetW).assertEqual(256);
      expect(wide.frameStep).assertEqual(1);
      // 不传上限 = 普通贴纸的 12MB，行为不变
      const normal = planAlphaDecode(512, 512, 256, 90, ALPHA_EMOJI_CHAT_MAX_BYTES);
      expect(normal.frameStep).assertEqual(2);
      // 放宽的是单张上限，不是全局池子：池子里只剩 8MB 时照样得降
      const squeezed = planAlphaDecode(512, 512, 256, 90, 8 * 1024 * 1024, ALPHA_EMOJI_CHAT_MAX_BYTES);
      expect(squeezed.accept).assertTrue();
      expect(squeezed.frameStep).assertEqual(3);
    });

    it('只有会话里的大表情走放宽预算', 0, (): void => {
      expect(alphaStickerMaxBytes('emojiChat')).assertEqual(ALPHA_EMOJI_CHAT_MAX_BYTES);
      expect(alphaStickerMaxBytes('sticker')).assertEqual(ALPHA_STICKER_MAX_BYTES);
      expect(alphaStickerMaxBytes('emojiPicker')).assertEqual(ALPHA_STICKER_MAX_BYTES);
      expect(alphaStickerMaxBytes('emojiStatus')).assertEqual(ALPHA_STICKER_MAX_BYTES);
    });

    // 缓存键必须带上预算档位：解码结果连抽帧步长一起缓存（内存 + 磁盘）。不带的话，
    // 之前按 15fps 缓存过的大表情会一直命中旧缓存，放宽预算等于没改。
    it('缓存键区分预算档位，且能原样拆回尺寸档', 0, (): void => {
      const normal: string = alphaCacheKey('/d/a.webm', 256, false);
      const high: string = alphaCacheKey('/d/a.webm', 256, true);
      expect(normal === high).assertFalse();
      expect(alphaKeyBucket(normal)).assertEqual(256);
      expect(alphaKeyBucket(high)).assertEqual(256);
      expect(alphaKeyHighBudget(normal)).assertFalse();
      expect(alphaKeyHighBudget(high)).assertTrue();
    });

    it('显示尺寸按 32px 归桶，夹在 96~256', 0, (): void => {
      expect(alphaSizeBucket(480)).assertEqual(256);
      expect(alphaSizeBucket(160)).assertEqual(160);
      expect(alphaSizeBucket(100)).assertEqual(128);
      expect(alphaSizeBucket(10)).assertEqual(96);
    });

    // 出帧改由 displaySync 驱动后，时钟按这段帧序列自己的帧率跳。
    it('帧序列自身的帧率', 0, (): void => {
      expect(alphaClipFps(90, 3000)).assertEqual(30);
      expect(alphaClipFps(45, 3000)).assertEqual(15);
      expect(alphaClipFps(0, 0)).assertEqual(30);       // 拿不到时长：按 Telegram 规范的 30
      expect(alphaClipFps(600, 1000)).assertEqual(60);  // 封顶
    });

    it('按时刻查该显示第几帧', 0, (): void => {
      const times: number[] = [0, 33, 66, 100];
      expect(alphaFrameIndexAt(times, 0)).assertEqual(0);
      expect(alphaFrameIndexAt(times, 50)).assertEqual(1);
      expect(alphaFrameIndexAt(times, 99)).assertEqual(2);
      expect(alphaFrameIndexAt(times, 1000)).assertEqual(3);
      expect(alphaFrameIndexAt([], 50)).assertEqual(0);
    });
  });
}
