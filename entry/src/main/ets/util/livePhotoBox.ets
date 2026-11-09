// 把实况照片的**全尺寸静图**夹带在 mp4 里。
//
// 【为什么要夹带】实况的动态部分只有 1080p 级别，而静图是全传感器分辨率。
// 走 inputMessageVideo 发出去之后，静图那一半就丢了——存回图库只能从视频抽帧，
// 拿到的是 1080p（issue #193 修完之后是"诚实的 1080p"，但仍不是原图）。
// TDLib 的 inputThumbnail 有长边 320 的协议约定（见 util/sendThumb），塞不进去。
//
// 【为什么载体是 mp4 文件本体】`util/livePhoto` 挑文件名当标记时列过判据：
// 「协议里唯一一个我们能写、别人不会显示、也不影响任何观感的字段」。文件名装不下
// 一张图，下一个满足这三条的就是文件字节本身——前提是 Telegram 原样保存视频文件
// （**这条尚未验证，见下**）。
//
// 【为什么用 free 盒】ISO-BMFF 定义 `free`/`skip` 盒的语义就是「跳过我」，任何
// 合规的解析器都会忽略它，所以别家客户端播放完全不受影响。这正好是鸿蒙实况照片
// 的逆操作——它是 JPEG 里嵌 MP4，我们做 MP4 里嵌 JPEG。
//
// 盒子结构（全部大端）：
//   [4] 盒长 = 8 + 8 + 4 + jpeg.length
//   [4] 'free'
//   [8] MAGIC 'PGLIVEST'
//   [4] jpeg 字节数
//   [n] jpeg
//
// 【尚未验证的前提】Telegram/TDLib 是否把上传的视频字节原样保存。同类风险见
// util/livePhoto 文件末尾那段（文件名标记能不能活着到对端）。**先做存活实验，
// 别在没验证的前提上建编解码。**

// 8 字节魔数。取得不像任何真实 box 类型，扫描时不会误命中。
export const LIVE_BOX_MAGIC: string = 'PGLIVEST';

const BOX_HEADER: number = 8;   // size(4) + type(4)
const MAGIC_LEN: number = 8;
const LEN_FIELD: number = 4;
export const LIVE_BOX_OVERHEAD: number = BOX_HEADER + MAGIC_LEN + LEN_FIELD;

function writeU32BE(out: Uint8Array, offset: number, value: number): void {
  out[offset] = (value >>> 24) & 0xff;
  out[offset + 1] = (value >>> 16) & 0xff;
  out[offset + 2] = (value >>> 8) & 0xff;
  out[offset + 3] = value & 0xff;
}

function readU32BE(buf: Uint8Array, offset: number): number {
  return ((buf[offset] << 24) >>> 0) + (buf[offset + 1] << 16) +
    (buf[offset + 2] << 8) + buf[offset + 3];
}

function asciiAt(buf: Uint8Array, offset: number, text: string): boolean {
  if (offset < 0 || offset + text.length > buf.length) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    if (buf[offset + i] !== text.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

// 构造要追加到 mp4 末尾的那个 free 盒。jpeg 为空时返回空数组（调用方据此不追加）。
export function buildLiveStillBox(jpeg: Uint8Array): Uint8Array {
  if (jpeg.length === 0) {
    return new Uint8Array(0);
  }
  const total: number = LIVE_BOX_OVERHEAD + jpeg.length;
  const out: Uint8Array = new Uint8Array(total);
  writeU32BE(out, 0, total);
  out[4] = 'f'.charCodeAt(0);
  out[5] = 'r'.charCodeAt(0);
  out[6] = 'e'.charCodeAt(0);
  out[7] = 'e'.charCodeAt(0);
  for (let i = 0; i < MAGIC_LEN; i++) {
    out[BOX_HEADER + i] = LIVE_BOX_MAGIC.charCodeAt(i);
  }
  writeU32BE(out, BOX_HEADER + MAGIC_LEN, jpeg.length);
  out.set(jpeg, LIVE_BOX_OVERHEAD);
  return out;
}

// 夹带的静图在 buf 里的位置。找不到返回 null。
//
// **从后往前扫**：盒子是追加在末尾的，倒着找一次就命中；正着扫要跨过整个视频。
export interface LiveStillSlice {
  start: number;
  length: number;
}

export function findLiveStillBox(buf: Uint8Array): LiveStillSlice | null {
  const magicStart: number = LIVE_BOX_MAGIC.charCodeAt(0);
  for (let i = buf.length - LIVE_BOX_OVERHEAD; i >= BOX_HEADER; i--) {
    if (buf[i] !== magicStart || !asciiAt(buf, i, LIVE_BOX_MAGIC)) {
      continue;
    }
    // 魔数前面 8 字节必须是我们写的盒头，否则是巧合命中（比如视频数据里
    // 恰好出现这串字节）。
    const boxStart: number = i - BOX_HEADER;
    if (!asciiAt(buf, boxStart + 4, 'free')) {
      continue;
    }
    const declared: number = readU32BE(buf, boxStart);
    const jpegLen: number = readU32BE(buf, i + MAGIC_LEN);
    const jpegStart: number = i + MAGIC_LEN + LEN_FIELD;
    // 三条互相印证：盒长自洽、jpeg 不越界、长度非零。
    if (declared !== LIVE_BOX_OVERHEAD + jpegLen) {
      continue;
    }
    if (jpegLen <= 0 || jpegStart + jpegLen > buf.length) {
      continue;
    }
    return { start: jpegStart, length: jpegLen };
  }
  return null;
}
