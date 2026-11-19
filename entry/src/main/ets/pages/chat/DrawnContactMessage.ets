import { contactVcardSummary } from '../../util/contactVcardSummary';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { contactLayoutFor, DrawnContactLayout, DrawnContactTextPainter } from './DrawnContactLayout';
import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { DrawnMediaControl } from './DrawnMediaControl';
import { DrawnCardBar } from './DrawnCardBar';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { AVATAR_PALETTE, COLOR_PRIMARY, COLOR_ICON_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';

// Like ChatMessageCell's contact delegate, actions resolve the current bound
// contact at activation time. Avatar arrival never changes the document source.
@ComponentV2
export struct DrawnContactMessage {
  @Param chatId: number = 0;
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 262;
  @Event onClaim: () => boolean = (): boolean => false;

  private env = chatEnv;
  private avatarSpecs: CachedImageSpecCache = new CachedImageSpecCache();
  private avatarPainter: DrawnCardBar = new DrawnCardBar();
  private actionPainter: DrawnMediaControl = new DrawnMediaControl();
  @Computed private get environment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get avatarSpec(): CachedImageSpec {
    const size = this.layout?.avatarSize ?? 48;
    return this.avatarSpecs.prepare({ path: this.msg.contactAvatarPath, boxWidth: size, boxHeight: size,
      fit: ImageFit.Cover, radius: size / 2, drawOnCanvas: true, sourceKey: `${this.chatId}:${this.msg.rowId}:${this.msg.contactUserId}` });
  }
  private avatarColor(): ResourceColor {
    const seed = this.msg.contactUserId !== 0 ? this.msg.contactUserId : (this.layout?.name.length ?? 0) * 31;
    return AVATAR_PALETTE[Math.abs(seed) % AVATAR_PALETTE.length];
  }
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
        Stack() { CachedImage({ spec: this.avatarSpec }); }
          .width(this.layout.avatarSize).height(this.layout.avatarSize)
          .drawModifier(this.avatarPainter.bind(this.getUIContext(), {
            width: this.layout.avatarSize, height: this.layout.avatarSize, environment: this.environment,
            radius: this.layout.avatarSize / 2, background: this.avatarColor(), center: this.layout.initials,
            centerFont: this.layout.avatarSize * 0.4, centerColor: '#FFFFFF'
          }))
          .borderRadius(this.layout.avatarSize / 2).clip(true)
          .position({ x: 0, y: this.layout.avatarY }).hitTestBehavior(HitTestMode.None);
        if (this.layout.phone !== '') {
          Row()
          .drawModifier(this.actionPainter.bind(this.getUIContext(), this.environment,
            this.layout.actionSize, '#123390EC', COLOR_PRIMARY, 'phone'))
          .width(this.layout.actionSize).height(this.layout.actionSize)
          .position({ x: this.layout.actionX, y: this.layout.actionY })
          .accessibilityText(str('cb_call_number', this.layout.phone))
          .onClick((): void => this.callContact());
        } else {
          Row().width(this.layout.actionSize).height(this.layout.actionSize)
            .drawModifier(this.actionPainter.bind(this.getUIContext(), this.environment,
              this.layout.actionSize, '#00000000', COLOR_ICON_SECONDARY, this.msg.contactUserId > 0 ? 'chevron' : 'person'))
            .position({ x: this.layout.actionX, y: this.layout.actionY }).hitTestBehavior(HitTestMode.None);
        }
      }
    }
    .width(this.layout?.width ?? this.boxWidth).height(this.layout?.height ?? 0)
    .accessibilityText(this.layout?.accessibilityLabel ?? str('cb_unavailable'))
    .onClick((): void => { if (this.layout?.available) { this.openContact(); } });
  }
}
