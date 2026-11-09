// 媒体缩略图路径的旁路通道。
//
// 路径原本写在 MessageEntry 里、并进了 collapseAlbums 的行 key：一张缩略图
// 落地就改一次 key，LazyForEach 按 key 比对，于是整行重建——一条 6 格相册
// 就重建 6 次，把同行的其它格子、文本、反应全部一起重建。实测这就是媒体多
// 的聊天滑动卡顿的主要成本（掉帧数与重建次数逐秒同步起伏）。
//
// 头像早先踩过同一个坑并已治好（见 senderAvatarChannel）：路径不进 key，
// 改由通道直达那个图片组件，组件自己换图。这里把同一套办法用到媒体上。
//
// 进程级全局：同一个文件在任何聊天里都是同一份，解析一次全局可用，也能
// 跨页面存活。
const paths: Map<number, string> = new Map();
const subs: Map<number, Set<(path: string) => void>> = new Map();

// 空路径不发布：那代表"还没下好"，不是一次内容更新。同理，路径没变也不
// 通知——否则每次 applyFile 都会把订阅者叫醒一遍。
export function publishThumbPath(fileId: number, path: string): void {
  if (fileId === 0 || path === '' || paths.get(fileId) === path) {
    return;
  }
  paths.set(fileId, path);
  const listeners = subs.get(fileId);
  if (listeners !== undefined) {
    listeners.forEach((cb: (path: string) => void): void => cb(path));
  }
}

export function thumbPathFor(fileId: number): string {
  return paths.get(fileId) ?? '';
}

export function subscribeThumbPath(fileId: number, cb: (path: string) => void): () => void {
  let listeners = subs.get(fileId);
  if (listeners === undefined) {
    listeners = new Set<(path: string) => void>();
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
