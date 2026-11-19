import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { DrawnCardBar } from './DrawnCardBar';
import { DrawnMediaControl } from './DrawnMediaControl';
import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { str } from '../../util/strings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { DrawnGiftLayout, DrawnGiftTextPainter } from './DrawnGiftLayout';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct GiftBubble {
  @Param chatId: number = 0;
  @Param prepared: DrawnGiftLayout | null = null;
  private env = chatEnv;
  private artworkPainter: DrawnCardBar = new DrawnCardBar();
  private retryPainter: DrawnCardBar = new DrawnCardBar();
  private badgePainter: DrawnCardBar = new DrawnCardBar();
  private statusPainter: DrawnCardBar = new DrawnCardBar();
  private copyPainter: DrawnCardBar = new DrawnCardBar();
  private dotPainter: DrawnMediaControl = new DrawnMediaControl();
  private progressPainter: DrawnMediaControl = new DrawnMediaControl();
  private photoSpecs: CachedImageSpecCache = new CachedImageSpecCache();
  @Computed private get environment(): string { return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`; }
  @Computed private get photoSpec(): CachedImageSpec {
    return this.photoSpecs.prepare({ path: this.photoPath, boxWidth: 112, boxHeight: 112, fit: ImageFit.Contain,
      drawOnCanvas: true, sourceKey: `${this.chatId}:${this.messageId}:${this.photoFileId}` });
  }
  private cardWidth(): number { return this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth)); }
  private textPainter: DrawnGiftTextPainter = new DrawnGiftTextPainter();
  @Param messageId: number = 0;
  @Param kind: string = '';
  @Param title: string = '';
  @Param value: string = '';
  @Param status: string = '';
  @Param text: string = '';
  @Param code: string = '';
  @Param refunded: boolean = false;
  @Param photoPath: string = '';
  @Param photoFileId: number = 0;
  @Param photoProgress: number = 0;
  @Param photoFailed: boolean = false;
  @Param maxWidth: number = 260;
  @Param fitAvailableWidth: boolean = false;
  @Event onBeforeAction: () => boolean = (): boolean => true;
  @Param onRetryPhoto: (messageId: number) => void = (_messageId: number): void => {};
  @Param onCopyCode: (code: string) => void = (_code: string): void => {};

  @Styles
  private normalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private pressedStyle(): void {
    .scale({ x: 0.975, y: 0.975 })
    .opacity(0.76)
  }

  private retryPhoto(): void {
    if (this.onBeforeAction()) { this.onRetryPhoto(this.messageId); }
  }
  private copyCode(): void {
    if (this.code !== '' && this.onBeforeAction()) { this.onCopyCode(this.code); }
  }

  private fallbackEmoji(): string {
    if (this.kind === 'premium' || this.kind === 'code') {
      return '💎';
    }
    if (this.kind === 'stars') {
      return '⭐';
    }
    if (this.kind === 'ton' || this.kind === 'collectible') {
      return '💠';
    }
    return '🎁';
  }

  private accent(): string {
    if (this.refunded) {
      return '#8C96A1';
    }
    return this.kind === 'stars' ? '#E8A62A'
      : (this.kind === 'premium' || this.kind === 'code' ? '#8D63D8'
        : (this.kind === 'ton' || this.kind === 'collectible' ? '#4B8FCB' : '#E06D8B'));
  }

  @Builder
  private artwork() {
    Stack() {
      CachedImage({ spec: this.photoSpec });
      if (this.photoPath === '' && this.photoFileId !== 0) {
        if (this.photoFailed) {
          Row().width(128).height(25)
          .drawModifier(this.retryPainter.bind(this.getUIContext(), {
            width: 128, height: 25, environment: this.environment, center: `↻ ${str('gift_retry_image')}`,
            centerFont: 10, centerColor: '#FFFFFF', background: '#78000000', radius: 10
          }))
          .position({ x: 8, y: 92 })
          .onClick((): void => this.retryPhoto());
        } else {
          Stack() {
            if (this.photoProgress <= 0) { DrawnLoadingSpinner({ ringSize: 23, ringColor: this.accent() }); }
          }.width(26).height(26).position({ x: 10, y: 91 })
            .drawModifier(this.progressPainter.bind(this.getUIContext(), this.environment, 26,
              '#00000000', this.accent(), '', this.photoProgress));
        }
      }
      Row().width(64).height(18).position({ x: 10, y: 9 })
        .drawModifier(this.badgePainter.bind(this.getUIContext(), {
          width: 64, height: 18, environment: this.environment, left: '🎁 GIFT', leftFont: 9.5, leftColor: this.accent()
        }));
    }
    .width('100%').height(this.prepared?.artworkHeight ?? 124)
    .drawModifier(this.artworkPainter.bind(this.getUIContext(), {
      width: this.cardWidth(), height: this.prepared?.artworkHeight ?? 124, environment: this.environment,
      center: this.photoPath === '' ? this.fallbackEmoji() : '', centerFont: 54, centerColor: this.accent(),
      background: `#1A${this.accent().substring(1)}`, radius: 12
    }))
    .borderRadius(12).clip(true);
  }

  build() {
    Column({ space: 8 }) {
      this.artwork();
      if (this.prepared !== null) {
        // The root painter uses the same paragraphs that established this size.
        Row().width('100%').height(this.prepared.textHeight);
      } else {
        Text(this.title.trim() !== '' ? this.title : $r('app.string.gift_regular_title'))
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.refunded ? COLOR_TEXT_SECONDARY : COLOR_TEXT_PRIMARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.value.trim() !== '') {
          Text(this.value).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.accent());
        }
        if (this.text.trim() !== '') {
          Text(this.text).fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ left: 9, right: 9, top: 7, bottom: 7 })
            .backgroundColor('#09000000').borderRadius(9);
        }
      }
      Row({ space: 5 }) {
        Row().width(6).height(6)
          .drawModifier(this.dotPainter.bind(this.getUIContext(), this.environment, 6,
            this.refunded ? '#8C96A1' : '#39A96B', '#00000000', ''));
        Row().width(Math.max(1, this.cardWidth() - 11 - (this.code !== '' ? (this.prepared?.copyWidth ?? 112) + 5 : 0)))
          .height(this.prepared?.statusHeight ?? 18)
          .drawModifier(this.statusPainter.bind(this.getUIContext(), {
            width: Math.max(1, this.cardWidth() - 11 - (this.code !== '' ? (this.prepared?.copyWidth ?? 112) + 5 : 0)),
            height: this.prepared?.statusHeight ?? 18, environment: this.environment,
            left: this.status.trim() !== '' ? this.status : str('gift_status_unknown'), leftFont: 11, leftColor: COLOR_TEXT_SECONDARY
          }));
        if (this.code !== '') {
          Row()
          .width(this.prepared?.copyWidth ?? 112).height(this.prepared?.copyHeight ?? 28)
          .drawModifier(this.copyPainter.bind(this.getUIContext(), {
            width: this.prepared?.copyWidth ?? 112, height: this.prepared?.copyHeight ?? 28, environment: this.environment,
            center: `▤ ${str('gift_copy_code')}`, centerFont: 11, centerColor: COLOR_PRIMARY, background: '#123390EC', radius: 9
          }))
          .accessibilityText(str('gift_copy_code'))
          .stateStyles({
            normal: this.normalStyle,
            pressed: this.pressedStyle
          })
          .animation({ duration: 110, curve: Curve.EaseOut })
          .onClick((): void => this.copyCode());
        }
      }.width('100%').height(this.prepared?.footerHeight).padding({ bottom: 9 });
    }
    .width(this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth)))
    .height(this.prepared?.height)
    .drawModifier(this.textPainter.bind(this.prepared, this.refunded, this.accent()))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.prepared?.titleText ?? this.title}，${this.value}，${this.status}`);
  }
}
