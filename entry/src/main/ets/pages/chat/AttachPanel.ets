import { AttachAction } from '../../util/attachActions';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';
import { BOTTOM_DRAWER_HEIGHT } from '../../util/drawerMetrics';

// 附件抽屉的内容：一张 4 列的图标网格。
//
// 纯展示——它不认识 MessageStore，也不知道点了之后会发生什么，只把 key 抛
// 回去。这样"有哪些格子"（attachActions）、"长什么样"（这里）、"点了做什么"
// （ChatPage）三件事各自可以单独改。
//
// 高度写死而不是自适应：抽屉要顶起输入框和聊天内容，那个高度得在内容挂上来
// 之前就确定，否则第一帧会先塌一下再弹开。数值和表情抽屉共用一处，见
// util/drawerMetrics。

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
    // 两行等分整块高度。不给 rowsTemplate 时行高按内容走、顶对齐，卡片下方
    // 空出一大片（实测截图）。
    .rowsTemplate('1fr 1fr')
    .rowsGap(6)
    .columnsGap(0)
    .width('100%')
    .height(BOTTOM_DRAWER_HEIGHT)
    .padding({ top: 14, bottom: 14 })
    // 八项固定两行，不该滚；给了滚动条反而会在两行的网格上出现一条多余的轨道。
    .scrollBar(BarState.Off);
  }

  @Builder
  cell(action: AttachAction) {
    Column({ space: 7 }) {
      Stack() {
        // 没有圆底，身份色移到图标本身：去掉底色之后白色字形在玻璃上几乎看
        // 不见，而每格的颜色是用来快速分辨的，不能一起丢掉。字号跟着放大一档
        // 补回原来圆底提供的视觉重量。
        SymbolGlyph($r(action.icon))
          .fontSize(30)
          .fontColor([action.tint]);
      }
      .width(ICON_SIZE)
      .height(ICON_SIZE);
      // 这里**不挂材质**。挂了就是一块玻璃砖：有圆角时是个圆底，去掉圆角后
      // 直接变成方块底——两种都不是"没有底色"。光感属于抽屉卡片那一层，
      // 格子只负责按压反馈。

      Text(action.label)
        .fontSize(12)
        .fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%');
    }
    .width('100%').height('100%')
    // 在自己那一格里居中，行高变大时图标和文字跟着居中而不是贴顶。
    .justifyContent(FlexAlign.Center)
    // 按压反馈只做缩放，不改底色：圆底是这一格的身份色，一按变灰会让人以为
    // 是另一个东西。
    //
    // 格子上没有材质（见上面那段注释），按压形变就得自己做，不受
    // pressAnimationWins 约束。
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
