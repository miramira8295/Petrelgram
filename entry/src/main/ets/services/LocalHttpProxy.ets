import { socket } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { logE, logW } from '../util/log';

// 本地 HTTP 代理 → SOCKS5 转发。
//
// 【为什么需要它】ArkWeb（小程序 / 内置浏览器）用的是自己的网络栈，读不到 TDLib
// 配的代理；而 HarmonyOS 的应用级代理接口 connection.setAppHttpProxy 只支持
// HTTP(S)，喂不进 SOCKS5。所以这里在本机起一个最小的 HTTP 代理，把 CONNECT /
// 绝对 URI 请求接住，转成 SOCKS5 握手打到用户的代理端口上，再把字节双向搬运。
// ArkWeb 那边只需要 setAppHttpProxy 指向本机端口就行。
//
// 【边界】
//  · 只处理 CONNECT（https）与绝对 URI 的 http 请求，够 WebView 用
//  · 不做缓存、不做鉴权（本机回环，不需要）
//  · 吞吐受 ArkTS 字节泵限制：静态资源没问题，大文件/视频会慢
//  · 生命周期由 start/stop 管，必须和代理开关一一对应，漏停就会一直占端口

const BRIDGE_PORT: number = 7891;

interface BridgePeer {
  client: socket.TCPSocketConnection | null;
  remote: socket.TCPSocketInstance | null;
  closed: boolean;
}

let server: socket.TCPSocketServerInstance | null = null;
let running: boolean = false;
let targetHost: string = '';
let targetPort: number = 0;

function closePeer(peer: BridgePeer): void {
  if (peer.closed) {
    return;
  }
  peer.closed = true;
  if (peer.remote !== null) {
    peer.remote.close().catch((): void => {});
    peer.remote = null;
  }
  if (peer.client !== null) {
    peer.client.close().catch((): void => {});
    peer.client = null;
  }
}

// SOCKS5 握手：05 01 00（无认证）→ 05 00 → 05 01 00 03 len host port → 05 00 00 01 ...
function socks5Connect(host: string, port: number): Promise<socket.TCPSocketInstance> {
  const remote: socket.TCPSocketInstance = socket.constructTCPSocketInstance();
  return new Promise<socket.TCPSocketInstance>((resolve, reject) => {
    let stage: number = 0;
    let settled: boolean = false;
    const fail = (why: string): void => {
      if (settled) { return; }
      settled = true;
      remote.close().catch((): void => {});
      reject(new Error(why));
    };
    remote.on('message', (info: socket.SocketMessageInfo): void => {
      const buf = new Uint8Array(info.message);
      if (stage === 0) {
        if (buf.length < 2 || buf[0] !== 0x05 || buf[1] !== 0x00) {
          fail('socks5 greeting rejected');
          return;
        }
        stage = 1;
        const name = new Uint8Array([...host].map((c: string): number => c.charCodeAt(0) & 0xff));
        const req = new Uint8Array(7 + name.length);
        req.set([0x05, 0x01, 0x00, 0x03, name.length], 0);
        req.set(name, 5);
        req[5 + name.length] = (port >> 8) & 0xff;
        req[6 + name.length] = port & 0xff;
        remote.send({ data: req.buffer as ArrayBuffer }).catch((): void => { fail('socks5 send failed'); });
        return;
      }
      if (stage === 1) {
        if (buf.length < 2 || buf[1] !== 0x00) {
          fail('socks5 connect rejected');
          return;
        }
        stage = 2;
        settled = true;
        resolve(remote);
      }
    });
    remote.on('error', (): void => { fail('socks5 socket error'); });
    remote.connect({ address: { address: targetHost, port: targetPort }, timeout: 8000 })
      .then((): void => {
        remote.send({ data: new Uint8Array([0x05, 0x01, 0x00]).buffer as ArrayBuffer })
          .catch((): void => { fail('socks5 hello failed'); });
      })
      .catch((): void => { fail('socks5 dial failed'); });
  });
}

// 从 HTTP 请求头里取目标：CONNECT host:port 或 GET http://host/path
function parseTarget(head: string): { host: string; port: number } | null {
  const firstLine: string = head.split('\r\n')[0];
  const parts: string[] = firstLine.split(' ');
  if (parts.length < 2) {
    return null;
  }
  const method: string = parts[0];
  const url: string = parts[1];
  if (method === 'CONNECT') {
    const idx: number = url.lastIndexOf(':');
    if (idx <= 0) { return null; }
    return { host: url.substring(0, idx), port: Number(url.substring(idx + 1)) };
  }
  const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^/:]+)(?::(\d+))?/);
  if (match === null) {
    return null;
  }
  return { host: match[1], port: match[2] !== undefined ? Number(match[2]) : 80 };
}

function pump(client: socket.TCPSocketConnection, remote: socket.TCPSocketInstance, peer: BridgePeer): void {
  client.on('message', (info: socket.SocketMessageInfo): void => {
    if (peer.closed) { return; }
    remote.send({ data: info.message }).catch((): void => { closePeer(peer); });
  });
  remote.on('message', (info: socket.SocketMessageInfo): void => {
    if (peer.closed) { return; }
    client.send({ data: info.message }).catch((): void => { closePeer(peer); });
  });
  client.on('close', (): void => { closePeer(peer); });
  remote.on('close', (): void => { closePeer(peer); });
  remote.on('error', (): void => { closePeer(peer); });
}

/** 代理是否在跑（设置页用来显示状态）。 */
export function localProxyRunning(): boolean {
  return running;
}

/**
 * 启动本地转发并把它指给 ArkWeb。
 * host/port 是用户配置的 SOCKS5 代理地址。
 */
export async function startLocalProxy(host: string, port: number): Promise<boolean> {
  if (running) {
    return true;
  }
  targetHost = host;
  targetPort = port;
  try {
    const srv: socket.TCPSocketServerInstance = socket.constructTCPSocketServerInstance();
    srv.on('connect', (client: socket.TCPSocketConnection): void => {
      const peer: BridgePeer = { client, remote: null, closed: false };
      let head: string = '';
      let headDone: boolean = false;
      client.on('message', (info: socket.SocketMessageInfo): void => {
        if (headDone || peer.closed) { return; }
        head += String.fromCharCode(...new Uint8Array(info.message));
        if (head.indexOf('\r\n\r\n') < 0) {
          if (head.length > 8192) { closePeer(peer); }
          return;
        }
        headDone = true;
        const target = parseTarget(head);
        if (target === null) {
          closePeer(peer);
          return;
        }
        targetHost = target.host;
        targetPort = target.port;
        socks5Connect(target.host, target.port).then((remote: socket.TCPSocketInstance): void => {
          peer.remote = remote;
          const isConnect: boolean = head.startsWith('CONNECT ');
          if (isConnect) {
            client.send({ data: new TextEncoder().encode('HTTP/1.1 200 Connection Established\r\n\r\n').buffer as ArrayBuffer })
              .catch((): void => { closePeer(peer); });
          } else {
            remote.send({ data: new TextEncoder().encode(head).buffer as ArrayBuffer })
              .catch((): void => { closePeer(peer); });
          }
          pump(client, remote, peer);
        }).catch((e: Error): void => {
          logW(`[LocalProxy] socks5 failed: ${e.message}`);
          closePeer(peer);
        });
      });
      client.on('close', (): void => { closePeer(peer); });
    });
    await srv.listen({ address: '127.0.0.1', port: BRIDGE_PORT });
    server = srv;
    running = true;
    // ArkWeb 走本机这一跳。
    try {
      connection.setAppHttpProxy({ host: '127.0.0.1', port: BRIDGE_PORT });
    } catch (e) {
      logW(`[LocalProxy] setAppHttpProxy failed: ${(e as Error).message}`);
    }
    logW(`[LocalProxy] started 127.0.0.1:${BRIDGE_PORT} -> ${host}:${port}`);
    return true;
  } catch (e) {
    logE(`[LocalProxy] start failed: ${(e as Error).message}`);
    return false;
  }
}

export function stopLocalProxy(): void {
  if (!running) {
    return;
  }
  running = false;
  try {
    connection.setAppHttpProxy({ host: '', port: 0 });
  } catch (e) {
    logW(`[LocalProxy] clear failed: ${(e as Error).message}`);
  }
  if (server !== null) {
    server.close().catch((): void => {});
    server = null;
  }
  logW('[LocalProxy] stopped');
}
