import { socket } from '@kit.NetworkKit';
import { VideoStreamSession } from './VideoStreamSession';
import { logE, logW } from '../util/log';

const LOOPBACK: string = '127.0.0.1';
const SERVE_CHUNK_SIZE: number = 256 * 1024;
const RANGE_WAIT_MS: number = 60000;

interface HttpRange {
  start: number;
  end: number;
  partial: boolean;
}

export class VideoRangeServer {
  private session: VideoStreamSession;
  private totalSize: number;
  private mimeType: string;
  private fileId: number;
  private server: socket.TCPSocketServer | null = null;
  private clients: Map<number, socket.TCPSocketConnection> = new Map();
  private requestBuffers: Map<number, string> = new Map();
  private closed: boolean = false;

  constructor(session: VideoStreamSession, fileId: number, totalSize: number, mimeType: string) {
    this.session = session;
    this.fileId = fileId;
    this.totalSize = totalSize;
    this.mimeType = mimeType.trim() !== '' ? mimeType.trim() : 'application/octet-stream';
  }

  async start(): Promise<string> {
    if (this.totalSize <= 0) {
      throw new Error('video size is unknown');
    }
    const server = socket.constructTCPSocketServerInstance();
    this.server = server;
    server.on('connect', (connection: socket.TCPSocketConnection): void => {
      this.clients.set(connection.clientId, connection);
      this.requestBuffers.set(connection.clientId, '');
      connection.on('message', (info: socket.SocketMessageInfo): void => {
        this.onMessage(connection, info.message);
      });
      connection.on('close', (): void => {
        this.clients.delete(connection.clientId);
        this.requestBuffers.delete(connection.clientId);
      });
      connection.on('error', (error: Error): void => {
        logW(`VideoRangeServer client ${connection.clientId}: ${error.message}`);
      });
    });
    server.on('error', (error: Error): void => {
      if (!this.closed) {
        logE(`VideoRangeServer: ${error.message}`);
      }
    });
    await server.listen({ address: LOOPBACK, port: 0, family: 1 });
    const address = await server.getLocalAddress();
    if (address.port === undefined) {
      throw new Error('range server has no port');
    }
    return `http://${LOOPBACK}:${address.port}/video/${this.fileId}`;
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    for (const connection of this.clients.values()) {
      connection.close().catch((): void => {});
    }
    this.clients.clear();
    this.requestBuffers.clear();
    if (this.server !== null) {
      const server = this.server;
      this.server = null;
      server.close().catch((): void => {});
    }
  }

  private onMessage(connection: socket.TCPSocketConnection, data: ArrayBuffer): void {
    if (this.closed) {
      return;
    }
    const clientId = connection.clientId;
    const request = (this.requestBuffers.get(clientId) ?? '') + this.decodeAscii(data);
    if (request.indexOf('\r\n\r\n') < 0) {
      this.requestBuffers.set(clientId, request);
      return;
    }
    this.requestBuffers.delete(clientId);
    connection.off('message');
    this.serve(connection, request).catch((e: Error): void => {
      logE(`VideoRangeServer.serve failed: ${e.message}`);
      connection.close().catch((): void => {});
    });
  }

  private async serve(connection: socket.TCPSocketConnection, request: string): Promise<void> {
    const firstLineEnd = request.indexOf('\r\n');
    const firstLine = firstLineEnd >= 0 ? request.substring(0, firstLineEnd) : request;
    const parts = firstLine.split(' ');
    const method = parts.length > 0 ? parts[0].toUpperCase() : '';
    if (method !== 'GET' && method !== 'HEAD') {
      await this.sendStatus(connection, '405 Method Not Allowed');
      return;
    }
    const range = this.parseRange(request);
    if (range === null) {
      await this.sendStatus(connection, '416 Range Not Satisfiable', `Content-Range: bytes */${this.totalSize}\r\n`);
      return;
    }
    const contentLength = range.end - range.start + 1;
    const status = range.partial ? '206 Partial Content' : '200 OK';
    let headers = `HTTP/1.1 ${status}\r\n` +
      `Content-Type: ${this.mimeType}\r\n` +
      'Accept-Ranges: bytes\r\n' +
      `Content-Length: ${contentLength}\r\n`;
    if (range.partial) {
      headers += `Content-Range: bytes ${range.start}-${range.end}/${this.totalSize}\r\n`;
    }
    headers += 'Connection: close\r\n\r\n';
    await connection.send({ data: headers });
    if (method === 'HEAD') {
      await connection.close();
      return;
    }
    let offset = range.start;
    while (!this.closed && offset <= range.end) {
      const length = Math.min(SERVE_CHUNK_SIZE, range.end - offset + 1);
      // readRange 内部已按截止时间重试；这里再补一次整块重试，覆盖
      // 会话刚启动时 TDLib 尚未开始下载该区间的情况。
      let data = await this.session.readRange(offset, length, RANGE_WAIT_MS);
      if ((data === null || data.byteLength === 0) && !this.closed) {
        data = await this.session.readRange(offset, length, RANGE_WAIT_MS);
      }
      if (data === null || data.byteLength === 0) {
        throw new Error(`range ${offset}+${length} unavailable`);
      }
      await connection.send({ data });
      offset += data.byteLength;
    }
    await connection.close();
  }

  private parseRange(request: string): HttpRange | null {
    const lower = request.toLowerCase();
    const marker = '\r\nrange:';
    const rangeIndex = lower.indexOf(marker);
    if (rangeIndex < 0) {
      return { start: 0, end: this.totalSize - 1, partial: false };
    }
    const lineStart = rangeIndex + marker.length;
    const lineEnd = lower.indexOf('\r\n', lineStart);
    const value = request.substring(lineStart, lineEnd >= 0 ? lineEnd : request.length).trim();
    if (!value.toLowerCase().startsWith('bytes=')) {
      return null;
    }
    const spec = value.substring(6).split(',')[0].trim();
    const dash = spec.indexOf('-');
    if (dash < 0) {
      return null;
    }
    const startText = spec.substring(0, dash).trim();
    const endText = spec.substring(dash + 1).trim();
    let start = 0;
    let end = this.totalSize - 1;
    if (startText === '') {
      const suffix = Number(endText);
      if (!Number.isFinite(suffix) || suffix <= 0) {
        return null;
      }
      start = Math.max(0, this.totalSize - Math.floor(suffix));
    } else {
      start = Math.floor(Number(startText));
      if (endText !== '') {
        end = Math.floor(Number(endText));
      }
    }
    if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || start >= this.totalSize || end < start) {
      return null;
    }
    return { start, end: Math.min(end, this.totalSize - 1), partial: true };
  }

  private async sendStatus(connection: socket.TCPSocketConnection, status: string,
    extraHeaders: string = ''): Promise<void> {
    await connection.send({
      data: `HTTP/1.1 ${status}\r\n${extraHeaders}Content-Length: 0\r\nConnection: close\r\n\r\n`
    });
    await connection.close();
  }

  private decodeAscii(data: ArrayBuffer): string {
    const bytes = new Uint8Array(data);
    let text = '';
    for (let i = 0; i < bytes.length; i++) {
      text += String.fromCharCode(bytes[i]);
    }
    return text;
  }
}
