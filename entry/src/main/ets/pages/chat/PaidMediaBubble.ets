import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { DrawnMediaTexts, DrawnMediaTextPlan, DrawnMediaTextPainter } from './DrawnMediaText';
import { DrawnMediaPlaceholder } from './DrawnMediaPlaceholder';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnTextLine, DrawnTextLineCache } from './DrawnTextLine';
import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { DrawnCardBar } from './DrawnCardBar';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnPaidMediaLayout, DrawnPaidMediaTextPainter } from './DrawnPaidMediaLayout';
import { PaidMediaSet } from '../../util/paidMediaModel';
import { DrawnPaidMediaGridLayouts, DrawnPaidMediaGridPlan } from './DrawnPaidMediaGridLayout';
import { DrawnPaidMediaGrid } from './DrawnPaidMediaGrid';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct PaidMediaBubble {
  private env = chatEnv;
  private countUnits: DrawnTextUnits = new DrawnTextUnits();
  private countLabels: DrawnTextLineCache = new DrawnTextLineCache();
  private countPainter: DrawnCardBar = new DrawnCardBar();
  private actionPainter: DrawnCardBar = new DrawnCardBar();
  private lockPainter: DrawnMediaControl = new DrawnMediaControl();
  private playPainter: DrawnMediaControl = new DrawnMediaControl();
  private retryPainter: DrawnCardBar = new DrawnCardBar();
  @Computed private get environment(): string { return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`; }
  private posterSpecs: CachedImageSpecCache = new CachedImageSpecCache();
  private fallbackLabels: DrawnMediaTexts = new DrawnMediaTexts();
  private fallbackNotes: DrawnMediaTexts = new DrawnMediaTexts();
  private fallbackLabelPainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private fallbackNotePainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private placeholderPainter: DrawnMediaControl = new DrawnMediaControl();
  @Computed private get posterSpec(): CachedImageSpec {
    return this.posterSpecs.prepare({ path: this.photoPath, boxWidth: this.cardWidth(), boxHeight: this.artworkHeight(),
      fit: ImageFit.Cover, drawOnCanvas: true, sourceKey: `${this.ownerKey}:${this.messageId}:${this.photoFileId}` });
  }
  @Computed private get fallbackText(): DrawnMediaTextPlan {
    return this.fallbackLabels.prepare(this.getUIContext(), this.environment, this.cardWidth(),
      str(this.locked ? 'paid_media' : 'paid_media_unlocked'), 14, COLOR_TEXT_PRIMARY,
      this.caption.trim() !== '' ? this.caption : '', 11.5, COLOR_TEXT_SECONDARY, 1, true, 2, 0, false, false, 2);
  }
  @Computed private get fallbackNote(): DrawnMediaTextPlan {
    return this.fallbackNotes.prepare(this.getUIContext(), this.environment, this.cardWidth(),
      str('paid_viewer_note'), 10.5, COLOR_TEXT_SECONDARY, '', 11, COLOR_TEXT_SECONDARY, 2);
  }
  private cardWidth(): number { return this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(224, Math.min(280, this.maxWidth)); }
  @Param prepared: DrawnPaidMediaLayout | null = null;
  private textPainter: DrawnPaidMediaTextPainter = new DrawnPaidMediaTextPainter();
  @Param mediaSet: PaidMediaSet | null = null;
  @Param ownerKey: string = '';
  private fallbackGrids: DrawnPaidMediaGridLayouts = new DrawnPaidMediaGridLayouts();
  @Param messageId: number = 0;
  @Param locked: boolean = true;
  @Param starCount: number = 0;
  @Param mediaCount: number = 0;
  @Param mediaKind: string = '';
  @Param mediaReady: boolean | undefined = undefined;
  @Param completeSet: boolean = false;
  @Param caption: string = '';
  @Param photoPath: string = '';
  @Param photoFileId: number = 0;
  @Param photoProgress: number = 0;
  @Param photoFailed: boolean = false;
  @Param pending: boolean = false;
  @Param maxWidth: number = 260;
  @Param fitAvailableWidth: boolean = false;
  @Event onBeforeAction: () => boolean = (): boolean => true;
  @Param onUnlock: (messageId: number) => void = (_messageId: number): void => {};
  @Param onOpen: (messageId: number) => void = (_messageId: number): void => {};
  @Param onOpenAt: ((messageId: number, index: number) => void) | null = null;
  @Param onRetryPhoto: (messageId: number) => void = (_messageId: number): void => {};

  @Styles
  private normalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private pressedStyle(): void {
    .scale({ x: 0.985, y: 0.985 })
    .opacity(0.82)
  }

  @Computed private get countLabel(): DrawnTextLine {
    const units = this.countUnits.prepare(this.getUIContext(), this.environment);
    return this.countLabels.prepare(this.countText(), Math.max(1, this.cardWidth() - (this.locked ? 32 : 51)) * units.density,
      units.fp2px(this.locked ? 13 : 10.5), { alpha: 255, red: 255, green: 255, blue: 255 }, this.environment, true);
  }
  @Computed private get countWidth(): number {
    const label = this.countLabel;
    return Math.max(1, Math.min(this.cardWidth() - 16, label.widthPx / this.countUnits.density + (this.locked ? 16 : 35)));
  }

  private countText(): string {
    const count = Math.max(1, this.mediaCount);
    return str('paid_items', count, this.locked ? str('paid_locked_word') : str('paid_unlocked_word'));
  }

  private available(): boolean {
    if (this.locked) {
      return this.starCount > 0;
    }
    if (this.mediaReady !== undefined) { return this.mediaReady; }
    return (this.mediaKind === 'photo' || this.mediaKind === 'video') &&
      (this.photoFileId !== 0 || this.photoPath !== '');
  }

  private actionText(): string {
    if (this.locked) {
      return this.starCount > 0 ? str('paid_unlock_stars', this.starCount) : str('paid_cannot_unlock');
    }
    if (!this.available()) {
      return str('paid_content_unavailable');
    }
    return this.mediaKind === 'video' ? str('paid_play_video') : str('paid_view_photo');
  }

  @Computed private get mediaGrid(): DrawnPaidMediaGridPlan | null {
    if (this.mediaSet === null || this.mediaSet.items.length === 0) { return null; }
    return this.prepared?.grid ?? this.fallbackGrids.prepare(this.mediaSet,
      this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(224, Math.min(280, this.maxWidth)));
  }
  private artworkHeight(): number { return this.mediaGrid?.height ?? this.prepared?.artworkHeight ?? 156; }
  private trigger(index: number = 0): void {
    const selectedReady = this.mediaSet !== null && !this.locked ? (this.mediaSet.viewerIndices[index] ?? -1) >= 0 : this.available();
    if (!selectedReady || this.pending || !this.onBeforeAction()) {
      return;
    }
    if (this.locked) {
      this.onUnlock(this.messageId);
    } else {
      if (this.onOpenAt !== null && this.onOpenAt !== undefined) { this.onOpenAt(this.messageId, index); }
      else { this.onOpen(this.messageId); }
    }
  }

  @Builder
  private lockedArtwork() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 135,
          colors: [['#D9C8F7', 0], ['#BDDDF8', 0.48], ['#F4D6E9', 1]]
        });
      if (this.mediaGrid !== null && this.mediaSet !== null) {
        DrawnPaidMediaGrid({ mediaSet: this.mediaSet, gridPlan: this.mediaGrid, ownerKey: this.ownerKey,
          locked: true, density: this.prepared?.density ?? this.getUIContext().vp2px(1), onOpen: (index: number): void => this.trigger(index) });
      } else {
        Row({ space: 8 }) {
          ForEach([0, 1, 2, 3], (index: number) => {
            Column()
              .width(index % 2 === 0 ? 44 : 54)
              .height(index % 2 === 0 ? 72 : 88)
              .backgroundColor(index % 2 === 0 ? '#52FFFFFF' : '#3AFFFFFF')
              .borderRadius(12)
              .rotate({ angle: index % 2 === 0 ? -9 : 8 });
          }, (index: number): string => `${index}`);
        }
        .opacity(0.8)
        .blur(8);
      }
      Column({ space: 7 }) {
        Row().width(44).height(44)
          .drawModifier(this.lockPainter.bind(this.getUIContext(), this.environment, 44, '#B8000000', '#FFFFFF', 'lock'));
        Row().width(this.countWidth).height(Math.max(24, this.prepared?.badgeHeight ?? 24))
          .drawModifier(this.countPainter.bind(this.getUIContext(), {
            width: this.countWidth, height: Math.max(24, this.prepared?.badgeHeight ?? 24),
            environment: this.environment, centerPrepared: this.countLabel, centerColor: '#FFFFFF',
            background: '#70000000', radius: 9, paddingLeft: 8, paddingRight: 8
          }));
      }.hitTestBehavior(HitTestMode.None);
    }
    .width('100%').height(this.artworkHeight())
    .borderRadius(12).clip(true);
  }

  @Builder
  private unlockedArtwork() {
    Stack() {
      if (this.mediaGrid !== null && this.mediaSet !== null) {
        DrawnPaidMediaGrid({ mediaSet: this.mediaSet, gridPlan: this.mediaGrid, ownerKey: this.ownerKey,
          locked: false, density: this.prepared?.density ?? this.getUIContext().vp2px(1), onOpen: (index: number): void => this.trigger(index) });
      } else if (this.photoPath !== '') {
        CachedImage({ spec: this.posterSpec })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }));
      } else {
        Column({ space: 8 }) {
          Row().width(36).height(36).hitTestBehavior(HitTestMode.None)
            .drawModifier(this.placeholderPainter.bind(this.getUIContext(), this.environment, 36,
              '#00000000', COLOR_ICON_SECONDARY, this.mediaKind === 'video' ? 'play' : 'photo'));
          DrawnMediaPlaceholder({ primaryKey: this.photoFileId === 0 ? 'paid_media_unavailable' : 'paid_loading_unlocked',
            primarySize: 11.5, boxWidth: this.cardWidth(), boxHeight: 36 });
        }.width('100%').height(this.artworkHeight()).justifyContent(FlexAlign.Center).backgroundColor('#E9EDF2');
      }
      if (this.mediaGrid === null && this.photoPath === '' && this.photoFileId !== 0) {
        if (this.photoFailed) {
          Row().width(Math.min(130, this.cardWidth() - 16)).height(40)
          .drawModifier(this.retryPainter.bind(this.getUIContext(), {
            width: Math.min(130, this.cardWidth() - 16), height: 40, environment: this.environment,
            center: `↻ ${str('settings_retry')}`, centerFont: 10.5, centerColor: '#FFFFFF', background: '#85000000', radius: 12
          }))
          .onClick((): void => { if (this.onBeforeAction()) { this.onRetryPhoto(this.messageId); } });
        } else if (this.photoProgress > 0) {
          DrawnLoadingSpinner({ ringSize: 34, ringColor: '#FFFFFF', ringStroke: 2.5,
            percent: this.photoProgress, showPercent: true })
          .padding(7).backgroundColor('#70000000').borderRadius(24);
        } else {
          DrawnLoadingSpinner({ ringSize: 26, ringColor: Color.White })
            .padding(8).backgroundColor('#70000000').borderRadius(22);
        }
      }
      if (this.mediaGrid === null && this.mediaKind === 'video' && this.available()) {
        Row().width(42).height(42)
          .drawModifier(this.playPainter.bind(this.getUIContext(), this.environment, 42, '#98000000', '#FFFFFF', 'play'));
      }
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width(20).height(20)
          .drawModifier(this.lockPainter.bind(this.getUIContext(), this.environment, 20, '#00000000', '#FFFFFF', 'lock-open'))
          .position({ x: 5, y: Math.max(0, ((this.prepared?.badgeHeight ?? 24) - 20) / 2) });
      }
      .width(this.countWidth).height(this.prepared?.badgeHeight ?? 24)
      .drawModifier(this.countPainter.bind(this.getUIContext(), {
        width: this.countWidth, height: this.prepared?.badgeHeight ?? 24, environment: this.environment,
        leftPrepared: this.countLabel, leftColor: '#FFFFFF', background: '#85000000', radius: 9, paddingLeft: 28, paddingRight: 7
      }))
      .position({ x: 8, y: this.prepared ? Math.max(0, this.artworkHeight() - this.prepared.badgeHeight - 8) : this.artworkHeight() - 32 })
      .hitTestBehavior(HitTestMode.None);
    }
    .width('100%').height(this.artworkHeight())
    .borderRadius(12).clip(true);
  }

  build() {
    Column({ space: 9 }) {
      if (this.locked) {
        this.lockedArtwork();
      } else {
        this.unlockedArtwork();
      }
      if (this.prepared !== null) {
        Row().width('100%').height(this.prepared.textHeight);
      } else {
        Column({ space: 2 }) {
          Row().width(this.fallbackText.width).height(this.fallbackText.height)
            .drawModifier(this.fallbackLabelPainter.bind(this.fallbackText))
            .accessibilityText(`${str(this.locked ? 'paid_media' : 'paid_media_unlocked')}. ${this.caption}`);
          if (!this.locked && this.mediaCount > 1 && !this.completeSet) {
            Row().width(this.fallbackNote.width).height(this.fallbackNote.height)
              .drawModifier(this.fallbackNotePainter.bind(this.fallbackNote)).accessibilityText(str('paid_viewer_note'));
          }
        }.width('100%').alignItems(HorizontalAlign.Start);
      }
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.pending) {
          DrawnLoadingSpinner({ ringSize: 16, ringColor: '#FFFFFF' })
            .position({ x: 8, y: Math.max(0, ((this.prepared?.buttonHeight ?? 36) - 16) / 2) });
        }
      }
      .width('100%').height(this.prepared?.buttonHeight ?? 36)
      .drawModifier(this.actionPainter.bind(this.getUIContext(), {
        width: this.cardWidth(), height: this.prepared?.buttonHeight ?? 36, environment: this.environment,
        center: this.pending ? str('paid_checking') : this.actionText(), centerFont: 12.5, centerColor: '#FFFFFF',
        background: this.available() ? COLOR_PRIMARY : '#A7AFB8', radius: 10, paddingLeft: this.pending ? 30 : 8, paddingRight: 8
      }))
      .accessibilityText(this.pending ? str('paid_checking') : this.actionText())
      .stateStyles({
        normal: this.normalStyle,
        pressed: this.pressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .onClick((): void => { this.trigger(); });
      Row().height(9).width('100%');
    }
    .width(this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(224, Math.min(280, this.maxWidth)))
    .height(this.prepared?.height)
    .drawModifier(this.textPainter.bind(this.prepared, this.locked))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.countText()}，${this.actionText()}`);
  }
}
