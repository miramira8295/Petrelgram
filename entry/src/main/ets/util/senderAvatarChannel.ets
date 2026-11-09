// Side channel for sender avatar paths.
//
// Avatar paths used to be written into every MessageEntry, which put them into
// each row's content signature: the moment a group's avatars finished
// downloading, EVERY row's key changed and the list rebuilt the whole page —
// measured as `change × 31` and a dropped frame ~0.7s after every first entry.
// A row's avatar is the only thing that changed, so the fix is to let the
// avatar view update itself: paths are published here by sender, and the
// bubble's avatar subscribes for its sender and swaps the image in place. No
// entry mutation, no key change, no row rebuild.
//
// Process-global on purpose: a sender's avatar is the same in every chat, so a
// path resolved once serves every store instance and survives page changes.

const paths: Map<string, string> = new Map();
const subs: Map<string, Set<(path: string) => void>> = new Map();

// Mirrors MessageStore.senderKey: 'u<id>' for users, 'c<id>' for chats
// posting as themselves.
export function senderChannelKey(senderId: number, isUser: boolean): string {
  return `${isUser ? 'u' : 'c'}${senderId}`;
}

export function publishSenderAvatar(key: string, path: string): void {
  if (path === '' || paths.get(key) === path) {
    return;
  }
  paths.set(key, path);
  const listeners = subs.get(key);
  if (listeners !== undefined) {
    listeners.forEach((cb: (path: string) => void): void => cb(path));
  }
}

export function senderAvatarFor(key: string): string {
  return paths.get(key) ?? '';
}

export function subscribeSenderAvatar(key: string, cb: (path: string) => void): () => void {
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
