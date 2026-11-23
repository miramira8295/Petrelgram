// Menu layout may remeasure a custom preview with smaller constraints. Keep
// the prepared bubble's geometry intact, then fit its ENTIRE subtree (paint +
// native islands) into that viewport. These nodes exist only in the popup.
export function menuPreviewFitScale(width: number, height: number, availableWidth: number, availableHeight: number): number {
  if (width <= 0 || height <= 0 || !Number.isFinite(width) || !Number.isFinite(height)) { return 0; }
  return Math.max(0, Math.min(1, availableWidth / width, availableHeight / height));
}

@ComponentV2
export struct DrawnMenuIntrinsic {
  @Require @Param sourceWidth: number;
  @Require @Param sourceHeight: number;
  @BuilderParam content: () => void;

  onMeasureSize(_self: GeometryInfo, children: Measurable[], _constraint: ConstraintSizeOptions): SizeResult {
    const size: SizeResult = { width: this.sourceWidth, height: this.sourceHeight };
    // content is one canvasContent Stack, not one child per message part.
    children[0]?.measure({ minWidth: size.width, maxWidth: size.width, minHeight: size.height, maxHeight: size.height });
    return size;
  }

  onPlaceChildren(_self: GeometryInfo, children: Layoutable[], _constraint: ConstraintSizeOptions): void {
    children[0]?.layout({ x: 0, y: 0 });
  }

  build() { this.content(); }
}

@ComponentV2
export struct DrawnMenuViewport {
  @Require @Param sourceWidth: number;
  @Require @Param sourceHeight: number;
  @BuilderParam content: () => void;
  @Local private viewportWidth: number = -1;
  @Local private viewportHeight: number = -1;

  @Computed private get fitScale(): number {
    return menuPreviewFitScale(this.sourceWidth, this.sourceHeight,
      this.viewportWidth < 0 ? this.sourceWidth : this.viewportWidth,
      this.viewportHeight < 0 ? this.sourceHeight : this.viewportHeight);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      DrawnMenuIntrinsic({ sourceWidth: this.sourceWidth, sourceHeight: this.sourceHeight,
        content: (): void => { this.content(); } })
        .scale({ x: this.fitScale, y: this.fitScale, centerX: 0, centerY: 0 })
        .position({ x: 0, y: 0 });
    }
    .width(this.sourceWidth).height(this.sourceHeight).clip(true)
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const width = Number(size.width), height = Number(size.height);
      if (!Number.isFinite(width) || !Number.isFinite(height)) { return; }
      // Only the scale observer is dirtied; no row plan/paragraph is rebuilt.
      if (this.viewportWidth !== width) { this.viewportWidth = width; }
      if (this.viewportHeight !== height) { this.viewportHeight = height; }
    });
  }
}
