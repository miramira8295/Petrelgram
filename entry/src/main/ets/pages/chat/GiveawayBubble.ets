import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { monthDayTime } from '../../util/intlFormat';
import { DrawnGiveawayLayout, DrawnGiveawayTextPainter } from './DrawnGiveawayLayout';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct GiveawayBubble {
  @Param prepared: DrawnGiveawayLayout | null = null;
  private textPainter: DrawnGiveawayTextPainter = new DrawnGiveawayTextPainter();
  @Param messageId: number = 0;
  @Param state: string = '';
  @Param winnerCount: number = 0;
  @Param prize: string = '';
  @Param description: string = '';
  @Param selectionDate: number = 0;
  @Param unclaimedCount: number = 0;
  @Param originalMessageId: number = 0;
  @Param boostedChatId: number = 0;
  @Param refunded: boolean = false;
  @Param onlyNewMembers: boolean = false;
  @Param photoPath: string = '';
  @Param maxWidth: number = 260;
  @Param fitAvailableWidth: boolean = false;
  @Param fullDescription: boolean = false;
  @Event onBeforeAction: () => boolean = (): boolean => true;
  @Param onOpenOriginal: (chatId: number, messageId: number) => void =
    (_chatId: number, _messageId: number): void => {};

  @Styles
  private normalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private pressedStyle(): void {
    .scale({ x: 0.98, y: 0.98 })
    .opacity(0.76)
  }

  private openOriginal(): void {
    if (this.originalMessageId > 0 && this.onBeforeAction()) {
      this.onOpenOriginal(this.boostedChatId, this.originalMessageId);
    }
  }

  private title(): string {
    if (this.refunded) {
      return str('gw_cancelled');
    }
    if (this.state === 'active') {
      return str('gw_channel');
    }
    if (this.state === 'prize') {
      return str('gw_you_won');
    }
    return this.state === 'winners' ? str('gw_results') : str('gw_ended');
  }

  private statusText(): string {
    if (this.refunded) {
      return str('gw_refunded');
    }
    if (this.state === 'active') {
      return this.selectionDate > 0 ? str('gw_draw_at', this.dateText()) : str('gw_awaiting_draw');
    }
    if (this.state === 'prize') {
      return this.description.trim() !== '' ? this.description : str('gw_prize_credited');
    }
    return plural('gw_winners_n', Math.max(0, this.winnerCount), Math.max(0, this.winnerCount));
  }

  private dateText(): string {
    if (this.selectionDate <= 0) {
      return '';
    }
    return monthDayTime(new Date(this.selectionDate * 1000));
  }

  build() {
    Column({ space: 9 }) {
      Stack() {
        Column()
          .width('100%').height('100%')
          .linearGradient({
            angle: 135,
            colors: [[this.refunded ? '#E2E5E9' : '#DDEBFF', 0],
              [this.refunded ? '#F5F6F7' : '#F3E7FF', 1]]
          });
        if (this.photoPath !== '') {
          Image(this.photoPath.startsWith('/') ? `file://${this.photoPath}` : this.photoPath).draggable(false)
            .width(104).height(104).objectFit(ImageFit.Contain);
        } else {
          Text(this.state === 'prize' ? '🏆' : (this.refunded ? '↩️' : '🎉'))
            .fontSize(52);
        }
        Row({ space: 5 }) {
          SymbolGlyph($r(this.state === 'active'
            ? 'sys.symbol.clock_fill' : 'sys.symbol.checkmark_seal_fill'))
            .fontSize(11).fontColor([this.refunded ? '#8C96A1' : COLOR_PRIMARY]);
          Text(this.statusText()).fontSize(10.5)
            .maxLines(this.prepared ? 1 : undefined).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.prepared ? Math.max(1, this.maxWidth - 29 - this.prepared.badgeHeight) : undefined })
            .fontColor(this.refunded ? '#8C96A1' : COLOR_PRIMARY);
        }
        .padding({ left: 7, right: 7, top: 4, bottom: 4 })
        .height(this.prepared?.badgeHeight)
        .backgroundColor('#DFFFFFFF').borderRadius(9)
        .position({ x: 9, y: this.prepared ? Math.max(0, this.prepared.artworkHeight - this.prepared.badgeHeight - 8) : 94 });
      }
      .width('100%').height(this.prepared?.artworkHeight ?? 126)
      .borderRadius(12).clip(true);
      if (this.prepared !== null) {
        Row().width('100%').height(this.prepared.textHeight);
      } else {
        Text(this.title())
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.refunded ? COLOR_TEXT_SECONDARY : COLOR_TEXT_PRIMARY);
        Text(this.prize.trim() !== '' ? this.prize : $r('app.string.giveaway_prize_unavailable'))
          .fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.refunded ? COLOR_TEXT_SECONDARY : '#7B57C7')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.description.trim() !== '' && this.state !== 'prize') {
          Text(this.description).fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(this.fullDescription ? undefined : 3).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      Row({ space: 10 }) {
        if (this.winnerCount > 0) {
          Text(plural('gw_winners_n', this.winnerCount, this.winnerCount))
            .fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(this.prepared ? 1 : undefined).textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(this.prepared?.statsHeight).lineHeight(this.prepared?.statsHeight).layoutWeight(this.prepared ? 1 : 0);
        }
        if (this.onlyNewMembers) {
          Text($r('app.string.gw_new_members_only')).fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(this.prepared ? 1 : undefined).textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(this.prepared?.statsHeight).lineHeight(this.prepared?.statsHeight).layoutWeight(this.prepared ? 1 : 0);
        }
        if (this.unclaimedCount > 0) {
          Text(plural('gw_unclaimed_n', this.unclaimedCount, this.unclaimedCount))
            .fontSize(10.5).fontColor('#B06A32')
            .maxLines(this.prepared ? 1 : undefined).textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(this.prepared?.statsHeight).lineHeight(this.prepared?.statsHeight).layoutWeight(this.prepared ? 1 : 0);
        }
      }.width('100%').height(this.prepared?.statsHeight);
      if (this.prepared ? this.prepared.hasOriginal : this.originalMessageId > 0) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(13).fontColor([COLOR_PRIMARY]);
          Text($r('app.string.gw_view_original')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .maxLines(this.prepared ? 1 : undefined).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.prepared ? Math.max(1, this.maxWidth - 35) : undefined });
        }
        .width('100%').height(this.prepared?.buttonHeight ?? 34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#123390EC').borderRadius(9)
        .stateStyles({
          normal: this.normalStyle,
          pressed: this.pressedStyle
        })
        .animation({ duration: 110, curve: Curve.EaseOut })
        .onClick((): void => this.openOriginal());
      }
      Row().height(9).width('100%');
    }
    .width(this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth)))
    .height(this.prepared?.height)
    .drawModifier(this.textPainter.bind(this.prepared, this.state, this.refunded))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.title()}，${this.prize}，${this.statusText()}${this.prepared ? `，${this.description}` : ''}`);
  }
}
