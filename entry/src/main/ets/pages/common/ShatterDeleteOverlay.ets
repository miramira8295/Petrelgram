import { image } from '@kit.ImageKit';
import { FrameCallback } from '@kit.ArkUI';
import { shatterPrepare, shatterAttach, shatterBegin, shatterClose } from 'libentry.so';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { logI, logW } from '../../util/log';
import { ShatterCanvasFallback } from './ShatterCanvasFallback';
import { ShatterStageHost } from '../../util/rowLeaveChannel';

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
  stage: ShatterStageHost | null = null;
  onCaptured: () => void = (): void => {};
  onFinish: () => void = (): void => {};
  @State private ready: boolean = false;
  @State private fallback: boolean = false;
  @State private widthVp: number = 0;
  @State private heightVp: number = 0;
  @State private offsetXVp: number = 0;
  @State private offsetYVp: number = 0;
  @State private surfaceWidthVp: number = 0;
  @State private surfaceHeightVp: number = 0;
  @State private topVp: number = 0;
  private snapshotScale: number = 1;
  private controller: XComponentController = new XComponentController();
  private handle: number = 0;
  private staged: boolean = false;
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
      if (this.staged && this.stage !== null) {
        this.stage.detachLayer(this.handle);
      } else {
        shatterClose(this.handle);
      }
      this.handle = 0;
    }
    this.staged = false;
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
    logW(`[Shatter] snapshot fade fallback: ${reason}`);
    if (this.snapshot === undefined) { this.finish(); return; }
    this.clearNativeTimeout();
    // 先切后端，XComponent 的 onDestroy 和迟到的 native 事件不能结束回退动画。
    this.fallback = true;
    this.ready = false;
    if (this.handle !== 0) {
      if (this.staged && this.stage !== null) {
        this.stage.detachLayer(this.handle);
      } else {
        shatterClose(this.handle);
      }
      this.handle = 0;
    }
    this.staged = false;
  }

  private markCaptured(): void {
    if (!this.active || this.finished || this.captured) { return; }
    this.captured = true;
    this.onCaptured();
  }

  private async capture(): Promise<void> {
    let pixels: image.PixelMap | undefined = undefined;
    try {
      const deviceDensity: number = this.getUIContext().vp2px(1);
      // 渲染表面上限 <= 2px/vp，截图阶段直接按相同比例降采样，减少 RS 读回、CPU 转换与纹理上传体量。
      const snapScale: number = deviceDensity > 2.0 ? Math.min(1.0, 2.0 / deviceDensity) : 1.0;
      this.snapshotScale = snapScale;
      try {
        // 已稳定在屏上的气泡无需等待同步渲染屏障，显著压低 ComponentSnapshot 耗时。
        pixels = await this.getUIContext().getComponentSnapshot().get(this.nodeId,
          { scale: snapScale, waitUntilRenderFinished: false });
      } catch (_fastErr) {
        if (!this.active || this.finished) { return; }
        pixels = await this.getUIContext().getComponentSnapshot().get(this.nodeId,
          { scale: snapScale, waitUntilRenderFinished: true });
      }
      if (!this.active || this.finished) { pixels.release(); return; }
      this.snapshot = pixels;
      this.preparing = true;
      const effDensity: number = deviceDensity * snapScale;
      const prepared = await shatterPrepare(pixels, effDensity, this.particleBudget);
      if (prepared === null) { this.useFallback('prepare'); return; }
      if (!this.active || this.finished) {
        shatterClose(prepared.handle);
        return;
      }
      this.handle = prepared.handle;
      const invScale: number = 1.0 / snapScale;
      this.widthVp = this.getUIContext().px2vp(prepared.width) * invScale;
      this.heightVp = this.getUIContext().px2vp(prepared.height) * invScale;
      this.offsetXVp = this.getUIContext().px2vp(prepared.offsetX ?? 0) * invScale;
      this.offsetYVp = this.getUIContext().px2vp(prepared.offsetY ?? 0) * invScale;
      this.surfaceWidthVp = this.getUIContext().px2vp(prepared.surfaceWidth) * invScale;
      this.surfaceHeightVp = this.getUIContext().px2vp(prepared.surfaceHeight) * invScale;
      this.topVp = this.getUIContext().px2vp(prepared.top) * invScale;
      logI(`[Shatter] prepared crop=${prepared.width}x${prepared.height}@(${prepared.offsetX ?? 0},${prepared.offsetY ?? 0}) tiles=${prepared.tileCount ?? 0} buf=${prepared.bufferWidth ?? 0}x${prepared.bufferHeight ?? 0}`);
      if (this.stage !== null) {
        const layerHandle: number = this.handle;
        const attached: boolean = this.stage.attachLayer(this.getUIContext(), {
          handle: layerHandle,
          nodeId: this.nodeId,
          snapScale: snapScale,
          offsetX: prepared.offsetX ?? 0,
          offsetY: prepared.offsetY ?? 0,
          surfaceWidth: prepared.surfaceWidth,
          surfaceHeight: prepared.surfaceHeight,
          top: prepared.top,
          singleMode: this.particleBudget >= 8000,
          onFirstFrame: (): void => {
            if (!this.active || this.finished || this.fallback || !this.staged || this.handle !== layerHandle) { return; }
            this.getUIContext().postFrameCallback(new ShatterCaptureFrame((): void => this.start()));
          },
          onFinish: (): void => {
            if (!this.active || this.finished || this.fallback || !this.staged || this.handle !== layerHandle) { return; }
            this.handle = 0;
            this.staged = false;
            this.finish();
          },
          onFail: (reason: string): void => {
            if (!this.active || this.finished || this.fallback || !this.staged || this.handle !== layerHandle) { return; }
            this.handle = 0;
            this.staged = false;
            this.useFallback(reason);
          }
        });
        if (attached) {
          this.staged = true;
          this.nativeTimeout = setTimeout((): void => this.useFallback('stage-first-frame-timeout'), 700);
          return;
        }
      }
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
    const durationMs: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1100);
    if (this.staged && this.stage !== null) {
      this.stage.beginLayer(this.handle, durationMs);
    } else {
      shatterBegin(this.handle, durationMs);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.fallback) {
        ShatterCanvasFallback({
          pixels: this.snapshot,
          snapshotScale: this.snapshotScale,
          canDraw: (): boolean => this.active && !this.finished && this.fallback,
          onCaptured: (): void => this.markCaptured(),
          onFinish: (): void => this.finish()
        });
      } else if (this.ready) {
        XComponent({ id: `shatter_${this.handle}`, type: XComponentType.TEXTURE, controller: this.controller })
          .width(this.surfaceWidthVp).height(this.surfaceHeightVp)
          .position({ x: this.offsetXVp, y: this.offsetYVp - this.topVp })
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
