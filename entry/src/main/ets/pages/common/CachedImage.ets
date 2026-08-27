import { image } from '@kit.ImageKit';
import {
  cachedPixelMap, cancelPixelMap, loadPixelMap, PixelHandle, PixelRequest,
  pinPixelMap, releasePixelMap, retainPixelMap
} from '../../util/pixelCache';
import {
  isDecodableTarget, sameDecodeTarget, shouldBlankBeforeDecode
} from '../../util/imageSwap';
import { reuseParam } from '../../util/reuseParams';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId
} from '../../util/nextFrameQueue';

// An Image fed from the decoded-PixelMap cache instead of a file path.
//
// Everything about the lifetime lives here so callers stay a one-liner: the
// decode is async, the cache is reference counted, and a reused row has to let
// go of the old bitmap before it takes the new one. Getting any of that wrong
// frees pixels that are still on screen, so it is deliberately not something
// each call site re-implements.
//
// Not @Reusable: path/size changes are handled by @Watch, while normal row
// teardown releases the retained PixelMap through aboutToDisappear. Keeping
// image ownership out of ArkUI's reuse pool also avoids nested cache lifetimes.
@Component
export struct CachedImage {
  @Prop @Watch('onSourceChanged') path: string;
  @Prop @Watch('onSourceChanged') boxWidth: number;
  @Prop @Watch('onSourceChanged') boxHeight: number;
  @Prop radius: number = 0;
  @Prop fit: ImageFit = ImageFit.Cover;
  // Keep the decoded bitmap for the whole session (see pinPixelMap).
  @Prop pin: boolean = false;
  // 位图第一次真正交给 Image 的那一刻。调用方据此决定什么时候撤掉自己的兜底层
  // ——解码失败时这个回调永远不来，兜底层就一直留着（issue #90）。
  onReady: () => void = (): void => {};
  @State pixelMap: image.PixelMap | undefined = undefined;
  // The handle currently retained, so it can be released even after path has
  // already been overwritten by a reuse — and even if the LRU has since
  // dropped it from the map.
  private held: PixelHandle | null = null;
  private heldReq: PixelRequest | null = null;
  // The decode currently waited on, so it can be cancelled by request rather
  // than merely ignored when it lands.
  private awaiting: PixelRequest | null = null;
  // Guards against an out-of-order decode landing after a newer one.
  private seq: number = 0;
  // This instance's slot in the shared next-frame queue (util/nextFrameQueue).
  // Undecorated members survive reuse untouched, so the id stays stable for the
  // life of the instance — that is what lets a later reuse override an earlier one.
  private frameOwnerId: number = nextFrameOwnerId();

  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.drop();
    // A stale re-check would start a decode for a component that is gone, and
    // retain a PixelMap nothing will ever release.
    cancelNextFrame(this.frameOwnerId);
  }

  // Recycling cancels work in flight but keeps a bitmap that is already
  // decoded. Dropping it here was a real bug: a pooled row reused with the
  // same photo gets no @Watch (the values never changed), so nothing reloaded
  // it and the cell stayed blank.
  aboutToRecycle(): void {
    this.cancelPending();
    // Pending work in flight was just cancelled; do not let the previous reuse's
    // scheduled re-check undo that. The next reuse enqueues again.
    cancelNextFrame(this.frameOwnerId);
  }

  aboutToReuse(params: Record<string, Object>): void {
    // The bitmap is NOT blanked here: doing that left the row empty until the
    // new decode landed, and the viewer's close animation shrinks back onto
    // this cell — onto nothing.
    //
    // The re-check is scheduled rather than done now for two reasons. @Prop
    // refreshes land after this callback, so the new source is not readable
    // yet; and when a row is reused with the SAME photo, @Watch never fires,
    // so nothing else would run. That combination is what left a permanent
    // blank whenever a row was recycled while its decode was still in flight:
    // the decode got cancelled and no one ever asked again. start() is
    // idempotent, so an unnecessary call costs nothing.
    // reuseParam：params 是 {} 还是 undefined 都安全（P3 批 2 第 1 项，见
    // util/reuseParams.ets）。取不到就跳过 drop，等同于原有的「不判定」分支，
    // 下面的 setTimeout 仍然无条件跑。
    const nextPath: string | undefined = reuseParam(params, 'path') as string | undefined;
    if (nextPath !== undefined && this.heldReq !== null && this.heldReq.path !== nextPath) {
      // A recycled avatar/thumbnail must never display the previous row while
      // the new decode is pending. Same-source reuse still keeps its bitmap.
      this.drop();
    }
    // Merged into the shared queue; semantics unchanged (util/nextFrameQueue).
    enqueueNextFrame(this.frameOwnerId, (): void => { this.start(); });
  }

  private request(): PixelRequest {
    return {
      path: this.path,
      width: vp2px(this.boxWidth),
      height: vp2px(this.boxHeight)
    };
  }

  // Stop waiting for a decode that has not arrived. If this was the last
  // component interested and the decode never started, the work is skipped.
  private cancelPending(): void {
    this.seq++;
    if (this.awaiting !== null) {
      cancelPixelMap(this.awaiting);
      this.awaiting = null;
    }
  }

  private drop(): void {
    this.cancelPending();
    if (this.held !== null) {
      releasePixelMap(this.held);
      this.held = null;
      this.heldReq = null;
    }
    this.pixelMap = undefined;
  }

  private onSourceChanged(): void {
    this.start();
  }

  // 判定本身在 util/imageSwap（纯函数 + 单测）。这里只负责把当前握着的那张
  // 摊平成参数。
  private sameAsHeld(req: PixelRequest): boolean {
    const held = this.heldReq;
    if (held === null) {
      return false;
    }
    return sameDecodeTarget(held.path, held.width, held.height,
      req.path, req.width, req.height);
  }

  // The old bitmap stays on screen until the new one is in hand — no blank
  // frame between two valid images.
  private swapTo(req: PixelRequest, handle: PixelHandle): void {
    const previous = this.held;
    retainPixelMap(handle);
    this.held = handle;
    this.heldReq = req;
    this.pixelMap = handle.pixelMap;
    this.onReady();
    if (this.pin) {
      pinPixelMap(handle);
    }
    if (previous !== null) {
      releasePixelMap(previous);
    }
  }

  private start(): void {
    if (!isDecodableTarget(this.path, this.boxWidth, this.boxHeight)) {
      this.drop();
      return;
    }
    const req = this.request();
    // 只在换了**源文件**时才提前清空：复用出来的行绝不能继续画上一条消息的图。
    //
    // 同一个源文件仅仅是解码目标尺寸变了（photoWidth/photoHeight 这类元数据晚到，
    // boxHeight 先给错后修正）时**不再清空**——老位图和新位图画的是同一张图,
    // 中间那段空窗纯属白送，用户看到的就是图闪一下。新位图由 swapTo 到手再换。
    if (shouldBlankBeforeDecode(this.heldReq !== null ? this.heldReq.path : '', req.path)) {
      this.pixelMap = undefined;
    }
    if (this.sameAsHeld(req)) {
      return; // already showing exactly this
    }
    const token = ++this.seq;
    // A row that has been on screen before hits synchronously; going through
    // the Promise there would blank the image for a frame on every recycle.
    const hit = cachedPixelMap(req);
    if (hit !== undefined) {
      this.swapTo(req, hit);
      return;
    }
    this.awaiting = req;
    loadPixelMap(req).then((handle: PixelHandle | undefined): void => {
      if (token !== this.seq) {
        return;
      }
      this.awaiting = null;
      if (handle === undefined) {
        return;
      }
      this.swapTo(req, handle);
    });
  }

  build() {
    // The undecoded state draws nothing rather than a placeholder: callers
    // already stack their own loading/failed state underneath.
    Image(this.pixelMap)
      .draggable(false)
      .width(this.boxWidth).height(this.boxHeight)
      .borderRadius(this.radius)
      // **borderRadius 要配 clip(true)**，否则圆角只是把角画圆，内容并没有被
      // 按那条曲线裁剪、边缘不做抗锯齿——头像的圆周上就是一圈台阶状锯齿
      // （issue #92，用户拿官方客户端对比过）。AvatarView 自己的另外两个分支
      // （Saved Messages、动态头像）本来就是 borderRadius + clip(true) 成对写的，
      // 只有走 PixelMap 缓存这一支漏了，而绝大多数头像恰恰走这一支。
      .clip(true)
      // 解码目标尺寸按 vp2px(box) 给，正常是 1:1 不缩放；但 DPR 取整、以及
      // 复用缓存里尺寸相近的那张时仍会有轻微缩放，此时默认的插值会更糙。
      .interpolation(ImageInterpolation.High)
      .objectFit(this.fit);
  }
}
