// Immutable input for one decoded image. Keep callbacks outside this value;
// changing presentation must not restart an in-flight decode.
export interface CachedImageSpec {
  path: string;
  boxWidth: number;
  boxHeight: number;
  radius?: number;
  fit?: ImageFit;
  pin?: boolean;
  pinBounded?: boolean;
  syncSmall?: boolean;
  syncDisplay?: boolean;
  sourceKey?: string;
  opaque?: boolean;
  backdrop?: string;
  backdropImage?: string;
  deferBackdropOnScroll?: boolean;
}

export function sameCachedImageDecode(a: CachedImageSpec | undefined, b: CachedImageSpec): boolean {
  return a !== undefined && a.path === b.path && a.boxWidth === b.boxWidth &&
    a.boxHeight === b.boxHeight && a.sourceKey === b.sourceKey &&
    a.opaque === b.opaque && a.syncSmall === b.syncSmall;
}

// One entry per live thumbnail, bounded by its component lifetime. Parent
// selection/progress updates may replace their spec without changing the image.
export class CachedImageSpecCache {
  private previous: CachedImageSpec | undefined = undefined;

  prepare(next: CachedImageSpec): CachedImageSpec {
    const previous = this.previous;
    if (previous !== undefined && sameCachedImageDecode(previous, next) &&
      previous.radius === next.radius && previous.fit === next.fit &&
      previous.pin === next.pin && previous.pinBounded === next.pinBounded &&
      previous.syncDisplay === next.syncDisplay && previous.backdrop === next.backdrop &&
      previous.backdropImage === next.backdropImage &&
      previous.deferBackdropOnScroll === next.deferBackdropOnScroll) {
      return previous;
    }
    this.previous = next;
    return next;
  }
}
