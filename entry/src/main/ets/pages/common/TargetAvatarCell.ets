import { AvatarView } from '../chatlist/AvatarView';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY } from '../../util/theme';

// 转发 / 分享选择器里的一格：头像 + 最多两行名字，可多选。
//
// 原来只长在 ForwardSheet 的网格里（issue #200）；2026-09-17 用户要系统分享抽屉也改成
// 同样的头像网格，于是收成一个组件，两边长得一样、改一处两边一起变。
//
// 【头像描边】两层叠在头像上的空心圆（带圆角的 border 容器），不用 outline：
// 第一版用 outline(radius = 头像半径)，真机上选中圈断成上下左右四段弧（45° 方向缺角）
// ——outline 的圆角没算进描边自身宽度、外层盒子又是方的，角上的弧接不上。border 圆
// 容器是底部页签头像选中圈的现成写法，真机上是完整的圆。
// - 未选中：0.7vp 分隔线色的细边，压在头像边缘上——白底头像（很多频道图标）和白色面板
//   原来糊成一片；
// - 选中：2vp 主色圈，画在头像外面一圈，和右下角的勾一起表达选中（勾太小、换个头像就看不清）。
// 外框恒为 头像 + 2×圈宽，选中与否不改变格子尺寸。

export const TARGET_AVATAR_SIZE: number = 56;
const HAIRLINE_WIDTH: number = 0.7;
const SELECTED_RING_WIDTH: number = 2;
const CHECK_BADGE_SIZE: number = 20;
const NAME_LINE_HEIGHT: number = 16;

@Component
export struct TargetAvatarCell {
  @Prop avatarPath: string = '';
  @Prop initials: string = '';
  @Prop colorSeed: number = 0;
  @Prop savedMessages: boolean = false;
  @Prop title: string = '';
  @Prop selected: boolean = false;
  // 正在往这个会话发：头像上压一层转圈。
  @Prop busy: boolean = false;
  @Prop avatarSize: number = TARGET_AVATAR_SIZE;
  // 名字最多几行。网格里两行（行与行对齐），横排的「常用」一行。
  @Prop titleLines: number = 2;

  @Styles
  cellNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  cellPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  private ringBox(): number {
    return this.avatarSize + SELECTED_RING_WIDTH * 2;
  }

  build() {
    Column({ space: 6 }) {
      Stack() {
        AvatarView({
          avatarPath: this.avatarPath,
          initials: this.initials,
          colorSeed: this.colorSeed,
          savedMessages: this.savedMessages,
          avatarSize: this.avatarSize
        });
        // 细边：贴着头像边缘。
        Column()
          .width(this.avatarSize).height(this.avatarSize).borderRadius(this.avatarSize / 2)
          .border({ width: this.selected ? 0 : HAIRLINE_WIDTH, color: $r('app.color.divider') })
          .hitTestBehavior(HitTestMode.None);
        // 选中圈：头像外面一圈。
        Column()
          .width(this.ringBox()).height(this.ringBox()).borderRadius(this.ringBox() / 2)
          .border({ width: this.selected ? SELECTED_RING_WIDTH : 0, color: COLOR_PRIMARY })
          .hitTestBehavior(HitTestMode.None);
        if (this.busy) {
          Column().width(this.avatarSize).height(this.avatarSize)
            .borderRadius(this.avatarSize / 2).backgroundColor('#66000000');
          LoadingProgress().width(24).height(24).color(Color.White);
        } else if (this.selected) {
          // 勾选圈压在头像右下角。
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(CHECK_BADGE_SIZE).fontColor([COLOR_PRIMARY, Color.White])
            .offset({ x: (this.avatarSize - CHECK_BADGE_SIZE) / 2 + 2, y: (this.avatarSize - CHECK_BADGE_SIZE) / 2 + 2 });
        }
      }
      .width(this.ringBox()).height(this.ringBox());
      Text(this.title)
        .fontSize(12).lineHeight(NAME_LINE_HEIGHT).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(this.titleLines).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center).width('100%').height(NAME_LINE_HEIGHT * this.titleLines);
    }
    .width('100%').padding({ top: 6, bottom: 4, left: 2, right: 2 })
    .borderRadius(12)
    .backgroundColor(this.selected ? '#14007DFF' : Color.Transparent)
    .stateStyles({ normal: this.cellNormalStyle, pressed: this.cellPressedStyle })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    });
  }
}
