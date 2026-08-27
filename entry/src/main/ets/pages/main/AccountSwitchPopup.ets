// 长按「个人资料」页签弹出的账号切换菜单：全屏半透明遮罩 + 一块贴在手指上方的
// 玻璃/实色面板。位置由 accountSwitchLayout 算好传进来；「滑到哪行」由父级从
// 页签的 onTouch 里算出来经 highlight 传进来（触摸序列归首个命中者，弹窗自己
// 收不到那根手指）。
//
// 材质照抄页签栏那一套（materialModifier('bar') + backdropBlur + dock_glass 回退色）：
// 弹窗是从页签栏长出来的，视觉上就该是同一块玻璃；材质关闭时两者一起变实色。
import { TdAccountSummary } from '../../tdkit/AccountRegistry';
import { AvatarView } from '../chatlist/AvatarView';
import { ACCOUNT_ROW_H, PopupRect } from '../../util/accountSwitchLayout';
import { materialModifier } from '../../util/materialModifier';
import { materialOff, overlayBackdropBlur } from '../../util/overlayMaterial';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  COLOR_DIVIDER, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';

const SCRIM: string = '#66000000';
const POPUP_RADIUS: number = 18;

function initialsOf(name: string): string {
  const trimmed: string = name.trim();
  return trimmed.length > 0 ? trimmed.substring(0, 1).toUpperCase() : '?';
}

function subtitleOf(a: TdAccountSummary): string {
  if (a.username !== '') {
    return `@${a.username}`;
  }
  return a.phone;
}

@Component
export struct AccountSwitchPopup {
  @Prop accounts: TdAccountSummary[];
  @Prop activeSlotId: string;
  @Prop rect: PopupRect;
  // 手指正压在第几行（-1 = 没有）。
  @Prop highlight: number;
  onPick: (slotId: string) => void = (_slotId: string): void => {};
  onDismiss: () => void = (): void => {};

  private fadeMs(): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160);
  }

  private panelBg(): ResourceColor {
    return materialOff() ? COLOR_SURFACE : $r('app.color.dock_glass');
  }

  @Styles
  rowNormal() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  rowPressed() {
    .backgroundColor($r('app.color.reaction_chip'))
  }

  @Builder
  accountRow(a: TdAccountSummary, index: number) {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: a.avatarPath, initials: initialsOf(a.name), colorSeed: a.userId, avatarSize: 34 });
      Column({ space: 2 }) {
        Text(a.name !== '' ? a.name : str('settings_telegram_account'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (subtitleOf(a) !== '') {
          Text(subtitleOf(a)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (a.slotId === this.activeSlotId) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([COLOR_PRIMARY]);
      }
    }
    .width('100%').height(ACCOUNT_ROW_H)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    // 手指滑到这一行时的高亮和按下态是同一个颜色：滑动松开和点击是同一件事。
    .backgroundColor(this.highlight === index ? $r('app.color.reaction_chip') : Color.Transparent)
    .stateStyles({ normal: this.rowNormal, pressed: this.rowPressed })
    .accessibilityText(str('a11y_option_state',
      a.name !== '' ? a.name : str('settings_telegram_account'),
      a.slotId === this.activeSlotId ? str('a11y_selected') : ''))
    .onClick((): void => { this.onPick(a.slotId); });
  }

  @Builder
  rows() {
    Column() {
      ForEach(this.accounts, (a: TdAccountSummary, i: number) => {
        this.accountRow(a, i);
      }, (a: TdAccountSummary) => a.slotId);
    }
    .width('100%');
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 遮罩：点一下关闭。
      Column()
        .width('100%').height('100%')
        .backgroundColor(SCRIM)
        .onClick((): void => { this.onDismiss(); });
      Column() {
        if (this.rect.scrolls) {
          Scroll() {
            this.rows();
          }
          .width('100%').height('100%')
          .scrollBar(BarState.Off);
        } else {
          this.rows();
        }
      }
      .width(this.rect.w).height(this.rect.h)
      .position({ x: this.rect.x, y: this.rect.y })
      .backgroundColor(this.panelBg())
      .backdropBlur(overlayBackdropBlur('bar'))
      .borderRadius(POPUP_RADIUS)
      .clip(true)
      .border({ width: 0.5, color: COLOR_DIVIDER })
      .shadow({ radius: 14, color: '#24000000', offsetX: 0, offsetY: 4 })
      .attributeModifier(materialModifier('bar'));
    }
    .width('100%').height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: this.fadeMs(), curve: Curve.EaseOut }));
  }
}
