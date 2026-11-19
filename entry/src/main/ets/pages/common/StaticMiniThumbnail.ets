import { miniThumbBlurCache } from '../../util/miniThumbBlurCache';

interface StaticMiniResult { source: string; w: number; h: number; fit: ImageFit; uri: string; }

// Only mounted while full pixels are missing. Completion changes this Image,
// never the owning message's state, layout, progress ring or click target.
@ComponentV2
export struct StaticMiniThumbnail {
  @Require @Param source: string;
  @Require @Param boxW: number;
  @Require @Param boxH: number;
  @Param imageFit: ImageFit = ImageFit.Cover;
  @Local private result: StaticMiniResult | null = null;
  private active: boolean = false;
  private generation: number = 0;
  private cancel: (() => void) | null = null;

  private detach(): void { this.generation++; this.cancel?.(); this.cancel = null; }
  private bind(): void {
    this.detach();
    if (!this.active) { return; }
    const generation = this.generation, source = this.source, w = this.boxW, h = this.boxH, fit = this.imageFit;
    const density = this.getUIContext().vp2px(1);
    this.cancel = miniThumbBlurCache.request(source, w * density, h * density, fit === ImageFit.Contain, (uri: string): void => {
      if (!this.active || generation !== this.generation || source !== this.source ||
        w !== this.boxW || h !== this.boxH || fit !== this.imageFit) { return; }
      this.result = { source, w, h, fit, uri };
    });
  }
  @Monitor('source', 'boxW', 'boxH', 'imageFit') private changed(): void { this.bind(); }
  aboutToAppear(): void { this.active = true; this.bind(); }
  aboutToReuse(): void { this.active = true; this.result = null; this.bind(); }
  aboutToRecycle(): void { this.active = false; this.detach(); this.result = null; }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private shownSource(): string {
    const r = this.result;
    // Parameter changes can render before Monitor delivery; never expose the prior row.
    return r !== null && r.source === this.source && r.w === this.boxW && r.h === this.boxH && r.fit === this.imageFit
      ? r.uri : this.source;
  }
  build() {
    Image(this.shownSource()).alt(this.source).width(this.boxW).height(this.boxH)
      .objectFit(this.imageFit).interpolation(ImageInterpolation.High).draggable(false)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants');
  }
}
