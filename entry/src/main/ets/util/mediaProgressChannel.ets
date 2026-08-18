// 媒体下载进度的旁路通道。
//
// 缩略图路径已经旁路化了（见 mediaThumbChannel），但进度当时留在了行 key
// 里，判断是"另一个独立的重建源，留作下一步"。这个判断是错的：缩略图很小，
// 进度只在下载完成那一刻从 0 跳到 100，而**路径正好在同一个事件里落地**。
// 两者不是两个源，是同一个事件的两个字段——只拿掉路径，重建照旧发生，只是
// 触发字段从 photoPath 换成了 photoProgress，净效果为零。
//
// 真机实测（列表 421 条时）：每次 store notify 要 8–20ms 主线程 JS，其中
// publish 段 6–15ms 就是框架在同步重建那些 key 变了的行；而滑动时进度每秒
// 变 13 次，notify 每秒 10 次。这条通道就是要把那 13 次从 key 里摘出去。
//
// 与 mediaThumbChannel 同构，进程级全局：同一个文件在任何聊天里都是同一份。
const percents: Map<number, number> = new Map();
const subs: Map<number, Set<(percent: number) => void>> = new Map();

// 进度没变就不通知——否则每次 applyFile 都会把订阅者叫醒一遍。
// 与路径通道不同，0 是有意义的值（"还没开始"），不能当空值跳过。
export function publishProgress(fileId: number, percent: number): void {
  if (fileId === 0 || percents.get(fileId) === percent) {
    return;
  }
  percents.set(fileId, percent);
  const listeners = subs.get(fileId);
  if (listeners !== undefined) {
    listeners.forEach((cb: (percent: number) => void): void => cb(percent));
  }
}

export function progressFor(fileId: number): number {
  return percents.get(fileId) ?? 0;
}

export function subscribeProgress(fileId: number, cb: (percent: number) => void): () => void {
  let listeners = subs.get(fileId);
  if (listeners === undefined) {
    listeners = new Set<(percent: number) => void>();
    subs.set(fileId, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current = subs.get(fileId);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(fileId);
      }
    }
  };
}
