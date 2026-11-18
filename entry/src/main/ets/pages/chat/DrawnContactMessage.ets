import { contactVcardSummary } from '../../util/contactVcardSummary';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { contactLayoutFor, DrawnContactLayout, DrawnContactTextPainter } from './DrawnContactLayout';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';

// Like ChatMessageCell's contact delegate, actions resolve the current bound
// contact at activation time. Avatar arrival never changes the document source.
@ComponentV2
export struct DrawnContactMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 262;
  @Event onClaim: () => boolean = (): boolean => false;

  private painter: DrawnContactTextPainter = new DrawnContactTextPainter();
  @Computed private get layout(): DrawnContactLayout | null { return contactLayoutFor(this.widget); }

  private openContact(): void {
    if (!this.onClaim()) { return; }
    this.actions.onContactOpen(this.msg.contactUserId, this.msg.contactPhone, this.msg.contactVcard);
  }

  @Computed private get callPhone(): string {
    return contactVcardSummary(this.msg.contactVcard, this.msg.contactPhone).phones[0] ?? '';
  }
  private callContact(): void {
    if (!this.onClaim() || this.callPhone === '') { return; }
    this.actions.onPhoneOpen(this.callPhone);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.layout !== null) {
        Row().width(this.layout.width).height(this.layout.height)
          .drawModifier(this.painter.bind(this.layout)).hitTestBehavior(HitTestMode.None);
        AvatarView({ avatarPath: this.msg.contactAvatarPath, initials: this.layout.initials,
          colorSeed: this.msg.contactUserId !== 0 ? this.msg.contactUserId : this.layout.name.length * 31,
          avatarSize: this.layout.avatarSize })
          .position({ x: 0, y: this.layout.avatarY }).hitTestBehavior(HitTestMode.None);
        if (this.layout.phone !== '') {
          Stack() {
            Circle({ width: this.layout.actionSize, height: this.layout.actionSize }).fill('#123390EC');
            SymbolGlyph($r('sys.symbol.phone_fill')).fontSize(Math.min(17, this.layout.actionSize / 2)).fontColor([COLOR_PRIMARY]);
          }
          .width(this.layout.actionSize).height(this.layout.actionSize)
          .position({ x: this.layout.actionX, y: this.layout.actionY })
          .accessibilityText(str('cb_call_number', this.layout.phone))
          .onClick((): void => this.callContact());
        } else {
          SymbolGlyph($r(this.msg.contactUserId > 0 ? 'sys.symbol.chevron_right' : 'sys.symbol.person'))
            .fontSize(this.layout.actionSize).fontColor([COLOR_ICON_SECONDARY])
            .position({ x: this.layout.actionX, y: this.layout.actionY }).hitTestBehavior(HitTestMode.None);
        }
      }
    }
    .width(this.layout?.width ?? this.boxWidth).height(this.layout?.height ?? 0)
    .accessibilityText(this.layout?.accessibilityLabel ?? str('cb_unavailable'))
    .onClick((): void => { if (this.layout?.available) { this.openContact(); } });
  }
}
