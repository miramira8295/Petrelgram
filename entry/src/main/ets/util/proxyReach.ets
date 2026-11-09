import { connection, socket } from '@kit.NetworkKit';
import { KEY_PREFER_IPV6 } from '../store/AppSettings';
import { isIpLiteral } from './proxyLogic';
import { netFamilyOf, NET_FAMILY_IPV4, NET_FAMILY_IPV6, stripIpv6Brackets } from './ipFamily';

export interface ProxyReachNetwork {
  resolve(host: string): Promise<connection.NetAddress[]>;
  localFamilies(): Promise<number[]>;
}

export interface ProxyReachSocket {
  connect(options: socket.TCPConnectOptions): Promise<void>;
  close(): Promise<void>;
}

export interface ProxyReachEnvironment {
  getNetwork(): Promise<ProxyReachNetwork>;
  createSocket(): ProxyReachSocket;
  preferIpv6(): boolean;
  now(): number;
  setTimeout(callback: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

class SystemReachNetwork implements ProxyReachNetwork {
  private handle: connection.NetHandle;
  constructor(handle: connection.NetHandle) { this.handle = handle; }

  resolve(host: string): Promise<connection.NetAddress[]> {
    return this.handle.getAddressesByName(host);
  }

  async localFamilies(): Promise<number[]> {
    const props = await connection.getConnectionProperties(this.handle);
    return props.linkAddresses.map((link: connection.LinkAddress): number => link.address.family ?? 0);
  }
}

class SystemReachSocket implements ProxyReachSocket {
  private tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
  connect(options: socket.TCPConnectOptions): Promise<void> { return this.tcp.connect(options); }
  close(): Promise<void> { return this.tcp.close(); }
}

class SystemReachEnvironment implements ProxyReachEnvironment {
  async getNetwork(): Promise<ProxyReachNetwork> {
    return new SystemReachNetwork(await connection.getDefaultNet());
  }
  createSocket(): ProxyReachSocket { return new SystemReachSocket(); }
  preferIpv6(): boolean { return AppStorage.get<boolean>(KEY_PREFER_IPV6) ?? false; }
  now(): number { return Date.now(); }
  setTimeout(callback: () => void, ms: number): number { return setTimeout(callback, ms); }
  clearTimeout(id: number): void { clearTimeout(id); }
}

function withinDeadline<T>(operation: Promise<T>, deadline: number, env: ProxyReachEnvironment): Promise<T> {
  return new Promise<T>((resolve, reject): void => {
    const timer = env.setTimeout((): void => reject(new Error('proxy reach timeout')),
      Math.max(0, deadline - env.now()));
    operation.then((value: T): void => {
      env.clearTimeout(timer);
      if (env.now() >= deadline) { reject(new Error('proxy reach timeout')); }
      else { resolve(value); }
    }, (error: Error): void => {
      env.clearTimeout(timer);
      reject(error);
    });
  });
}

function closeSocket(tcp: ProxyReachSocket): void {
  // Cleanup must not extend the measurement deadline, including a stuck close.
  try { tcp.close().catch((): void => {}); } catch (_caught) {}
}

function orderedTargets(
  addresses: connection.NetAddress[], port: number, preferIpv6: boolean
): socket.NetAddress[] {
  const preferred: socket.NetAddress[] = [];
  const other: socket.NetAddress[] = [];
  const seen: Set<string> = new Set();
  const wanted = preferIpv6 ? NET_FAMILY_IPV6 : NET_FAMILY_IPV4;
  for (const entry of addresses) {
    const bare = stripIpv6Brackets(entry.address);
    if (!isIpLiteral(bare) || seen.has(bare)) { continue; }
    seen.add(bare);
    const family = netFamilyOf(bare);
    const target: socket.NetAddress = { address: bare, port: port, family: family };
    if (family === wanted) { preferred.push(target); } else { other.push(target); }
  }
  // Give the other family an early chance even when DNS has many A/AAAA records.
  const result: socket.NetAddress[] = [];
  for (let i = 0; i < Math.max(preferred.length, other.length); i++) {
    if (i < preferred.length) { result.push(preferred[i]); }
    if (i < other.length) { result.push(other[i]); }
  }
  return result;
}

// Only the successful TCP handshake is reported as ≈ms (issue #31), not DNS
// or previous failed attempts. It does not establish Telegram connectivity.
// DNS, optional local capability probing, and all connects share one deadline.
export async function measureProxyConnectMs(
  host: string, port: number, timeoutMs: number, environment?: ProxyReachEnvironment
): Promise<number> {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) { throw new Error('invalid proxy reach timeout'); }
  const env = environment ?? new SystemReachEnvironment();
  const deadline = env.now() + timeoutMs;
  const bare = stripIpv6Brackets(host);
  let targets: socket.NetAddress[] = [{ address: bare, port: port, family: netFamilyOf(bare) }];
  if (!isIpLiteral(bare)) {
    const net = await withinDeadline(env.getNetwork(), deadline, env);
    const addresses = await withinDeadline(net.resolve(bare), deadline, env);
    if (addresses.length === 0) { throw new Error('dns: no proxy address'); }
    let families: number[] = [];
    try {
      // Capability lookup is optional; failure/unknown must not block DNS results.
      families = await withinDeadline(net.localFamilies(), Math.min(deadline, env.now() + 250), env);
    } catch (_caught) {}
    const ipv6Only = families.indexOf(NET_FAMILY_IPV6) >= 0 && families.indexOf(NET_FAMILY_IPV4) < 0;
    targets = orderedTargets(addresses, port, env.preferIpv6() || ipv6Only);
  }
  let lastError: Error = new Error('dns: no usable proxy address');
  for (let i = 0; i < targets.length; i++) {
    const remaining = deadline - env.now();
    if (remaining <= 0) { throw new Error('proxy reach timeout'); }
    // Reserve half the remaining budget for fallback; the final address gets all.
    const allowance = targets.length - i > 1 ? Math.max(1, Math.floor(remaining / 2)) : remaining;
    const tcp = env.createSocket();
    const startedAt = env.now();
    let finished = false;
    try {
      const connected = tcp.connect({ address: targets[i], timeout: allowance }).then((): void => {
        // Some native implementations may complete after a timed-out close.
        if (finished) { closeSocket(tcp); }
      });
      await withinDeadline(connected, Math.min(deadline, startedAt + allowance), env);
      return Math.max(0, env.now() - startedAt);
    } catch (caught) {
      lastError = caught as Error;
    } finally {
      finished = true;
      closeSocket(tcp);
    }
  }
  throw lastError;
}
