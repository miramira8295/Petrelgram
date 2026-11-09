// 持久化由 AppSettings 负责；这里只向已挂载的预取器广播开关变化。
export const KEY_VIDEO_AUTO_PRELOAD: string = 'videoAutoPreload';
const listeners: Set<(enabled: boolean) => void> = new Set();

export function publishVideoPreload(enabled: boolean): void {
  listeners.forEach((listener: (enabled: boolean) => void): void => listener(enabled));
}

export function subscribeVideoPreload(listener: (enabled: boolean) => void): () => void {
  listeners.add(listener);
  listener(AppStorage.get<boolean>(KEY_VIDEO_AUTO_PRELOAD) ?? true);
  return (): void => { listeners.delete(listener); };
}
