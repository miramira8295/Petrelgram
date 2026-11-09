import { image } from '@kit.ImageKit';
import { FrameCallback } from '@kit.ArkUI';
import { shatterPrepare, shatterAttach, shatterBegin, shatterClose } from 'libentry.so';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { logI, logW } from '../../util/log';
import { ShatterCanvasFallback } from './ShatterCanvasFallback';

class ShatterCaptureFrame extends FrameCallback {
  private ready: () => void;

  constructor(ready: () => void) {
    super();
    this.ready = ready;
  }

  onIdle(_timeLeftInNano: number): void {
    this.ready();
  }
}

// 截图/完成协议不变；切块和像素准备在 worker，运动/淡出在 GPU。
// TEXTURE 参与 ArkUI 透明合成，避免独立 SURFACE 覆盖其他页面内容。
@Component
export struct ShatterDeleteOverlay {
  nodeId: string = '';
  particleBudget: number = 8000;
  onCaptured: () => void = (): void => {};
  onFinish: () => void = (): void => {};
  @State private ready: boolean = false;
  @State private fallback: boolean = false;
  @State private widthVp: number = 0;
  @State private heightVp: number = 0;
  @State private surfaceWidthVp: number = 0;
  @State private surfaceHeightVp: number = 0;
  @State private topVp: number = 0;
  private controller: XComponentController = new XComponentController();
  private handle: number = 0;
  private active: boolean = false;
  private finished: boolean = false;
  private started: boolean = false;
  private captured: boolean = false;
  private preparing: boolean = false;
  private snapshot: image.PixelMap | undefined = undefined;
  private timeout: number = -1;
  private nativeTimeout: number = -1;

  aboutToAppear(): void {
    this.active = true;
    this.timeout = setTimeout((): void => this.finish(), 2750);
    if (powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1100) === 0) {
      this.finish();
      return;
    }
    this.capture();
  }

  aboutToDisappear(): void {
    // 行滑出复用区或切页也完成已确认的删除，迟到的准备结果会自行关闭。
    this.finish();
    this.active = false;
  }

  private finish(): void {
    if (!this.active || this.finished) { return; }
    this.finished = true;
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
    this.clearNativeTimeout();
    if (this.handle !== 0) {
      shatterClose(this.handle);
      this.handle = 0;
    }
    this.ready = false;
    this.fallback = false;
    // worker 还在读取时等它返回后释放；回退 Canvas 也从此不再绘制。
    if (!this.preparing) { this.releaseSnapshot(); }
    this.onFinish();
  }

  private clearNativeTimeout(): void {
    if (this.nativeTimeout !== -1) { clearTimeout(this.nativeTimeout); this.nativeTimeout = -1; }
  }

  private releaseSnapshot(): void {
    const pixels = this.snapshot;
    this.snapshot = undefined;
    if (pixels !== undefined) { pixels.release(); }
  }

  private useFallback(reason: string): void {
    if (!this.active || this.finished || this.fallback) { return; }
    logW(`[Shatter] Canvas fallback: ${reason}`);
    if (this.snapshot === undefined) { this.finish(); return; }
    this.clearNativeTimeout();
    // 先切后端，XComponent 的 onDestroy 和迟到的 native 事件不能结束回退动画。
    this.fallback = true;
    this.ready = false;
    if (this.handle !== 0) { shatterClose(this.handle); this.handle = 0; }
  }

  private markCaptured(): void {
    if (!this.active || this.finished || this.captured) { return; }
    this.captured = true;
    this.onCaptured();
  }

  private async capture(): Promise<void> {
    let pixels: image.PixelMap | undefined = undefined;
    try {
      pixels = await this.getUIContext().getComponentSnapshot().get(this.nodeId,
        { waitUntilRenderFinished: true });
      if (!this.active || this.finished) { pixels.release(); return; }
      this.snapshot = pixels;
      this.preparing = true;
      const prepared = await shatterPrepare(pixels, this.getUIContext().vp2px(1), this.particleBudget);
      if (prepared === null) { this.useFallback('prepare'); return; }
      if (!this.active || this.finished) {
        shatterClose(prepared.handle);
        return;
      }
      this.handle = prepared.handle;
      this.widthVp = this.getUIContext().px2vp(prepared.width);
      this.heightVp = this.getUIContext().px2vp(prepared.height);
      this.surfaceWidthVp = this.getUIContext().px2vp(prepared.surfaceWidth);
      this.surfaceHeightVp = this.getUIContext().px2vp(prepared.surfaceHeight);
      this.topVp = this.getUIContext().px2vp(prepared.top);
      this.ready = true;
      this.nativeTimeout = setTimeout((): void => this.useFallback('first-frame-timeout'), 700);
    } catch (_error) {
      if (this.snapshot !== undefined) { this.useFallback('prepare-exception'); }
      else { logW('[Shatter] capture failed'); this.finish(); }
    } finally {
      this.preparing = false;
      // 保留截图到本次效果结束，保证 GPU 失败时仍能恢复原效果；不留到业务删除返回。
      if (!this.active || this.finished) { this.releaseSnapshot(); }
    }
  }

  private attach(): void {
    if (!this.active || this.finished || this.fallback || this.handle === 0) { return; }
    try {
      const attached = shatterAttach(this.handle, this.controller.getXComponentSurfaceId(),
        (event: number): void => {
          if (!this.active || this.finished || this.fallback) { return; }
          if (event === 0) {
            // 首帧已 swap，再等 ArkUI 一帧交接，隐藏原行后才启动 1100ms 计时。
            this.getUIContext().postFrameCallback(new ShatterCaptureFrame((): void => this.start()));
          } else if (event === 1) {
            this.finish();
          } else {
            this.useFallback('render');
          }
        });
      if (!attached) { this.useFallback('surface-attach'); }
    } catch (_error) {
      this.useFallback('surface-exception');
    }
  }

  private start(): void {
    if (!this.active || this.finished || this.fallback || this.started || this.handle === 0) { return; }
    this.started = true;
    this.clearNativeTimeout();
    logI('[Shatter] GPU first frame ready');
    this.markCaptured();
    if (!this.active || this.finished || this.handle === 0) { return; }
    shatterBegin(this.handle, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1100));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.fallback) {
        ShatterCanvasFallback({
          pixels: this.snapshot,
          particleBudget: this.particleBudget,
          canDraw: (): boolean => this.active && !this.finished && this.fallback,
          onCaptured: (): void => this.markCaptured(),
          onFinish: (): void => this.finish()
        });
      } else if (this.ready) {
        XComponent({ id: `shatter_${this.handle}`, type: XComponentType.TEXTURE, controller: this.controller })
          .width(this.surfaceWidthVp).height(this.surfaceHeightVp)
          .position({ x: 0, y: -this.topVp })
          .backgroundColor(Color.Transparent)
          .onLoad((): void => this.attach())
          .onDestroy((): void => {
            if (!this.fallback) { this.finish(); }
          });
      }
    }
    .width(this.fallback ? undefined : this.widthVp).height(this.fallback ? undefined : this.heightVp)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no');
  }
}
