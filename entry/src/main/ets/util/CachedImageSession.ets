import { vp2pxUI } from './uiContext';
import { image } from '@kit.ImageKit';
import {
  cachedPixelMap, cancelPixelMap, loadPixelMap, loadPixelMapSync, PixelHandle, PixelRequest,
  pinPixelMap, pinPixelMapBounded, releasePixelMap, retainPixelMap
} from './pixelCache';
import { isDecodableTarget, sameDecodeTarget, shouldBlankBeforeDecode } from './imageSwap';
import { CachedImageSpec, sameCachedImageDecode } from './cachedImageSpec';
import { logW } from './log';

// Only failed, completed decodes retry. Never duplicate an in-flight task or
// poll every visible image. At most three attempts per source activation.
const DECODE_RETRY_DELAYS: number[] = [150, 600];

// One owner of each displayed bitmap and pending decode. This is deliberately
// not observed: only the component's pixelMap is reactive. Both CachedImage and
// LiveThumbImage render directly, without another custom-component boundary.
export class CachedImageSession {
  private spec: CachedImageSpec | undefined = undefined;
  private active: boolean = false;
  private held: PixelHandle | null = null;
  private heldReq: PixelRequest | null = null;
  private heldKey: string = '';
  private awaiting: PixelRequest | null = null;
  private seq: number = 0;
  private retryTimer: number = -1;
  private retryCount: number = 0;
  private publish: (pixels: image.PixelMap | undefined, ready: boolean, width?: number, height?: number) => void;

  constructor(publish: (pixels: image.PixelMap | undefined, ready: boolean, width?: number, height?: number) => void) {
    this.publish = publish;
  }

  // @Local is reset by V2 reuse, while held still owns a reference. Activation
  // must seed it synchronously even when the input object has not changed.
  activate(spec: CachedImageSpec): void {
    this.active = true;
    this.retryCount = 0;
    this.apply(spec, true);
  }

  update(spec: CachedImageSpec): void {
    this.apply(spec, false);
  }

  recycle(): void {
    this.active = false;
    this.cancelPending();
  }

  dispose(): void {
    this.active = false;
    this.cancelPending();
    this.releaseHeld();
    this.spec = undefined;
    // Teardown must not publish reactive changes into a disappearing subtree.
  }

  private cancelPending(): void {
    this.seq++;
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (this.awaiting !== null) {
      cancelPixelMap(this.awaiting);
      this.awaiting = null;
    }
  }

  private releaseHeld(): void {
    const previous = this.held;
    this.held = null;
    this.heldReq = null;
    this.heldKey = '';
    if (previous !== null) {
      releasePixelMap(previous);
    }
  }

  private sameAsHeld(path: string, width: number, height: number, opaque: boolean): boolean {
    const held = this.heldReq;
    return held !== null && held.opaque === opaque &&
      sameDecodeTarget(held.path, held.width, held.height, path, width, height);
  }

  private swapTo(req: PixelRequest, handle: PixelHandle): void {
    const spec = this.spec;
    if (!this.active || spec === undefined) {
      return;
    }
    const previous = this.held;
    retainPixelMap(handle);
    this.held = handle;
    this.heldReq = req;
    this.heldKey = spec.sourceKey ?? '';
    if (spec.pin === true) {
      pinPixelMap(handle);
    } else if (spec.pinBounded === true) {
      pinPixelMapBounded(req, handle);
    }
    this.publish(handle.pixelMap, true, handle.width, handle.height);
    // Retain/publish the replacement before returning the old reference.
    if (previous !== null) {
      releasePixelMap(previous);
    }
  }

  private apply(spec: CachedImageSpec, reseed: boolean): void {
    const unchanged = sameCachedImageDecode(this.spec, spec);
    // Presentation updates still become current, including pin/on-ready policy
    // used when an already pending decode completes.
    this.spec = spec;
    if (!this.active || (unchanged && !reseed)) {
      return;
    }
    if (!unchanged) { this.retryCount = 0; }
    this.cancelPending();
    if (!isDecodableTarget(spec.path, spec.boxWidth, spec.boxHeight)) {
      this.releaseHeld();
      this.publish(undefined, false);
      return;
    }
    // Reuse must still re-evaluate density and synchronously seed @Local, but
    // an already owned matching bitmap needs no temporary decode request.
    const width: number = vp2pxUI(spec.boxWidth);
    const height: number = vp2pxUI(spec.boxHeight);
    const opaque: boolean = spec.opaque === true;
    if (shouldBlankBeforeDecode(this.heldReq !== null ? this.heldReq.path : '', spec.path,
      this.heldKey, spec.sourceKey ?? '')) {
      this.releaseHeld();
    }
    if (this.sameAsHeld(spec.path, width, height, opaque) && this.held !== null) {
      this.publish(this.held.pixelMap, true, this.held.width, this.held.height);
      return;
    }
    const req: PixelRequest = { path: spec.path, width: width, height: height, opaque: opaque };
    const hit = cachedPixelMap(req);
    if (hit !== undefined) {
      this.swapTo(req, hit);
      return;
    }
    // syncSmall is the explicit cache-miss decode policy; syncDisplay remains
    // solely an Image attribute for an already decoded PixelMap.
    if (spec.syncSmall === true) {
      const sync = loadPixelMapSync(req);
      if (sync !== undefined) {
        this.swapTo(req, sync);
        return;
      }
    }
    // Publish only the final synchronous result: a cache hit must not first
    // invalidate the native Image with an empty bitmap. On a miss, clear a
    // different source before awaiting, or reseed the owned same-source image.
    if (this.held === null) {
      this.publish(undefined, false);
    } else if (reseed) {
      this.publish(this.held.pixelMap, false, this.held.width, this.held.height);
    }
    const token = this.seq;
    this.awaiting = req;
    loadPixelMap(req).then((handle: PixelHandle | undefined): void => {
      if (token !== this.seq || !this.active) {
        return;
      }
      this.awaiting = null;
      if (handle !== undefined) {
        this.swapTo(req, handle);
      } else {
        this.retryFailedDecode(token, req);
      }
    });
  }

  private retryFailedDecode(token: number, req: PixelRequest): void {
    if (!this.active || token !== this.seq) { return; }
    if (this.retryCount >= DECODE_RETRY_DELAYS.length) {
      // No file path/message content in diagnostics. One warning per exhausted
      // activation, rather than repeated warnings on every render.
      logW(`ImageDecode: retries exhausted, target=${req.width}x${req.height}`);
      return;
    }
    const delay: number = DECODE_RETRY_DELAYS[this.retryCount++];
    this.retryTimer = setTimeout((): void => {
      if (!this.active || token !== this.seq) { return; }
      this.retryTimer = -1;
      const current = this.spec;
      if (this.active && token === this.seq && current !== undefined) {
        this.apply(current, true);
      }
    }, delay);
  }
}
