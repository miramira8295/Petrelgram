import { AttachAction } from '../../util/attachActions';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';

// 附件抽屉的内容：一张 4 列的图标网格。
//
// 纯展示——它不认识 MessageStore，也不知道点了之后会发生什么，只把 key 抛
// 回去。这样"有哪些格子"（attachActions）、"长什么样"（这里）、"点了做什么"
// （ChatPage）三件事各自可以单独改。
//
// 高度写死而不是自适应：抽屉要顶起输入框和聊天内容，那个高度得在内容挂上来
// 之前就确定，否则第一帧会先塌一下再弹开。8 项两行，260 是量出来的。
export const ATTACH_PANEL_HEIGHT: number = 260;

const COLUMNS: number = 4;
const ICON_SIZE: number = 52;

@Component
export struct AttachPanel {
  @Prop actions: AttachAction[];
  onPick: (key: string) => void = (): void => {};
  // 省电开关沿用 ChatPage 的约定：传进来的函数在关掉动效时返回 0。
  effectDuration: (ms: number) => number = (ms: number): number => ms;

  @State pressedKey: string = '';

  build() {
    Grid() {
      ForEach(this.actions, (action: AttachAction): void => {
        GridItem() {
          this.cell(action);
        }
      }, (action: AttachAction): string => action.key)
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .rowsGap(6)
    .columnsGap(0)
    .width('100%')
    .height(ATTACH_PANEL_HEIGHT)
    .padding({ top: 14, bottom: 14 })
    // 八项固定两行，不该滚；给了滚动条反而会在两行的网格上出现一条多余的轨道。
    .scrollBar(BarState.Off);
  }

  @Builder
  cell(action: AttachAction) {
    Column({ space: 7 }) {
      Stack() {
        SymbolGlyph($r(action.icon))
          .fontSize(25)
          .fontColor([Color.White]);
      }
      .width(ICON_SIZE)
      .height(ICON_SIZE)
      .borderRadius(ICON_SIZE / 2)
      .backgroundColor(action.tint);

      Text(action.label)
        .fontSize(12)
        .fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%');
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 按压反馈只做缩放，不改底色：圆底是这一格的身份色，一按变灰会让人以为
    // 是另一个东西。
    .scale(this.pressedKey === action.key ? { x: 0.9, y: 0.9 } : { x: 1, y: 1 })
    .animation({ duration: this.effectDuration(110), curve: Curve.EaseOut })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedKey = action.key;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick((): void => { this.onPick(action.key); });
  }
}
