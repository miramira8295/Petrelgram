// UI-free ownership hooks for navigation/account teardown.
export interface VideoPlaybackSnapshot {
  positionMs: number;
  speedIndex: number;
  playing: boolean;
}

export interface VideoPlaybackControls {
  snapshot: () => VideoPlaybackSnapshot | null;
  stop: () => void;
  toggle: () => void;
}

interface FloatingVideoHooks {
  close: () => void;
  collapse: () => boolean;
}

let activeHooks: FloatingVideoHooks | null = null;

export function registerFloatingVideo(close: () => void, collapse: () => boolean): () => void {
  const hooks: FloatingVideoHooks = { close: close, collapse: collapse };
  activeHooks = hooks;
  return (): void => { if (activeHooks === hooks) { activeHooks = null; } };
}

export function closeFloatingVideo(): void { activeHooks?.close(); }
export function collapseFloatingVideo(): boolean { return activeHooks?.collapse() ?? false; }

export function validVideoSnapshot(snapshot: VideoPlaybackSnapshot | null): boolean {
  return snapshot !== null && Number.isFinite(snapshot.positionMs) && snapshot.positionMs >= 0 &&
    Number.isInteger(snapshot.speedIndex) && snapshot.speedIndex >= 0 && snapshot.speedIndex < 4;
}

// Mount a dormant host first; failed mounting must leave playback untouched.
export function handoffVideoPlayback(
  controls: VideoPlaybackControls,
  mount: (snapshot: VideoPlaybackSnapshot) => boolean,
  activate: () => void
): boolean {
  const snapshot = controls.snapshot();
  if (!validVideoSnapshot(snapshot) || snapshot === null || !mount(snapshot)) { return false; }
  controls.stop();
  activate();
  return true;
}
