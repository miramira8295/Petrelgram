// 群成员身份标签的旁路通道（气泡里发送者名字旁边那一枚）。
//
// 和 senderAvatarChannel 同一套路子，理由也一样：标签是异步取回来的
// （getChatAdministrators 要一次网络往返），而消息行早就渲染完了。若把标签
// 写进 MessageEntry，它就进了行的内容签名——名单一到货，**整页每一行的 key
// 都会变**，列表整体重建。标签只是名字旁边多两个字，不该有这个代价。
//
// 与头像通道的唯一区别：头像全局通用（同一个人在哪都是那张脸），身份却是
// **按群**的——同一个人在 A 群是管理员、在 B 群是普通成员。所以 key 里必须
// 带上 chatId。

const labels: Map<string, string> = new Map();
const subs: Map<string, Set<(label: string) => void>> = new Map();

export function senderRoleKey(chatId: number, userId: number): string {
  return `${chatId}:${userId}`;
}

export function publishSenderRole(key: string, label: string): void {
  if (labels.get(key) === label) {
    return;
  }
  labels.set(key, label);
  const listeners = subs.get(key);
  if (listeners !== undefined) {
    listeners.forEach((cb: (label: string) => void): void => cb(label));
  }
}

export function senderRoleFor(key: string): string {
  return labels.get(key) ?? '';
}

// 换群或退出登录时清掉：身份跟着群走，留着会在别的会话里错标。
export function clearSenderRoles(chatId: number): void {
  const prefix: string = `${chatId}:`;
  const stale: string[] = [];
  labels.forEach((_v: string, k: string): void => {
    if (k.startsWith(prefix)) {
      stale.push(k);
    }
  });
  for (const k of stale) {
    labels.delete(k);
    const listeners = subs.get(k);
    if (listeners !== undefined) {
      listeners.forEach((cb: (label: string) => void): void => cb(''));
    }
  }
}

export function subscribeSenderRole(key: string, cb: (label: string) => void): () => void {
  let listeners = subs.get(key);
  if (listeners === undefined) {
    listeners = new Set<(label: string) => void>();
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
