import { image } from '@kit.ImageKit';
import { FrameCallback, LengthMetricsUnit } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

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

// GPU 失败时只画一次截图并交给系统淡出；禁止回到 UI 线程逐粒子动画。
// 像素坐标绘制，避免不同屏幕密度下源图裁切错位；不保存截图到磁盘。
@Component
export struct ShatterCanvasFallback {
  pixels: image.PixelMap | undefined = undefined;
  snapshotScale: number = 1;
  canDraw: () => boolean = (): boolean => true;
  onCaptured: () => void = (): void => {};
  onFinish: () => void = (): void => {};
  @State private snapshot: image.PixelMap | undefined = undefined;
  @State private widthVp: number = 0;
  @State private heightVp: number = 0;
  @State private fadeOpacity: number = 1;
  private started: boolean = false;
  private widthPx: number = 0;
  private heightPx: number = 0;
  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  private active: boolean = false;
  private finished: boolean = false;
  private timeout: number = -1;

  aboutToAppear(): void {
    this.active = true;
    this.timeout = setTimeout((): void => this.finish(), 2750);
    this.capture();
  }

  aboutToDisappear(): void {
    // 行滑出复用区或切换搜索时也完成已确认的删除，避免卡住页面删除状态。
    this.finish();
    this.active = false;
    this.stop();
    this.snapshot = undefined;
  }

  private stop(): void {
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
  }

  private finish(): void {
    if (!this.active || this.finished) { return; }
    this.finished = true;
    this.stop();
    this.onFinish();
  }

  private async capture(): Promise<void> {
    let pixels: image.PixelMap | undefined = undefined;
    try {
      pixels = this.pixels;
      if (pixels === undefined || !this.canDraw()) { this.finish(); return; }
      const info = await pixels.getImageInfo();
      if (!this.active || this.finished || !this.canDraw()) { return; }
      const scale: number = this.snapshotScale > 0 ? this.snapshotScale : 1;
      this.widthPx = info.size.width;
      this.heightPx = info.size.height;
      this.widthVp = this.getUIContext().px2vp(this.widthPx) / scale;
      this.heightVp = this.getUIContext().px2vp(this.heightPx) / scale;
      this.snapshot = pixels;
    } catch (_error) {
      this.finish();
    }
  }

  private start(): void {
    if (!this.active || this.finished || !this.canDraw() || this.started || this.snapshot === undefined) { return; }
    this.started = true;
    const scale: number = this.snapshotScale > 0 ? this.snapshotScale : 1;
    if (scale < 0.999) {
      this.ctx.drawImage(this.snapshot, 0, 0, this.widthPx / scale, this.heightPx / scale);
    } else {
      this.ctx.drawImage(this.snapshot, 0, 0);
    }
    this.getUIContext().postFrameCallback(new ShatterCaptureFrame((): void => this.animate()));
  }

  private animate(): void {
    if (!this.active || this.finished || !this.canDraw() || this.fadeOpacity === 0) { return; }
    this.onCaptured();
    this.getUIContext().animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.Linear, onFinish: (): void => this.finish()
    }, (): void => { this.fadeOpacity = 0; });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.snapshot !== undefined) {
        Canvas(this.ctx)
          .width(this.widthVp).height(this.heightVp)
          .opacity(this.fadeOpacity)
          .onReady((): void => this.start());
      }
    }
    .width(this.widthVp).height(this.heightVp)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no');
  }
}
