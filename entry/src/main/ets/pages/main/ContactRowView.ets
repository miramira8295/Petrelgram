import { ContactItem } from '../../store/ContactsStore';
import { AvatarView } from '../chatlist/AvatarView';
import { LIST_CARD_INSET_VP, LIST_CARD_TRAIL_VP } from '../../util/listCardGeometry';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
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
  // 玻璃档：行透明，让外层卡片那块透上来（行各铺一块是两层模糊叠加，又重又灰）。
  @Prop glassCard: boolean = false;

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private rowFill(): ResourceColor {
    if (this.pressed) {
      return $r('app.color.surface_alt');
    }
    return this.glassCard ? Color.Transparent : CARD_BG;
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
    // 行底色铺满卡片宽度（按压高亮由外层卡片的圆角裁），头像内缩 4、落在顶部标题的起始线上
    // （2026-09-15 与首页统一，见 util/listCardGeometry）。
    .padding({ left: LIST_CARD_INSET_VP, right: LIST_CARD_TRAIL_VP, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.rowFill())
    .scale({ x: this.pressed ? 0.99 : 1, y: this.pressed ? 0.985 : 1 });
  }
}
