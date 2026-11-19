import { GiveawayAudience } from '../../util/giveawayAudience';
import { DrawnGiveawayAudience } from './DrawnGiveawayAudience';
import { DrawnGiveawayAudienceLayout, DrawnGiveawayAudienceLayouts } from './DrawnGiveawayAudienceLayout';
import { DrawnCardBar } from './DrawnCardBar';
import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { monthDayTime } from '../../util/intlFormat';
import { DrawnGiveawayLayout, DrawnGiveawayTextPainter } from './DrawnGiveawayLayout';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct GiveawayBubble {
  @Param chatId: number = 0;
  @Param audience: GiveawayAudience | undefined = undefined;
  @Param ownerKey: string = '';
  @Event onPeer: (id: number, user: boolean) => void = (): void => {};
  private audiences: DrawnGiveawayAudienceLayouts = new DrawnGiveawayAudienceLayouts();
  @Computed private get audienceLayout(): DrawnGiveawayAudienceLayout | null {
    return this.prepared !== null ? this.prepared.audience : this.audiences.prepare(this.getUIContext(), this.audience, this.cardWidth(), this.environment);
  }
  @Param prepared: DrawnGiveawayLayout | null = null;
  private env = chatEnv;
  private artworkPainter: DrawnCardBar = new DrawnCardBar();
  private badgePainter: DrawnCardBar = new DrawnCardBar();
  private statsPainter: DrawnCardBar = new DrawnCardBar();
  private buttonPainter: DrawnCardBar = new DrawnCardBar();
  private photoSpecs: CachedImageSpecCache = new CachedImageSpecCache();
  @Computed private get environment(): string { return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`; }
  @Computed private get photoSpec(): CachedImageSpec {
    return this.photoSpecs.prepare({ path: this.photoPath, boxWidth: 104, boxHeight: 104, fit: ImageFit.Contain,
      drawOnCanvas: true, sourceKey: `${this.chatId}:${this.messageId}:${this.boostedChatId}` });
  }
  private cardWidth(): number { return this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth)); }
  private statsLabel(): string {
    const labels: string[] = [];
    if (this.winnerCount > 0) { labels.push(plural('gw_winners_n', this.winnerCount, this.winnerCount)); }
    if (this.onlyNewMembers) { labels.push(str('gw_new_members_only')); }
    if (this.unclaimedCount > 0) { labels.push(plural('gw_unclaimed_n', this.unclaimedCount, this.unclaimedCount)); }
    return labels.join(' · ');
  }
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
        CachedImage({ spec: this.photoSpec });
        Row().width(Math.max(1, this.cardWidth() - 18)).height(this.prepared?.badgeHeight ?? 24)
          .drawModifier(this.badgePainter.bind(this.getUIContext(), {
            width: Math.max(1, this.cardWidth() - 18), height: this.prepared?.badgeHeight ?? 24,
            environment: this.environment, left: `${this.state === 'active' ? '◷' : '✓'} ${this.statusText()}`,
            leftFont: 10.5, leftColor: this.refunded ? '#8C96A1' : COLOR_PRIMARY,
            background: '#DFFFFFFF', radius: 9, paddingLeft: 7, paddingRight: 7
          }))
          .position({ x: 9, y: this.prepared ? Math.max(0, this.prepared.artworkHeight - this.prepared.badgeHeight - 8) : 94 });
      }
      .width('100%').height(this.prepared?.artworkHeight ?? 126)
      .drawModifier(this.artworkPainter.bind(this.getUIContext(), {
        width: this.cardWidth(), height: this.prepared?.artworkHeight ?? 126, environment: this.environment,
        background: this.refunded ? '#EDF0F3' : '#ECEAFF', radius: 12,
        center: this.photoPath !== '' ? '' : this.state === 'prize' ? '🏆' : this.refunded ? '↩️' : '🎉',
        centerFont: 52, centerColor: COLOR_PRIMARY
      }))
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
      if (this.audienceLayout !== null) {
        DrawnGiveawayAudience({ model: this.audienceLayout, ownerKey: this.ownerKey || `${this.chatId}:${this.messageId}`,
          onActivate: (id: number, user: boolean): void => { if (this.onBeforeAction()) { this.onPeer(id, user); } } });
      }
      Row().width('100%').height(this.prepared?.statsHeight ?? (this.statsLabel() !== '' ? 18 : 0))
        .drawModifier(this.statsPainter.bind(this.getUIContext(), {
          width: this.cardWidth(), height: this.prepared?.statsHeight ?? 18, environment: this.environment,
          left: this.statsLabel(), leftFont: 10.5, leftColor: COLOR_TEXT_SECONDARY
        })).accessibilityText(this.statsLabel());
      if (this.prepared ? this.prepared.hasOriginal : this.originalMessageId > 0) {
        Row().width('100%').height(this.prepared?.buttonHeight ?? 34)
        .drawModifier(this.buttonPainter.bind(this.getUIContext(), {
          width: this.cardWidth(), height: this.prepared?.buttonHeight ?? 34, environment: this.environment,
          center: `↗ ${str('gw_view_original')}`, centerFont: 12, centerColor: COLOR_PRIMARY, background: '#123390EC', radius: 9
        }))
        .accessibilityText(str('gw_view_original'))
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
