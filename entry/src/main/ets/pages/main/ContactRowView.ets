import { ContactItem } from '../../store/ContactsStore';
import { AvatarView } from '../chatlist/AvatarView';
import { HOME_CARD_INSET_VP } from '../../util/listCardGeometry';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, ROW_PAD_H, ROW_PAD_V } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { APPEARANCE_EPOCH } from '../../util/appearance';

// 与 ContactsPage 的卡片同值。
const CARD_BG: ResourceColor = $r('app.color.surface');

// 联系人页的一行。原来是 ContactsPage 里的 @Builder，跟着 ForEach 一次性为每个联系人
// 建一棵；现在是可复用组件，LazyForEach 滚动时滚出去的行进复用池、滚进来的行从池里取。
//
// **只管画，不管交互。** 点击、按压、长按菜单都挂在页面 LazyForEach 的 ListItem 上：
// ListItem 随行 key 重建，闭包里拿到的永远是这一行当下的联系人；挂在复用组件里的回调
// 会跟着节点进池，复用后还攥着上一个联系人。
//
// **不挂常驻 .animation()。** 复用时每换一次数据就是一次重渲染，常驻 .animation 会让每次
// 重渲染都同步冲刷一次（2026-09-14 贴纸视频那次 trace 量过）。按压态的过渡改由页面在
// 按压那一刻 animateTo 驱动一次（ContactsPage.setPressedContact）。
@Reusable
@Component
export struct ContactRowView {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @Prop contact: ContactItem;
  @Prop pressed: boolean = false;
  // 正在为这个联系人开会话或删除。
  @Prop busy: boolean = false;

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 行本身不再铺底色：2026-10-29 起一行一张卡片（与首页同款），底色、玻璃、
  // 圆角都由页面那一层的卡片负责，行透明才能让卡片那块透上来（行各铺一块就是
  // 两层模糊叠加，又重又灰）。只剩按压高亮留在行上，由卡片 clip 裁圆角。
  private rowFill(): ResourceColor {
    return this.pressed ? $r('app.color.surface_alt') : Color.Transparent;
  }

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AvatarView({
          avatarPath: this.contact.avatarPath,
          initials: this.contact.initials,
          colorSeed: this.contact.id,
          avatarSize: 46
        });
        if (this.contact.online) {
          Circle({ width: 12, height: 12 })
            .fill('#34C759')
            .border({ width: 2, color: CARD_BG })
            .translate({ x: 1, y: 1 })
            // 不带自身动画参数：复用行按需创建时（滑动、换数据）绿点直接出现，不在滚动中一个个弹出来。
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.5, y: 0.5 })));
        }
      }
      .width(46)
      .height(46);
      Column({ space: 3 }) {
        Text(this.contact.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.contact.statusText)
          .fontSize(13)
          .fontColor(this.contact.online ? this.accent() : COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      if (this.busy) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accent())
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.65, y: 0.65 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
              curve: Curve.EaseOut
            }));
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 60 })
    // 与首页会话行同一套内边距：左 8、右 14、上下 8（util/theme 的 ROW_PAD_*）。
    .padding({ left: HOME_CARD_INSET_VP, right: ROW_PAD_H, top: ROW_PAD_V, bottom: ROW_PAD_V })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.rowFill())
    .scale({ x: this.pressed ? 0.99 : 1, y: this.pressed ? 0.985 : 1 });
  }
}
