import { musicGlassBlur, musicGlassFill } from '../../util/musicCenterStyle';
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
  onBack: () => void = (): void => {};
  onToggleCenter: () => void = (): void => {};
  onSearch: () => void = (): void => {};

  @Builder
  iconButton(icon: string, action: () => void) {
    Row() {
      SymbolGlyph($r(icon)).fontSize(20).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(BUTTON).height(BUTTON).borderRadius(BUTTON / 2)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: $r('app.color.divider') })
    .onClick((): void => { action(); });
  }

  build() {
    Row() {
      this.iconButton('sys.symbol.chevron_left', (): void => { this.onBack(); });
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
      .height(34).padding({ left: 12, right: 8 }).borderRadius(17)
      .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
      .border({ width: 0.5, color: $r('app.color.divider') })
      .onClick((): void => { this.onToggleCenter(); });
      this.iconButton('sys.symbol.magnifyingglass', (): void => { this.onSearch(); });
    }
    .width('100%').height(BAR_HEIGHT)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center);
  }
}
