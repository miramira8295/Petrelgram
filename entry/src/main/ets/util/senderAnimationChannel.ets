// 群聊气泡左侧动态头像的进程级通道（issue #140，2026-09-17）。
//
// 和 senderAvatarChannel（静态头像）同一个道理：按发送者广播，气泡里的头像自己订阅、
// 原地换内容，不改消息条目、不动行 key。键也沿用 senderChannelKey（u<id> / c<id>）。
//
// 多出来的是「取」的状态：动态头像要先取完整资料再下载，一个人在一屏里出现十几次，
// 这一趟只该发一次。
// - loading：已经有人在取，别人不要再发；
// - ready：路径已到；
// - failed：没取到（没网、没有动画、超时），冷却 SENDER_ANIMATION_RETRY_MS 后才许再试；
// - broken：文件到手但播放器放不了——再取也是同一个文件，换头像（invalidate）之前不再试。
//
// claim 发一枚令牌，resolve 必须带着它回来：换头像时 invalidate 会作废令牌，
// 正在路上的旧请求回来就不会把旧视频发出去。

export const SENDER_ANIMATION_RETRY_MS: number = 60 * 1000;

type SenderAnimationState = 'loading' | 'ready' | 'failed' | 'broken';

interface SenderAnimationRecord {
  state: SenderAnimationState;
  token: number;
  path: string;
  at: number;
}

const records: Map<string, SenderAnimationRecord> = new Map();
const subs: Map<string, Set<(path: string) => void>> = new Map();
let nextToken: number = 1;

function publish(key: string, path: string): void {
  const listeners = subs.get(key);
  if (listeners === undefined) {
    return;
  }
  // 回调里可能退订（组件据此卸掉播放层），先拷一份再遍历。
  Array.from(listeners).forEach((cb: (path: string) => void): void => cb(path));
}

export function senderAnimationFor(key: string): string {
  const rec = records.get(key);
  return rec !== undefined && rec.state === 'ready' ? rec.path : '';
}

export function subscribeSenderAnimation(key: string, cb: (path: string) => void): () => void {
  let listeners = subs.get(key);
  if (listeners === undefined) {
    listeners = new Set<(path: string) => void>();
    subs.set(key, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current = subs.get(key);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(key);
      }
    }
  };
}

// 返回令牌（>0）表示调用方该去取；0 表示不必（在取、已到、冷却中或放不了）。
export function claimSenderAnimation(key: string, nowMs: number): number {
  const rec = records.get(key);
  if (rec !== undefined) {
    if (rec.state === 'loading' || rec.state === 'ready' || rec.state === 'broken') {
      return 0;
    }
    if (nowMs - rec.at < SENDER_ANIMATION_RETRY_MS) {
      return 0;
    }
  }
  const token: number = nextToken++;
  records.set(key, { state: 'loading', token: token, path: '', at: nowMs });
  return token;
}

// path 为空 = 没取到。令牌过期（期间换了头像）或已经落定的结果一律丢弃。
export function resolveSenderAnimation(key: string, token: number, path: string, nowMs: number): void {
  const rec = records.get(key);
  if (rec === undefined || rec.token !== token || rec.state !== 'loading') {
    return;
  }
  if (path === '') {
    records.set(key, { state: 'failed', token: token, path: '', at: nowMs });
    return;
  }
  records.set(key, { state: 'ready', token: token, path: path, at: nowMs });
  publish(key, path);
}

export function markSenderAnimationBroken(key: string): void {
  const rec = records.get(key);
  const hadPath: boolean = rec !== undefined && rec.state === 'ready';
  records.set(key, { state: 'broken', token: rec !== undefined ? rec.token : 0, path: '', at: 0 });
  if (hadPath) {
    publish(key, '');
  }
}

// 头像换了：忘掉一切，已经在放的撤下来。
export function invalidateSenderAnimation(key: string): void {
  const rec = records.get(key);
  if (rec === undefined) {
    return;
  }
  records.delete(key);
  if (rec.state === 'ready') {
    publish(key, '');
  }
}

// ---- 仅供单测 ----
export function resetSenderAnimationForTest(): void {
  records.clear();
  subs.clear();
}
