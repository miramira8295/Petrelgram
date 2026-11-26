// Telegram WEB proxy（tproxy-server）协议 v1 的帧编解码。
//
// 帧格式（PROTOCOL.md，全部大端）：
//   type:u8 | stream_id:u24 | payload_length:u32 | payload
//
// 这一层只管字节，不碰加密：DATA 里装的是 TDLib 已经用 MTProxy secret 变换过的
// 字节（obfuscated2 + AES-CTR 由 tgnet 自己完成，见 tproxy-server/ANDROID.md 的
// loopback 捷径），本层只负责把多条 TCP 连接多路复用到一路 carrier 上。
export const FRAME_OPEN: number = 0x01;
export const FRAME_DATA: number = 0x02;
export const FRAME_CLOSE: number = 0x03;
export const FRAME_WINDOW: number = 0x04;
export const FRAME_PING: number = 0x05;
export const FRAME_PONG: number = 0x06;
export const FRAME_HELLO: number = 0x10;
export const FRAME_WELCOME: number = 0x11;
export const FRAME_BYE: number = 0x1f;

export const FRAME_HEADER_BYTES: number = 8;
// 单条 DATA 的载荷上限。官方 Android 侧车用 64KiB，这里保持一致。
export const FRAME_MAX_PAYLOAD: number = 64 * 1024;

export interface WebProxyFrame {
  type: number;
  streamId: number;
  payload: Uint8Array;
}

export function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total: number = 0;
  for (const part of parts) {
    total += part.length;
  }
  const out: Uint8Array = new Uint8Array(total);
  let at: number = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.length;
  }
  return out;
}

export function u32be(value: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(4);
  out[0] = (value >>> 24) & 0xff;
  out[1] = (value >>> 16) & 0xff;
  out[2] = (value >>> 8) & 0xff;
  out[3] = value & 0xff;
  return out;
}

export function readU32be(bytes: Uint8Array, at: number): number {
  const a: number = bytes[at] ?? 0;
  const b: number = bytes[at + 1] ?? 0;
  const c: number = bytes[at + 2] ?? 0;
  const d: number = bytes[at + 3] ?? 0;
  // 无符号还原：>>> 0 把 32 位有符号结果转回无符号。
  return (((a << 24) | (b << 16) | (c << 8) | d) >>> 0);
}

export function webProxyFrameBytes(type: number, streamId: number, payload: Uint8Array | null): Uint8Array {
  const length: number = payload === null ? 0 : payload.length;
  const out: Uint8Array = new Uint8Array(FRAME_HEADER_BYTES + length);
  out[0] = type & 0xff;
  out[1] = (streamId >>> 16) & 0xff;
  out[2] = (streamId >>> 8) & 0xff;
  out[3] = streamId & 0xff;
  out[4] = (length >>> 24) & 0xff;
  out[5] = (length >>> 16) & 0xff;
  out[6] = (length >>> 8) & 0xff;
  out[7] = length & 0xff;
  if (payload !== null && length > 0) {
    out.set(payload, FRAME_HEADER_BYTES);
  }
  return out;
}

// 把一帧帧攒进一个批次。carrier 的一次 HTTP body / 一条 WS message = 一批完整帧，
// 攒批能把「每条 socket 消息发一次请求」的开销摊掉（WebProxyBridge 的经验：
// 逐条 send 会把主线程排满，6 秒就会撞上 THREAD_BLOCK_6S）。
export class WebProxyFrameWriter {
  private parts: Uint8Array[] = [];
  private total: number = 0;

  add(type: number, streamId: number, payload: Uint8Array | null): void {
    const bytes: Uint8Array = webProxyFrameBytes(type, streamId, payload);
    this.parts.push(bytes);
    this.total += bytes.length;
  }

  get bytes(): number {
    return this.total;
  }

  get empty(): boolean {
    return this.parts.length === 0;
  }

  take(): Uint8Array | null {
    if (this.parts.length === 0) {
      return null;
    }
    const out: Uint8Array = concatBytes(this.parts);
    this.parts = [];
    this.total = 0;
    return out;
  }
}

// 流式拆帧：carrier 收到的字节可能半帧、也可能一批里粘着好几帧。
export class WebProxyFrameReader {
  private rest: Uint8Array = new Uint8Array(0);

  push(chunk: Uint8Array): WebProxyFrame[] {
    let buffer: Uint8Array = chunk;
    if (this.rest.length > 0) {
      buffer = concatBytes([this.rest, chunk]);
    }
    const frames: WebProxyFrame[] = [];
    let at: number = 0;
    while (buffer.length - at >= FRAME_HEADER_BYTES) {
      const type: number = buffer[at] ?? 0;
      const streamId: number = (((buffer[at + 1] ?? 0) << 16) | ((buffer[at + 2] ?? 0) << 8) | (buffer[at + 3] ?? 0)) >>> 0;
      const length: number = readU32be(buffer, at + 4);
      if (length > FRAME_MAX_PAYLOAD * 4) {
        // 明显超出上限的长度字段：丢弃剩余缓存，等 carrier 重连，避免把内存撑爆。
        this.rest = new Uint8Array(0);
        return frames;
      }
      if (buffer.length - at - FRAME_HEADER_BYTES < length) {
        break;
      }
      const payload: Uint8Array = buffer.slice(at + FRAME_HEADER_BYTES, at + FRAME_HEADER_BYTES + length);
      frames.push({ type: type, streamId: streamId, payload: payload });
      at += FRAME_HEADER_BYTES + length;
    }
    this.rest = at >= buffer.length ? new Uint8Array(0) : buffer.slice(at);
    return frames;
  }

  reset(): void {
    this.rest = new Uint8Array(0);
  }
}
