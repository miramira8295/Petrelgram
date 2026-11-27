import { COLOR_TEXT_PRIMARY } from '../../util/theme';

// 分段刻度胶囊滑杆（HarmonyOS 风格）：
// 药丸容器 + 两侧小/大图标或文字 + 分段蓝/灰轨道与刻度圆点 + 椭圆白色滑块。
// 支持水平拖动顺滑吸附与点击任意刻度直达，不抢父级 Scroll 的纵向滚动手势。
const THUMB_W: number = 34;
const THUMB_H: number = 22;
const DOT_SIZE: number = 5;
const DOT_GAP: number = 4;

@Component
export struct SteppedCapsuleSlider {
  @Prop values: number[] = [];
  @Prop currentValue: number = 0;
  @Prop accentColor: ResourceColor = '#0A59F7';
  // 'text'：两侧显示文字（如小 A / 大 A，或 薄 / 厚）；'corner'：两侧显示方角/圆角示意图标。
  @Prop endKind: string = 'text';
  @Prop leftText: string = 'A';
  @Prop rightText: string = 'A';
  @Prop leftFontSize: number = 13;
  @Prop rightFontSize: number = 19;
  onSelect: (value: number) => void = (): void => {};

  @State private trackW: number = 0;
  @State private dragging: boolean = false;
  @State private dragIndex: number = -1;
  private panStartX: number = 0;

  private activeIndex(): number {
    if (this.dragging && this.dragIndex >= 0 && this.dragIndex < this.values.length) {
      return this.dragIndex;
    }
    if (this.values.length === 0) {
      return 0;
    }
    let bestIdx: number = 0;
    let bestDist: number = Math.abs(this.values[0] - this.currentValue);
    for (let i: number = 1; i < this.values.length; i++) {
      const dist: number = Math.abs(this.values[i] - this.currentValue);
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  private dotCenterX(index: number): number {
    const count: number = this.values.length;
    if (count <= 1 || this.trackW <= THUMB_W) {
      return this.trackW / 2;
    }
    const usable: number = this.trackW - THUMB_W;
    return THUMB_W / 2 + (usable * index) / (count - 1);
  }

  private indexFromX(localX: number): number {
    const count: number = this.values.length;
    if (count <= 1 || this.trackW <= THUMB_W) {
      return 0;
    }
    const usable: number = this.trackW - THUMB_W;
    const ratio: number = Math.max(0, Math.min(1, (localX - THUMB_W / 2) / usable));
    return Math.round(ratio * (count - 1));
  }

  private commitIndex(idx: number): void {
    if (idx < 0 || idx >= this.values.length) {
      return;
    }
    const nextVal: number = this.values[idx];
    if (nextVal !== this.currentValue) {
      this.onSelect(nextVal);
    }
  }

  private segmentIndices(): number[] {
    const out: number[] = [];
    for (let i: number = 0; i < this.values.length - 1; i++) {
      out.push(i);
    }
    return out;
  }

  @Builder
  private endIndicator(isRight: boolean) {
    if (this.endKind === 'corner') {
      Column()
        .width(isRight ? 15 : 13)
        .height(isRight ? 15 : 13)
        .borderRadius(isRight ? 7.5 : 2)
        .border({ width: 1.6, color: COLOR_TEXT_PRIMARY });
    } else {
      Text(isRight ? this.rightText : this.leftText)
        .fontSize(isRight ? this.rightFontSize : this.leftFontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
        .constraintSize({ minWidth: 18 });
    }
  }

  build() {
    Row({ space: 12 }) {
      this.endIndicator(false);

      Stack({ alignContent: Alignment.Start }) {
        // 1. 分段轨道线（每段夹在相邻两颗圆点之间，左右各留小空隙）
        if (this.trackW > THUMB_W && this.values.length > 1) {
          ForEach(this.segmentIndices(), (segIdx: number) => {
            Row()
              .width(Math.max(2,
                (this.dotCenterX(segIdx + 1) - this.dotCenterX(segIdx)) - DOT_SIZE - DOT_GAP * 2))
              .height(2.5)
              .borderRadius(1.25)
              .backgroundColor(segIdx < this.activeIndex() ? this.accentColor : '#59888888')
              .position({
                x: this.dotCenterX(segIdx) + DOT_SIZE / 2 + DOT_GAP,
                y: 18 - 1.25
              })
              .hitTestBehavior(HitTestMode.None);
          }, (segIdx: number): string => `seg-${segIdx}`);

          // 2. 刻度圆点
          ForEach(this.values, (_val: number, idx: number) => {
            if (idx !== this.activeIndex()) {
              Row()
                .width(DOT_SIZE)
                .height(DOT_SIZE)
                .borderRadius(DOT_SIZE / 2)
                .backgroundColor(idx < this.activeIndex() ? this.accentColor : '#80888888')
                .position({
                  x: this.dotCenterX(idx) - DOT_SIZE / 2,
                  y: 18 - DOT_SIZE / 2
                })
                .hitTestBehavior(HitTestMode.None);
            }
          }, (_val: number, idx: number): string => `dot-${idx}`);

          // 3. 椭圆白色滑块
          Row()
            .width(THUMB_W)
            .height(THUMB_H)
            .borderRadius(THUMB_H / 2)
            .backgroundColor(Color.White)
            .border({ width: 0.7, color: '#1F000000' })
            .shadow({ radius: 5, color: '#1F000000', offsetX: 0, offsetY: 1 })
            .position({
              x: this.dotCenterX(this.activeIndex()) - THUMB_W / 2,
              y: 18 - THUMB_H / 2
            })
            .animation(this.dragging ? { duration: 0 } : { duration: 120, curve: Curve.EaseOut })
            .hitTestBehavior(HitTestMode.None);
        }
      }
      .layoutWeight(1)
      .height(40)
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Block)
      .onAreaChange((_old: Area, area: Area): void => {
        const w: number = Number(area.width);
        if (w > 0 && Math.abs(w - this.trackW) > 0.5) {
          this.trackW = w;
        }
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Horizontal, distance: 2 })
            .onActionStart((event: GestureEvent): void => {
              this.dragging = true;
              const startX: number = event.fingerList.length > 0
                ? event.fingerList[0].localX : this.dotCenterX(this.activeIndex());
              this.panStartX = startX;
              const idx: number = this.indexFromX(startX);
              this.dragIndex = idx;
              this.commitIndex(idx);
            })
            .onActionUpdate((event: GestureEvent): void => {
              const x: number = event.fingerList.length > 0
                ? event.fingerList[0].localX : (this.panStartX + event.offsetX);
              const idx: number = this.indexFromX(x);
              if (idx !== this.dragIndex) {
                this.dragIndex = idx;
                this.commitIndex(idx);
              }
            })
            .onActionEnd((): void => {
              this.dragging = false;
              this.dragIndex = -1;
            })
            .onActionCancel((): void => {
              this.dragging = false;
              this.dragIndex = -1;
            }),
          TapGesture()
            .onAction((event: GestureEvent): void => {
              if (event.fingerList.length > 0) {
                const idx: number = this.indexFromX(event.fingerList[0].localX);
                this.commitIndex(idx);
              }
            })
        )
      );

      this.endIndicator(true);
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .borderRadius(23)
    .backgroundColor($r('app.color.surface_alt'))
    .alignItems(VerticalAlign.Center);
  }
}
