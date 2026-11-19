import { DrawnLocationCardLayout, DrawnLocationCardLayouts } from './DrawnLocationCardLayout';
import { DrawnLocationPreview, DrawnLocationBadge, DrawnLocationStop } from './DrawnLocationDecorations';
import { DrawnMediaTexts, DrawnMediaTextPlan, DrawnMediaTextPainter } from './DrawnMediaText';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnDocumentMap } from './DrawnDocumentMap';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct LocationBubble {
  @Param preparedCard: DrawnLocationCardLayout | undefined = undefined;
  private cardLayouts: DrawnLocationCardLayouts = new DrawnLocationCardLayouts();
  @Computed private get cardLayout(): DrawnLocationCardLayout {
    return this.preparedCard ?? this.cardLayouts.prepare(this.getUIContext(), { title: this.venueTitle,
      address: this.venueAddress, live: this.livePeriod > 0, valid: this.valid, sharing: this.sharing,
      width: this.maxWidth, environment: this.paintEnvironment });
  }
  private paintEnv = chatEnv;
  private texts: DrawnMediaTexts = new DrawnMediaTexts();
  private textPainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private previewPainter: DrawnLocationPreview = new DrawnLocationPreview();
  private badgePainter: DrawnLocationBadge = new DrawnLocationBadge();
  private stopPainter: DrawnLocationStop = new DrawnLocationStop();
  private chevronPainter: DrawnMediaControl = new DrawnMediaControl();
  @Computed private get paintEnvironment(): string {
    return `${this.paintEnv.appearanceEpoch}:${this.paintEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  private cardWidth(): number {
    return this.cardLayout.width;
  }
  // Native paragraphs are cached independently. A countdown label update never
  // reshapes the title, rebuilds the map widget, or changes the reserved row box.
  private textPlan(): DrawnMediaTextPlan {
    return this.cardLayout.labels.prepare(this.getUIContext(), this.cardLayout.environment,
      Math.max(1, this.cardWidth() - 32 - (this.available() ? 21 : 0)), this.title(), 14.5,
      COLOR_TEXT_PRIMARY, this.detail(), 11.5, this.available() ? COLOR_TEXT_SECONDARY : '#D95B57',
      1, true, 3, 0, false, false, 1);
  }
  private badgeForPaint(): DrawnLocationBadge {
    return this.badgePainter.bind(this.getUIContext(), this.paintEnvironment,
      str(this.liveActive() ? 'loc_live_short' : 'ended'), this.liveActive(), this.cardWidth());
  }
  @Param latitude: number = 0;
  @Param longitude: number = 0;
  @Param accuracy: number = 0;
  @Param valid: boolean = false;
  @Param livePeriod: number = 0;
  @Param expiresIn: number = 0;
  @Param messageDate: number = 0;
  @Param nowSec: number = 0;
  @Param venueTitle: string = '';
  @Param venueAddress: string = '';
  @Param venueProvider: string = '';
  @Param proximityRadius: number = 0;
  @Param maxWidth: number = 250;
  @Param fitAvailableWidth: boolean = false;
  @Param realMap: boolean = false;
  @Param chatId: number = 0;

  // Only coordinates invalidate this object, never the countdown or live status.
  @Computed private get mapWidget(): DrawnDocumentWidget {
    return { key: 'location-map', kind: 'map', name: '', mimeType: '', size: 0,
      latitude: this.latitude, longitude: this.longitude, zoom: 15, width: this.cardLayout.width, height: this.cardLayout.mapHeight };
  }

  // 本机正在共享的就是这一条。停止入口必须长在气泡上——之前只放在会话页顶部
  // 的「⋯」菜单里，用户盯着气泡根本找不到。
  @Param sharing: boolean = false;
  @Param onOpen: () => void = (): void => {};
  @Param onStopLive: () => void = (): void => {};

  @Styles
  private cardNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private cardPressedStyle(): void {
    .scale({ x: 0.985, y: 0.985 })
    .opacity(0.84)
  }

  private available(): boolean {
    return this.valid || this.venueTitle.trim() !== '' || this.venueAddress.trim() !== '';
  }

  // 判活必须以 expires_in 为准，不能只看"发送时间 + 时长"这个窗口：主动停止
  // 共享后 live_period 不变，窗口照旧是开的，左上角就会一直亮着绿色"实时"。
  // 服务端结束共享时把 expires_in 置 0，这才是唯一能反映"提前停止"的信号。
  private liveActive(): boolean {
    if (this.livePeriod <= 0) {
      return false;
    }
    if (this.expiresIn <= 0) {
      return false;
    }
    if (this.messageDate > 0) {
      return this.nowSec < this.messageDate + this.livePeriod;
    }
    return true;
  }

  private liveRemaining(): number {
    if (!this.liveActive() || this.messageDate <= 0) {
      return 0;
    }
    return Math.max(0, this.messageDate + this.livePeriod - this.nowSec);
  }

  private liveLabel(): string {
    if (!this.liveActive()) {
      return str('loc_live_ended');
    }
    const remaining = this.liveRemaining();
    if (remaining <= 0) {
      return str('loc_live_sharing');
    }
    if (remaining >= 3600) {
      return plural('loc_live_hours', Math.ceil(remaining / 3600), Math.ceil(remaining / 3600));
    }
    return plural('loc_live_minutes', Math.max(1, Math.ceil(remaining / 60)), Math.max(1, Math.ceil(remaining / 60)));
  }

  private title(): string {
    if (this.venueTitle.trim() !== '') {
      return this.venueTitle.trim();
    }
    if (this.livePeriod > 0) {
      return this.liveActive() ? str('loc_live') : str('loc_live_ended');
    }
    return this.valid ? str('loc_location') : str('loc_unavailable');
  }

  private coordinateText(): string {
    if (!this.valid) {
      return '';
    }
    return `${this.latitude.toFixed(4)}, ${this.longitude.toFixed(4)}`;
  }

  private detail(): string {
    if (this.venueAddress.trim() !== '') {
      return this.venueAddress.trim();
    }
    if (this.livePeriod > 0) {
      return this.liveLabel();
    }
    if (this.accuracy > 0) {
      return plural('loc_accuracy', Math.max(1, Math.round(this.accuracy)), Math.max(1, Math.round(this.accuracy)));
    }
    if (this.proximityRadius > 0) {
      return plural('loc_proximity', Math.round(this.proximityRadius), Math.round(this.proximityRadius));
    }
    const coordinate = this.coordinateText();
    return coordinate !== '' ? coordinate : str('loc_no_coords');
  }

  @Builder
  private mapPreview(): void {
    Stack() {
      if (this.realMap && this.valid) {
        DrawnDocumentMap({ widget: this.mapWidget, chatId: this.chatId,
          boxWidth: Math.max(1, Math.min(270, this.maxWidth)), boxHeight: this.cardLayout.mapHeight,
          onOpen: (): void => this.onOpen() });
      } else {
        Row().width('100%').height(this.cardLayout.mapHeight)
          .drawModifier(this.previewPainter.bind(this.getUIContext(), this.paintEnvironment,
            this.cardWidth(), this.valid, str('loc_coords_missing')));
      }
      if (this.livePeriod > 0) {
        Row().width(this.badgeForPaint().widthVp).height(this.badgeForPaint().heightVp)
          .drawModifier(this.badgeForPaint())
          .hitTestBehavior(HitTestMode.None)
          .position({ x: 8, y: 8 });
      }
    }
    .width('100%').height(this.cardLayout.mapHeight)
    .borderRadius(10)
    .clip(true);
  }

  build() {
    Column({ space: 9 }) {
      this.mapPreview();
      if (this.cardLayout.showText) {
      Row({ space: 8 }) {
        Row().width(this.textPlan().width).height(this.textPlan().height)
          .drawModifier(this.textPainter.bind(this.textPlan()));
        if (this.available()) {
          Row().width(13).height(13)
            .drawModifier(this.chevronPainter.bind(this.getUIContext(), this.paintEnvironment,
              13, '#00000000', COLOR_ICON_SECONDARY, 'chevron'));
        }
      }
      .padding({ left: 2, right: 30, bottom: 10 })
      .height(this.cardLayout.textHeight);
      }
      if (this.sharing) {
        Row().width('100%').height(this.cardLayout.stopHeight)
        .drawModifier(this.stopPainter.bind(this.getUIContext(), this.paintEnvironment,
          str('loc_stop_sharing'), this.cardWidth(), this.cardLayout.stopHeight))
        .accessibilityText(str('loc_stop_sharing'))
        .accessibilityLevel('yes')
        .onClick((): void => { this.onStopLive(); });
      }
    }
    .width(this.cardWidth()).height(this.cardLayout.height)
    .stateStyles({
      normal: this.cardNormalStyle,
      pressed: this.cardPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .accessibilityText(this.available() ? `${this.title()}，${this.detail()}` : str('loc_unavailable'))
    .onClick((): void => {
      if (this.available()) {
        this.onOpen();
      }
    });
  }
}
