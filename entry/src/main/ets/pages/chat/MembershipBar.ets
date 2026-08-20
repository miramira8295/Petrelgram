import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  MEMBERSHIP_BLOCKED, MEMBERSHIP_CHECKING, MEMBERSHIP_JOINABLE, MEMBERSHIP_READONLY
} from '../../util/membershipState';

// 没有发言权时，输入区的位置放什么。
//
// 四种形态各一副样子：正在确认身份（转圈）、被挡在外面（一句说明）、只读频道
// （让位给静音开关）、可加入（加入按钮）。判定本身在 util/membershipState，
// 有单测；这里只按结果画。
//
// 高度要上报给页面：它决定消息列表底部留多少空，和输入框走的是同一个字段。

@Component
export struct MembershipBar {
  // util/membershipState 的取值；writable 时页面根本不挂这个组件。
  @Prop state: string;
  @Prop isMuted: boolean;
  @Prop joining: boolean;
  // 底部让出的高度，由页面按键盘/抽屉状态算好传进来。
  @Prop bottomGap: number;

  onJoin: () => void = (): void => {};
  onToggleMute: () => void = (): void => {};
  onHeightChange: (height: number) => void = (): void => {};

  build() {
    Column() {
      Row({ space: 8 }) {
        if (this.state === MEMBERSHIP_CHECKING) {
          LoadingProgress()
            .width(20).height(20).color(COLOR_PRIMARY);
          Text($r('app.string.cp_fetching_membership'))
            .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
        } else if (this.state === MEMBERSHIP_BLOCKED) {
          Text($r('app.string.cp_cannot_join'))
            .fontSize(16).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
        } else if (this.state === MEMBERSHIP_READONLY) {
          SymbolGlyph($r(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash'))
            .fontSize(17).fontColor([COLOR_PRIMARY]);
          Text(this.isMuted ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'))
            .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        } else {
          if (this.joining) {
            LoadingProgress()
              .width(20).height(20).color(COLOR_PRIMARY);
          }
          Text(this.joining ? $r('app.string.cp_joining') : $r('app.string.cp_join'))
            .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        }
      }
      .width('100%')
      // 和输入框内部那颗胶囊同一副轮廓。
      .constraintSize({ minHeight: 48 })
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(24)
      // 只有"可加入且没在加入中"和"只读（点了是切静音）"可点。确认中、被挡住
      // 都不可点：前者点了没意义，后者点了只会失败。
      // 照抄原式的正面枚举，而不是反过来排除——反写在遇到意外状态时行为会翻转。
      .enabled((this.state === MEMBERSHIP_JOINABLE && !this.joining) ||
        this.state === MEMBERSHIP_READONLY)
      .onClick((): void => {
        if (this.state === MEMBERSHIP_READONLY) {
          this.onToggleMute();
        } else {
          this.onJoin();
        }
      });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 6, bottom: this.bottomGap })
    .alignItems(HorizontalAlign.Center)
    .onAreaChange((_old: Area, area: Area): void => {
      this.onHeightChange(area.height as number);
    });
  }
}
