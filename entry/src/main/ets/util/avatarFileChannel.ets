// 头像文件的旁路通道，按 **file id** 订阅（issue #211 第 2 条）。
//
// 【为什么不能用 senderAvatarChannel】那条按 `senderChannelKey(senderId, isUser)`
// 订阅，而且只由 MessageStore 在处理消息发送者/评论者头像时发布。@ 候选人来自
// searchChatMembers，**未必在本会话发过言**，那条通道里根本没有他。
//
// 【为什么 FileService 只能按 file id 发】它拿到的是 updateFile，里面只有文件
// id，没有"这是谁的头像"。谁订阅谁自己知道自己要哪个 id。
//
// 进程级全局：同一个文件在任何页面都是同一份。空路径不发布——那代表"还没下好"，
// 不是一次内容更新；路径没变也不发，否则每条 updateFile 都会把订阅者叫醒一遍
// （同 util/mediaThumbChannel 的两条规矩）。
const paths: Map<number, string> = new Map();
const subs: Map<number, Set<(path: string) => void>> = new Map();

export function publishAvatarFile(fileId: number, path: string): void {
  if (fileId === 0 || path === '' || paths.get(fileId) === path) {
    return;
  }
  paths.set(fileId, path);
  const listeners = subs.get(fileId);
  if (listeners !== undefined) {
    listeners.forEach((cb: (path: string) => void): void => cb(path));
  }
}

export function avatarFilePathFor(fileId: number): string {
  return paths.get(fileId) ?? '';
}

export function subscribeAvatarFile(fileId: number, cb: (path: string) => void): () => void {
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

// 仅供单测：模块级 Map 会跨用例串味。
export function resetAvatarFileChannelForTest(): void {
  paths.clear();
  subs.clear();
}
