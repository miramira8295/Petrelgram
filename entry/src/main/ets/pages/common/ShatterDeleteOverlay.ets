import { image } from '@kit.ImageKit';
import { AnimatorResult, FrameCallback, LengthMetricsUnit } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

interface ShatterRegion {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface ShatterTile {
  x: number;
  y: number;
  width: number;
  height: number;
  drift: number;
  rise: number;
  delay: number;
  lifetime: number;
  fade: number;
}

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

// 整区域截图消散：一张纹理、一个Canvas，按原始颜色绘制细碎片。
// 像素坐标绘制，避免不同屏幕密度下源图裁切错位；不保存截图到磁盘。
@Component
export struct ShatterDeleteOverlay {
  nodeId: string = '';
  particleBudget: number = 3200;
  onCaptured: () => void = (): void => {};
  onFinish: () => void = (): void => {};
  @State private snapshot: image.PixelMap | undefined = undefined;
  @State private widthVp: number = 0;
  @State private heightVp: number = 0;
  private tiles: ShatterTile[] = [];
  private widthPx: number = 0;
  private heightPx: number = 0;
  private paddingPx: number = 0;
  private paddingVp: number = 280;
  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  private animator: AnimatorResult | undefined = undefined;
  private active: boolean = false;
  private finished: boolean = false;
  private timeout: number = -1;

  aboutToAppear(): void {
    this.active = true;
    this.timeout = setTimeout((): void => this.finish(), 2200);
    this.capture();
  }

  aboutToDisappear(): void {
    // 行滑出复用区或切换搜索时也完成已确认的删除，避免卡住页面删除状态。
    this.finish();
    this.active = false;
    this.stop();
    const pixels = this.snapshot;
    this.snapshot = undefined;
    this.tiles = [];
    if (pixels !== undefined) { pixels.release(); }
  }

  private stop(): void {
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
    if (this.animator !== undefined) {
      this.animator.onFrame = (): void => {};
      this.animator.onFinish = (): void => {};
      this.animator.cancel();
      this.animator = undefined;
    }
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
      pixels = await this.getUIContext().getComponentSnapshot().get(this.nodeId,
        { waitUntilRenderFinished: true });
      const info = await pixels.getImageInfo();
      if (!this.active || this.finished) { pixels.release(); return; }
      this.widthPx = info.size.width;
      this.heightPx = info.size.height;
      this.widthVp = this.getUIContext().px2vp(this.widthPx);
      this.heightVp = this.getUIContext().px2vp(this.heightPx);
      this.paddingPx = this.getUIContext().vp2px(this.paddingVp);
      // 随机二分完整截图，切口错开，不再按等距网格切成粉尘。
      // 常见碎片约2–4vp，增加密度并保留随机切口；宽屏按预算放大。
      // 每块的启动时机由右上角向左下角传播；少量抖动只打散波前，不改变整体方向。
      const target = Math.max(this.getUIContext().vp2px(4),
        Math.sqrt(this.widthPx * this.heightPx / this.particleBudget));
      const pending: ShatterRegion[] = [{ x: 0, y: 0, width: this.widthPx, height: this.heightPx }];
      const tiles: ShatterTile[] = [];
      while (pending.length > 0) {
        const region = pending.pop()!;
        if ((region.width > target || region.height > target) &&
          tiles.length + pending.length < Math.min(6143, this.particleBudget * 2 - 1)) {
          const vertical = region.width > target &&
            (region.height <= target || region.width * (0.7 + Math.random() * 0.6) > region.height);
          const ratio = 0.36 + Math.random() * 0.28;
          if (vertical) {
            const cut = Math.max(1, Math.min(region.width - 1, Math.round(region.width * ratio)));
            pending.push({ x: region.x, y: region.y, width: cut, height: region.height });
            pending.push({ x: region.x + cut, y: region.y, width: region.width - cut, height: region.height });
          } else {
            const cut = Math.max(1, Math.min(region.height - 1, Math.round(region.height * ratio)));
            pending.push({ x: region.x, y: region.y, width: region.width, height: cut });
            pending.push({ x: region.x, y: region.y + cut, width: region.width, height: region.height - cut });
          }
          continue;
        }
        const centerX = region.x + region.width / 2;
        const centerY = region.y + region.height / 2;
        const fromRight = 1 - centerX / this.widthPx;
        const fromTop = centerY / this.heightPx;
        const cornerDistance = Math.sqrt(fromRight * fromRight + fromTop * fromTop) / Math.SQRT2;
        const delay = Math.max(0, Math.min(0.52,
          cornerDistance * 0.5 + (Math.random() - 0.5) * 0.035));
        tiles.push({ x: region.x, y: region.y, width: region.width, height: region.height,
          // 所有碎片朝右上方移动，越靠左的碎片向右漂移越远。
          drift: this.getUIContext().vp2px(70 + fromRight * 150 + Math.random() * 24),
          rise: this.getUIContext().vp2px(100 + Math.random() * 140),
          delay, lifetime: 1 - delay,
          fade: 0.55 + Math.random() * 0.4 });
      }
      this.tiles = tiles.sort((left: ShatterTile, right: ShatterTile): number => left.delay - right.delay);
      this.snapshot = pixels;
    } catch (_error) {
      if (pixels !== undefined && this.snapshot !== pixels) { pixels.release(); }
      this.finish();
    }
  }

  private start(): void {
    if (!this.active || this.finished || this.animator !== undefined) { return; }
    this.draw(0);
    // Canvas命令异步提交：首帧完成后才隐藏原行，避免头像交接时出现空帧。
    this.getUIContext().postFrameCallback(new ShatterCaptureFrame((): void => this.animate()));
  }

  private animate(): void {
    if (!this.active || this.finished || this.animator !== undefined) { return; }
    this.onCaptured();
    this.animator = this.getUIContext().createAnimator({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 550),
      easing: 'linear', delay: 0, fill: 'forwards', direction: 'normal',
      iterations: 1, begin: 0, end: 1
    });
    this.animator.onFrame = (progress: number): void => {
      if (this.active && !this.finished) { this.draw(progress); }
    };
    this.animator.onFinish = (): void => this.finish();
    this.animator.play();
  }

  private draw(progress: number): void {
    const pixels = this.snapshot;
    if (pixels === undefined) { return; }
    // 粒子只向右上移动，仅在上方和右侧预留画布，减少清屏面积。
    this.ctx.clearRect(0, 0, this.widthPx + this.paddingPx, this.heightPx + this.paddingPx);
    if (progress <= 0) {
      this.ctx.drawImage(pixels, 0, this.paddingPx);
      return;
    }
    // 未启动区域共用一次整图绘制，头像不会在波前到达前反复拼接、缩放。
    // 切口对齐源图整数像素，避免相邻裁片重复采样造成亮缝。
    this.ctx.save();
    this.ctx.beginPath();
    for (const tile of this.tiles) {
      if (progress <= tile.delay) {
        this.ctx.rect(tile.x, this.paddingPx + tile.y, tile.width, tile.height);
      }
    }
    this.ctx.clip();
    this.ctx.drawImage(pixels, 0, this.paddingPx);
    this.ctx.restore();
    for (const tile of this.tiles) {
      if (progress <= tile.delay) { break; }
      const t = Math.max(0, Math.min(1, (progress - tile.delay) / tile.lifetime));
      if (t >= 1) { continue; }
      const travel = t * t;
      const scale = 1 - 0.45 * t;
      const motion = 0.35 * t + 0.65 * travel;
      this.ctx.globalAlpha = Math.pow(1 - t, tile.fade);
      // 细粒子直接绘制到目标矩形，避免逐片save/translate/rotate/restore。
      this.ctx.drawImage(pixels, tile.x, tile.y, tile.width, tile.height,
        tile.x + tile.width * (1 - scale) / 2 + tile.drift * motion,
        this.paddingPx + tile.y + tile.height * (1 - scale) / 2 - tile.rise * motion,
        tile.width * scale, tile.height * scale);
    }
    this.ctx.globalAlpha = 1;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.snapshot !== undefined) {
        Canvas(this.ctx)
          .width(this.widthVp + this.paddingVp).height(this.heightVp + this.paddingVp)
          .position({ x: 0, y: -this.paddingVp })
          .onReady((): void => this.start());
      }
    }
    .width(this.widthVp).height(this.heightVp)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no');
  }
}
