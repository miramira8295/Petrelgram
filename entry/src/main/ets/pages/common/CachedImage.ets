import { image } from '@kit.ImageKit';
import {
  cachedPixelMap, cancelPixelMap, loadPixelMap, PixelHandle, PixelRequest,
  pinPixelMap, releasePixelMap, retainPixelMap
} from '../../util/pixelCache';
import {
  isDecodableTarget, sameDecodeTarget, shouldBlankBeforeDecode
} from '../../util/imageSwap';

// An Image fed from the decoded-PixelMap cache instead of a file path.
//
// Everything about the lifetime lives here so callers stay a one-liner: the
// decode is async, the cache is reference counted, and a reused row has to let
// go of the old bitmap before it takes the new one. Getting any of that wrong
// frees pixels that are still on screen, so it is deliberately not something
// each call site re-implements.
//
// P4 批 4：迁 @ComponentV2（判读依据 survey 批 0.5 节，配方经批 1/2/3b/3c
// 四轮验证）。aboutToReuse 时 @Param 已是新值 → 换源判定与重启动全部同步，
// V1 的 reuseParam/nextFrameQueue 延帧退役。V2 专属陷阱：@Local pixelMap 被
// 框架重置为 undefined，而 held 的位图还 retain 着——同源复用走 sameAsHeld
// 早退分支时必须补种，见 start() 里的注释。
@ComponentV2
export struct CachedImage {
  @Param path: string = '';
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Param radius: number = 0;
  @Param fit: ImageFit = ImageFit.Cover;
  // Keep the decoded bitmap for the whole session (see pinPixelMap).
  @Param pin: boolean = false;
  // 位图第一次真正交给 Image 的那一刻。调用方据此决定什么时候撤掉自己的兜底层
  // ——解码失败时这个回调永远不来，兜底层就一直留着（issue #90）。
  @Param onReady: () => void = (): void => {};
  @Local pixelMap: image.PixelMap | undefined = undefined;
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
  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.drop();
  }

  // Recycling cancels work in flight but keeps a bitmap that is already
  // decoded. Dropping it here was a real bug: a pooled row reused with the
  // same photo gets no @Watch (the values never changed), so nothing reloaded
  // it and the cell stayed blank.
  // Recycling cancels work in flight but keeps the retained bitmap: a pooled
  // row reused with the same photo re-seeds from it synchronously (start()'s
  // sameAsHeld branch) — no decode, no blank frame.
  aboutToRecycle(): void {
    this.cancelPending();
  }

  aboutToReuse(): void {
    // @Param 已是新值（批 0.5 判读）：换源判定直接同步做。换了源先 drop——
    // 复用出来的行绝不能画着上一条消息的图等新解码；同源保留位图，
    // start() 里补种（@Local 已被框架重置）。
    if (this.heldReq !== null && this.heldReq.path !== this.path) {
      this.drop();
    }
    this.start();
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

  // 非复用路径上源/尺寸真变化时重启动；复用路径由 aboutToReuse 覆盖
  // （@Monitor 复用期静默，批 0.5 实测）。
  @Monitor('path', 'boxWidth', 'boxHeight')
  onSourceChanged(): void {
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
      // V2 复用把 @Local pixelMap 重置成 undefined，held 的位图却还 retain
      // 着——不补种就是永久空白（V1 靠「复用不清 @State」天然没这个问题）。
      if (this.pixelMap === undefined && this.held !== null) {
        this.pixelMap = this.held.pixelMap;
        this.onReady();
      }
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
