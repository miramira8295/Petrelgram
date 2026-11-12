import { image } from '@kit.ImageKit';
import { DrawnImageReceiver } from './DrawnImageReceiver';
import { CachedImageSession } from '../../util/CachedImageSession';
import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { scrollPlaceholderState } from '../../util/scrollEffects';

// The rendering boundary for callers that already own a local image path.
// Bitmap ownership is shared with LiveThumbImage through a non-observed session;
// neither component needs to instantiate the other to reuse the decode policy.
@ComponentV2
export struct CachedImage {
  @Require @Param spec: CachedImageSpec;
  @Event onReady: () => void = (): void => {};
  @Local pixelMap: image.PixelMap | undefined = undefined;
  private scrollState = scrollPlaceholderState;
  private imageReceiver: DrawnImageReceiver = new DrawnImageReceiver();
  private imageActive: boolean = false;
  private imageSession: CachedImageSession = new CachedImageSession(
    (pixels: image.PixelMap | undefined, ready: boolean, width?: number, height?: number): void => {
      this.imageReceiver.setPixels(this.spec.drawOnCanvas === true ? pixels : undefined, width, height);
      // 同值不写：activate/reuse 会把同一个位图重新投递一次，@Local 写同值也会
      // 走一遍通知（12.4s 采集里 804 次变更，多数是这种重投）。
      if (this.pixelMap !== pixels) {
        this.pixelMap = pixels;
      }
      if (ready) { this.onReady(); }
    });

  private get boxWidth(): number { return this.spec.boxWidth; }
  private get boxHeight(): number { return this.spec.boxHeight; }
  private get radius(): number { return this.spec.radius ?? 0; }
  private get fit(): ImageFit { return this.spec.fit ?? ImageFit.Cover; }
  private get syncDisplay(): boolean { return this.spec.syncDisplay === true; }
  private get backdrop(): string { return this.spec.backdrop ?? ''; }
  private get backdropImage(): string { return this.spec.backdropImage ?? ''; }

  aboutToAppear(): void { this.imageActive = true; this.imageSession.activate(this.spec); }
  aboutToReuse(): void { this.imageActive = true; this.imageSession.activate(this.spec); }
  aboutToRecycle(): void {
    // Retain the same image while pooled, exactly like the session-held handle.
    this.imageActive = false; this.imageSession.recycle();
  }
  aboutToDisappear(): void {
    this.imageActive = false; this.imageReceiver.setPixels(undefined); this.imageSession.dispose();
  }

  // Repeat updates and @ReusableV2 activation are both required: the former
  // uses Monitor while the latter resets locals with monitors temporarily muted.
  @Monitor('spec')
  onSourceChanged(): void {
    this.imageSession.update(this.spec);
    this.syncImageReceiver();
  }

  private useDrawnImage(): boolean {
    const spec: CachedImageSpec = this.spec;
    return spec.drawOnCanvas === true && this.imageReceiver.canDraw(this.pixelMap, spec.fit ?? ImageFit.Cover);
  }

  private bindImageReceiver(): DrawnImageReceiver | undefined {
    const spec: CachedImageSpec = this.spec;
    return spec.drawOnCanvas === true ? this.imageReceiver.bind(this.getUIContext(),
      spec.boxWidth, spec.boxHeight, spec.fit ?? ImageFit.Cover, this.useDrawnImage()) : undefined;
  }

  private syncImageReceiver(): void {
    if (this.imageActive) {
      this.imageReceiver.setPixels(this.spec.drawOnCanvas === true ? this.pixelMap : undefined);
    }
  }

  private showMiniPlaceholder(): boolean {
    // Only unresolved album images subscribe to scrolling. Once decoded, the
    // real image stays visible and scroll changes cannot invalidate its input.
    return this.pixelMap === undefined && this.backdropImage !== '' &&
      !(this.spec.deferBackdropOnScroll === true && this.scrollState.active);
  }

  build() {
    // 未解码状态本身不画内容——加载/失败态由调用方自己叠。但**底色要垫**：
    // 调用方是"有路径就换成 CachedImage"的 if/else，撤占位与出图之间会透出去。
    Stack() {
      // 内联小图：只在还没解出来时存在，位图一到手这个 if 就false、节点消失。
      // 40px 拉到几百 px 必然是马赛克，所以叠一层模糊让它读起来像"正在变清晰"
      // 而不是"画糊了"——官方客户端也是这个做法。
      if (this.showMiniPlaceholder()) {
        Image(this.backdropImage)
          .draggable(false)
          .width(this.boxWidth).height(this.boxHeight)
          .borderRadius(this.radius)
          .clip(true)
          .objectFit(this.fit)
          .blur(MINI_PLACEHOLDER_BLUR);
      }
      if (!this.useDrawnImage()) {
        Image(this.pixelMap)
          .syncLoad(this.syncDisplay && this.pixelMap !== undefined)
          .draggable(false)
          .width(this.boxWidth).height(this.boxHeight)
          // 解码完成前 Image(undefined) 什么都不画；没有这层底色，调用方撤掉占位
          // 到位图落地之间格子是透明的，就是"图片闪一下"（见 util/thumbBackdrop）。
          // 位图盖上来之后它被完全遮住，不额外占节点。
          .backgroundColor(this.backdrop !== '' ? this.backdrop : Color.Transparent)
          .borderRadius(this.radius)
          // **borderRadius 要配 clip(true)**，否则圆角只是把角画圆，内容并没有被
          // 按那条曲线裁剪、边缘不做抗锯齿——头像的圆周上就是一圈台阶状锯齿
          // （issue #92，用户拿官方客户端对比过）。AvatarView 自己的另外两个分支
          // （Saved Messages、动态头像）本来就是 borderRadius + clip(true) 成对写的，
          // 只有走 PixelMap 缓存这一支漏了，而绝大多数头像恰恰走这一支。
          .clip(true)
          // 解码目标尺寸按 this.getUIContext().vp2px(box) 给，正常是 1:1 不缩放；但 DPR 取整、以及
          // 复用缓存里尺寸相近的那张时仍会有轻微缩放，此时默认的插值会更糙。
          .interpolation(ImageInterpolation.High)
          .objectFit(this.fit);
      }
    }
    .width(this.boxWidth).height(this.boxHeight)
    .backgroundColor(this.useDrawnImage() && this.backdrop !== '' ? this.backdrop : Color.Transparent)
    .borderRadius(this.radius).clip(this.useDrawnImage())
    .drawModifier(this.bindImageReceiver());
  }
}
