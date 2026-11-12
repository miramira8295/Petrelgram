import { image } from '@kit.ImageKit';

// Presentation only. CachedImageSession remains the sole PixelHandle owner.
// Path changes within one source need no UI update until pixels/visibility change.
export interface LiveThumbDisplayState {
  readonly hasPath: boolean;
  readonly pixels: image.PixelMap | undefined;
}

export const EMPTY_LIVE_THUMB_DISPLAY: LiveThumbDisplayState = { hasPath: false, pixels: undefined };

export function liveThumbDisplayState(previous: LiveThumbDisplayState, hasPath: boolean,
  pixels: image.PixelMap | undefined): LiveThumbDisplayState {
  if (previous.hasPath === hasPath && previous.pixels === pixels) { return previous; }
  if (!hasPath && pixels === undefined) { return EMPTY_LIVE_THUMB_DISPLAY; }
  return { hasPath, pixels };
}
