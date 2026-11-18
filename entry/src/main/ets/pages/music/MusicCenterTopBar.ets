import { SystemGlassSurface } from '../chat/SystemGlassSurface';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY } from '../../util/theme';

// 音乐中心的自绘顶栏：返回键 · 「音乐中心」开关 · 搜索。
//
// 【为什么不用 HDS 标题栏】中间那颗开关是 pill + 滑块，HDS 的标题栏只认
// 标题/副标题/菜单图标三样，塞不进去（见 [[hds-titlebar-limits]]）。

const BAR_HEIGHT: number = 44;
const BUTTON: number = 38;
const TRACK_W: number = 38;
const TRACK_H: number = 24;
const KNOB: number = 18;

@Component
export struct MusicCenterTopBar {
  @Prop centerOn: boolean;
  // 三个可点元素共用一套跟手位移：0=返回 1=中间胶囊 2=搜索。
  @State private grabSlot: number = -1;
  @State private grabDX: number = 0;
  @State private grabDY: number = 0;
  private grabStartX: number = 0;
  private grabStartY: number = 0;
  onBack: () => void = (): void => {};
  onToggleCenter: () => void = (): void => {};
  onSearch: () => void = (): void => {};


  // 按住拖动跟手：按下记原点，Move 算增量 ×0.18 夹 ±3vp，松手归零。
  private trackGrab(event: TouchEvent, slot: number): void {
    if (event.type === TouchType.Down) {
      this.grabSlot = slot;
      this.grabDX = 0;
      this.grabDY = 0;
      if (event.touches.length > 0) {
        this.grabStartX = event.touches[0].x;
        this.grabStartY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.grabSlot !== slot || event.touches.length === 0) {
        return;
      }
      const dx: number = (event.touches[0].x - this.grabStartX) * 0.18;
      const dy: number = (event.touches[0].y - this.grabStartY) * 0.18;
      this.grabDX = dx > 3 ? 3 : (dx < -3 ? -3 : dx);
      this.grabDY = dy > 3 ? 3 : (dy < -3 ? -3 : dy);
      return;
    }
    this.grabSlot = -1;
    this.grabDX = 0;
    this.grabDY = 0;
  }

  @Builder
  iconButton(icon: string, action: () => void, slot: number) {
    // 玻璃改由系统沉浸材质承载（2026-11-18 全应用统一）。
    Stack() {
      SystemGlassSurface({ radius: BUTTON / 2, fixedWidth: BUTTON, fixedHeight: BUTTON }) {
        Row() {
          SymbolGlyph($r(icon)).fontSize(20).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center);
      }
    }
    .width(BUTTON).height(BUTTON)
    .translate({ x: this.grabSlot === slot ? this.grabDX : 0, y: this.grabSlot === slot ? this.grabDY : 0 })
    .onTouch((event: TouchEvent): void => { this.trackGrab(event, slot); })
    .onClick((): void => { action(); });
  }

  build() {
    Row() {
      this.iconButton('sys.symbol.chevron_left', (): void => { this.onBack(); }, 0);
      Stack() {
        SystemGlassSurface({ radius: 17, fixedHeight: 34 }) {
      Row({ space: 8 }) {
        Text($r('app.string.mc_title'))
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        // 开关：一条轨 + 一颗滑块。滑块靠 offset 走位，开关态之间有动画。
        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width(TRACK_W).height(TRACK_H).borderRadius(TRACK_H / 2)
            .backgroundColor(this.centerOn ? COLOR_PRIMARY : $r('app.color.surface_alt'));
          Column()
            .width(KNOB).height(KNOB).borderRadius(KNOB / 2)
            .backgroundColor(Color.White)
            .shadow({ radius: 3, color: '#4D000000', offsetX: 0, offsetY: 1 })
            .offset({ x: this.centerOn ? TRACK_W - KNOB - 3 : 3, y: 0 })
            .animation({ duration: 200, curve: Curve.EaseInOut });
        }
        .width(TRACK_W).height(TRACK_H);
      }
      .height('100%').padding({ left: 12, right: 8 });
        }
      }
      .height(34)
      .translate({ x: this.grabSlot === 1 ? this.grabDX : 0, y: this.grabSlot === 1 ? this.grabDY : 0 })
      .onTouch((event: TouchEvent): void => { this.trackGrab(event, 1); })
      .onClick((): void => { this.onToggleCenter(); });
      this.iconButton('sys.symbol.magnifyingglass', (): void => { this.onSearch(); }, 2);
    }
    .width('100%').height(BAR_HEIGHT)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center);
  }
}
