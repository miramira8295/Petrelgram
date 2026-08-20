// EBML 的底层原语（Matroska/WebM 的字节层）。
//
// 单独成文件是为了能单测：容器解析错一个字节就会让整段码流报废，而这一层又
// 完全是纯函数，值得钉死。元素语义留给 WebmAlphaDemuxer。

// 一个变长整数的读取结果。ok=false 时 value/length 无意义。
export interface EbmlVint {
  ok: boolean;
  value: number;
  length: number;
}

// 长度未知的元素（size 的有效位全 1）。WebM 的 Segment / Cluster 允许这么写，
// 流式封装尤其常见，所以不能当成解析失败。
export const EBML_UNKNOWN_SIZE: number = -1;

function invalid(): EbmlVint {
  return { ok: false, value: 0, length: 0 };
}

// 首字节的前导零个数 + 1 = 该 vint 的总字节数。首字节为 0 意味着长度 > 8，
// WebM 里不会出现，按损坏处理。
function vintLength(first: number): number {
  for (let i = 0; i < 8; i++) {
    if ((first & (0x80 >> i)) !== 0) {
      return i + 1;
    }
  }
  return 0;
}

// 元素 ID。**保留**首字节的长度标记位——Matroska 规范里的 ID 常量
// （0x1F43B675 等）就是带标记的形式，去掉标记反而对不上。
export function readElementId(data: Uint8Array, pos: number): EbmlVint {
  if (pos < 0 || pos >= data.length) {
    return invalid();
  }
  const len = vintLength(data[pos]);
  // ID 最长 4 字节；再长的一定是把数据当成了 ID，说明前面已经走偏了。
  if (len === 0 || len > 4 || pos + len > data.length) {
    return invalid();
  }
  let value = 0;
  for (let i = 0; i < len; i++) {
    value = value * 256 + data[pos + i];
  }
  return { ok: true, value: value, length: len };
}

// 元素长度。与 ID 相反，这里要**去掉**长度标记位。
export function readVarSize(data: Uint8Array, pos: number): EbmlVint {
  if (pos < 0 || pos >= data.length) {
    return invalid();
  }
  const len = vintLength(data[pos]);
  if (len === 0 || pos + len > data.length) {
    return invalid();
  }
  let value: number = data[pos] & (0xFF >> len);
  let allOnes: boolean = value === (0xFF >> len);
  for (let i = 1; i < len; i++) {
    const b: number = data[pos + i];
    allOnes = allOnes && b === 0xFF;
    value = value * 256 + b;
  }
  if (allOnes) {
    return { ok: true, value: EBML_UNKNOWN_SIZE, length: len };
  }
  return { ok: true, value: value, length: len };
}

// 大端无符号整数。用乘法而不是移位：EBML 允许 8 字节，位运算在 32 位处截断。
export function readUint(data: Uint8Array, pos: number, len: number): number {
  if (len <= 0 || pos < 0 || pos + len > data.length) {
    return 0;
  }
  let value = 0;
  for (let i = 0; i < len; i++) {
    value = value * 256 + data[pos + i];
  }
  return value;
}

// 大端有符号整数（Block 的相对时间戳是 2 字节有符号）。
export function readInt(data: Uint8Array, pos: number, len: number): number {
  if (len <= 0 || pos < 0 || pos + len > data.length) {
    return 0;
  }
  const raw = readUint(data, pos, len);
  const limit = Math.pow(2, len * 8 - 1);
  return raw >= limit ? raw - limit * 2 : raw;
}

// 大端浮点（Duration 写成 float32 或 float64）。
export function readFloat(data: Uint8Array, pos: number, len: number): number {
  if (pos < 0 || pos + len > data.length) {
    return 0;
  }
  if (len !== 4 && len !== 8) {
    return 0;
  }
  // 手算而不是用 DataView：Uint8Array 可能是别人 buffer 的一段视图，
  // byteOffset 对不上就会读到隔壁的字节。
  const sign: number = (data[pos] & 0x80) !== 0 ? -1 : 1;
  if (len === 4) {
    const exp: number = ((data[pos] & 0x7F) << 1) | (data[pos + 1] >> 7);
    const frac: number = ((data[pos + 1] & 0x7F) * 65536) + (data[pos + 2] * 256) + data[pos + 3];
    if (exp === 0) {
      return sign * frac * Math.pow(2, -149);
    }
    if (exp === 0xFF) {
      return frac === 0 ? sign * Infinity : NaN;
    }
    return sign * (1 + frac * Math.pow(2, -23)) * Math.pow(2, exp - 127);
  }
  const exp: number = ((data[pos] & 0x7F) << 4) | (data[pos + 1] >> 4);
  let frac: number = data[pos + 1] & 0x0F;
  for (let i = 2; i < 8; i++) {
    frac = frac * 256 + data[pos + i];
  }
  if (exp === 0) {
    return sign * frac * Math.pow(2, -1074);
  }
  if (exp === 0x7FF) {
    return frac === 0 ? sign * Infinity : NaN;
  }
  return sign * (1 + frac * Math.pow(2, -52)) * Math.pow(2, exp - 1023);
}
