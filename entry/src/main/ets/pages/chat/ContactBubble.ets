import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct ContactBubble {
  @Param firstName: string = '';
  @Param lastName: string = '';
  @Param phone: string = '';
  @Param vcard: string = '';
  @Param userId: number = 0;
  @Param avatarPath: string = '';
  @Param maxWidth: number = 250;
  @Param onOpen: () => void = (): void => {};
  @Param onCall: () => void = (): void => {};

  @Styles
  private cardNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private cardPressedStyle(): void {
    .scale({ x: 0.985, y: 0.985 })
    .opacity(0.82)
  }

  @Styles
  private actionNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private actionPressedStyle(): void {
    .scale({ x: 0.86, y: 0.86 })
    .opacity(0.62)
  }

  private name(): string {
    const value = `${this.firstName} ${this.lastName}`.trim();
    if (value !== '') {
      return value;
    }
    return this.userId > 0 ? str('cb_telegram_user') : str('cb_unnamed');
  }

  private initials(): string {
    const first = this.firstName.trim();
    const last = this.lastName.trim();
    const value = `${first.length > 0 ? first.substring(0, 1) : ''}` +
      `${last.length > 0 ? last.substring(0, 1) : ''}`;
    return value !== '' ? value.toUpperCase() : '?';
  }

  private available(): boolean {
    return this.userId > 0 || this.phone.trim() !== '' ||
      this.firstName.trim() !== '' || this.lastName.trim() !== '' || this.vcard.trim() !== '';
  }

  private subtitle(): string {
    if (this.phone.trim() !== '') {
      return this.phone.trim();
    }
    if (this.userId > 0) {
      return str('cb_tap_profile');
    }
    if (this.vcard.trim() !== '') {
      return str('cb_contact_card');
    }
    return str('cb_unavailable');
  }

  build() {
    Row({ space: 10 }) {
      Row({ space: 10 }) {
        AvatarView({
          avatarPath: this.avatarPath,
          initials: this.initials(),
          colorSeed: this.userId !== 0 ? this.userId : this.name().length * 31,
          avatarSize: 48
        });
        Column({ space: 4 }) {
          Text(this.name())
            .fontSize(14.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
          Text(this.subtitle())
            .fontSize(11.5)
            .fontColor(this.available() ? COLOR_TEXT_SECONDARY : '#D95B57')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.cardNormalStyle,
        pressed: this.cardPressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .accessibilityText(this.available() ? str('cb_contact_named', this.name()) : str('cb_unavailable'))
      .onClick((): void => {
        if (this.available()) {
          this.onOpen();
        }
      });

      if (this.phone.trim() !== '') {
        Stack() {
          Circle({ width: 34, height: 34 }).fill('#123390EC');
          SymbolGlyph($r('sys.symbol.phone_fill'))
            .fontSize(17).fontColor([COLOR_PRIMARY]);
        }
        .width(34).height(34)
        .stateStyles({
          normal: this.actionNormalStyle,
          pressed: this.actionPressedStyle
        })
        .animation({ duration: 100, curve: Curve.EaseOut })
        .accessibilityText(str('cb_call_number', this.phone.trim()))
        .onClick((): void => { this.onCall(); });
      } else {
        SymbolGlyph($r(this.userId > 0 ? 'sys.symbol.chevron_right' : 'sys.symbol.person'))
          .fontSize(this.userId > 0 ? 14 : 19)
          .fontColor([this.userId > 0 ? COLOR_ICON_SECONDARY : '#9EA6AF'])
          .opacity(this.available() ? 1 : 0.55);
      }
    }
    .width(Math.max(190, Math.min(264, this.maxWidth)))
    .alignItems(VerticalAlign.Center)
    .padding({ top: 2, bottom: 11, right: 30 });
  }
}
