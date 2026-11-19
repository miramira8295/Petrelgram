import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { DrawnCardBar } from './DrawnCardBar';
import { DrawnMediaControl } from './DrawnMediaControl';
import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { DrawnPollText } from './DrawnPollText';
import { DrawnGameLayout } from './DrawnGameLayout';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 成员 @Styles 迁全局（V2 不支持，两组均无状态依赖）。
@Styles
function gameNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function gamePressedStyle() { .scale({ x: 0.985, y: 0.985 }).opacity(0.8) }

// P4 批 6a：迁 @ComponentV2（@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct GameBubble {
  @Param chatId: number = 0;
  @Param richMessage: MessageEntry | null = null;
  @Param prepared: DrawnGameLayout | null = null;
  @Event onLink: (url: string, hidesUrl: boolean) => void = (): void => {};
  private env = chatEnv;
  private coverPainter: DrawnCardBar = new DrawnCardBar();
  private coverStatusPainter: DrawnCardBar = new DrawnCardBar();
  private retryPainter: DrawnCardBar = new DrawnCardBar();
  private buttonPainter: DrawnCardBar = new DrawnCardBar();
  private footerPainter: DrawnCardBar = new DrawnCardBar();
  private progressPainter: DrawnMediaControl = new DrawnMediaControl();
  private coverSpecs: CachedImageSpecCache = new CachedImageSpecCache();
  @Computed private get environment(): string { return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`; }
  @Computed private get coverSpec(): CachedImageSpec {
    return this.coverSpecs.prepare({ path: this.photoPath, boxWidth: this.richWidth(),
      boxHeight: this.prepared?.coverHeight ?? 116, fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `${this.chatId}:${this.richMessage?.rowId ?? this.messageId}:${this.photoFileId}` });
  }
  private emptyEntities: TdObject[] = [];
  @Param messageId: number = 0;
  @Param title: string = '';
  @Param shortName: string = '';
  @Param description: string = '';
  @Param gameText: string = '';
  @Param photoPath: string = '';
  @Param photoFileId: number = 0;
  @Param photoProgress: number = 0;
  @Param photoFailed: boolean = false;
  @Param maxWidth: number = 260;
  @Param fitAvailableWidth: boolean = false;
  @Event onBeforeAction: () => boolean = (): boolean => true;
  @Local opening: boolean = false;
  private photoActionAtMs: number = 0;
  private openingTimer: number = -1;
  @Param onOpen: (messageId: number) => void = (_messageId: number): void => {};
  @Param onRetryPhoto: (messageId: number) => void = (_messageId: number): void => {};

  private gameAvailable(): boolean {
    if (this.prepared !== null) { return this.prepared.available; }
    return this.title.trim() !== '' || this.shortName.trim() !== '';
  }

  private displayTitle(): string {
    if (this.prepared !== null) { return this.prepared.titleText; }
    if (this.title.trim() !== '') {
      return this.title.trim();
    }
    if (this.shortName.trim() !== '') {
      return this.shortName.trim();
    }
    return str('game_unavailable');
  }

  private detailText(): string {
    if (this.prepared !== null) { return this.prepared.detailText; }
    if (this.description.trim() !== '') {
      return this.description.trim();
    }
    if (this.gameText.trim() !== '') {
      return this.gameText.trim();
    }
    return this.gameAvailable() ? str('game_interactive') : str('game_unreadable');
  }

  private openGame(): void {
    if (!this.gameAvailable() || this.opening ||
      Date.now() - this.photoActionAtMs < 300 || !this.onBeforeAction()) {
      return;
    }
    this.opening = true;
    this.onOpen(this.messageId);
    this.openingTimer = setTimeout((): void => {
      this.openingTimer = -1;
      this.opening = false;
    }, 900);
  }

  private resetTransientState(): void {
    if (this.openingTimer !== -1) {
      clearTimeout(this.openingTimer);
      this.openingTimer = -1;
    }
    this.opening = false;
    this.photoActionAtMs = 0;
  }

  aboutToRecycle(): void {
    this.resetTransientState();
  }

  // 【两条复用路径都要覆盖】aboutToReuse 只在 @ReusableV2 那条路上触发；打开
  // Repeat 自己的复用（virtualScroll reusable:true）时它**不会被调用**（官方：
  // 「Repeat 自身能够进行复用，不会走到自定义组件复用的生命周期」）。而
  // @ReusableV2 复用的重置期间 @Monitor 又是静默的——两者互补，缺一不可。
  @Monitor('messageId')
  onMessageChanged(): void {
    this.resetTransientState();
  }

  aboutToReuse(): void {
    // @Local opening 由框架重置；只剩无装饰器的定时器与时间戳要手工归零。
    this.resetTransientState();
  }

  aboutToDisappear(): void {
    this.resetTransientState();
  }

  private claimTextLink(): boolean {
    if (!this.onBeforeAction()) { return false; }
    this.photoActionAtMs = Date.now();
    return true;
  }

  private richWidth(inset: number = 0): number {
    const width = this.fitAvailableWidth ? this.maxWidth : Math.max(220, Math.min(278, this.maxWidth));
    return Math.max(1, width - inset);
  }

  private retryCover(): void {
    if (!this.onBeforeAction()) { return; }
    this.photoActionAtMs = Date.now();
    this.onRetryPhoto(this.messageId);
  }

  @Builder
  private cover() {
    Stack() {
      CachedImage({ spec: this.coverSpec });
      if (this.photoPath === '' && this.photoFileId === 0) {
        Row().width('100%').height(24)
          .drawModifier(this.coverStatusPainter.bind(this.getUIContext(), {
            width: this.richWidth(), height: 24, environment: this.environment,
            center: str(this.gameAvailable() ? 'game_no_cover' : 'game_unavailable'), centerFont: 11, centerColor: COLOR_TEXT_SECONDARY
          })).position({ x: 0, y: (this.prepared?.coverHeight ?? 116) - 28 });
      }

      if (this.photoPath === '' && this.photoFileId !== 0) {
        if (this.photoFailed) {
          Row().width(Math.min(150, this.richWidth())).height(40)
          .drawModifier(this.retryPainter.bind(this.getUIContext(), {
            width: Math.min(150, this.richWidth()), height: 40, environment: this.environment,
            center: `↻ ${str('game_retry_cover')}`, centerFont: 11, centerColor: '#FFFFFF', background: '#80000000', radius: 12
          }))
          .onClick((): void => { this.retryCover(); });
        } else {
          Stack() {
            if (this.photoProgress <= 0) { DrawnLoadingSpinner({ ringSize: 24, ringColor: Color.White }); }
          }
          .width(44).height(44)
          .drawModifier(this.progressPainter.bind(this.getUIContext(), this.environment, 44,
            '#68000000', '#FFFFFF', 'percent', this.photoProgress, false,
            this.photoProgress > 0 ? `${this.photoProgress}%` : ''));
        }
      }
    }
    .width('100%').height(this.prepared?.coverHeight ?? 116)
    .drawModifier(this.coverPainter.bind(this.getUIContext(), {
      width: this.richWidth(), height: this.prepared?.coverHeight ?? 116, environment: this.environment,
      background: '#E7EDF5', center: this.photoPath === '' ? '🎮' : '', centerFont: 34, centerColor: COLOR_PRIMARY
    }))
    .borderRadius(10)
    .clip(true);
  }

  build() {
    Column({ space: 8 }) {
      this.cover();
      if (this.prepared !== null && this.richMessage !== null) {
        DrawnPollText({ msg: this.richMessage, content: this.prepared.titleText,
          preparedLayout: this.prepared.title, boxWidth: this.richWidth(), textSize: 15, bold: true,
          textColor: this.prepared.available ? COLOR_TEXT_PRIMARY : '#B05D58' });
      } else {
        Text(this.displayTitle())
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.gameAvailable() ? COLOR_TEXT_PRIMARY : '#B05D58')
          .maxLines(this.richMessage !== null ? undefined : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      if (this.richMessage !== null) {
        if (this.prepared ? this.prepared.description !== null : this.description.trim() !== '') {
          DrawnPollText({ msg: this.richMessage, content: this.description, boxWidth: this.richWidth(), textSize: 11.5,
            preparedLayout: this.prepared?.description ?? null,
            onBeforeLink: (): boolean => this.claimTextLink(),
            onLink: (url: string, hidesUrl: boolean): void => this.onLink(url, hidesUrl) });
        }
        if (this.prepared ? this.prepared.body !== null : this.gameText.trim() !== '') {
          DrawnPollText({ msg: this.richMessage, content: this.gameText,
            preparedLayout: this.prepared?.body ?? null,
            entities: this.richMessage.gameTextEntities ?? this.emptyEntities,
            boxWidth: this.richWidth(this.prepared === null && this.description.trim() !== '' ? 16 : 0), textSize: 11.5,
            textColor: COLOR_TEXT_PRIMARY,
            onBeforeLink: (): boolean => this.claimTextLink(),
            onLink: (url: string, hidesUrl: boolean): void => this.onLink(url, hidesUrl) })
            .padding((this.prepared === null && this.description.trim() !== '') ?
              { left: 8, right: 8, top: 6, bottom: 6 } : 0);
        } else if (this.prepared !== null && this.prepared.fallback !== null) {
          DrawnPollText({ msg: this.richMessage, content: this.prepared.detailText,
            preparedLayout: this.prepared.fallback, boxWidth: this.richWidth(), textSize: 11.5 });
        } else if (this.prepared === null && this.description.trim() === '') {
          Text(this.detailText()).fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        }
      } else {
        Text(this.detailText())
          .fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        if (this.gameText.trim() !== '' && this.description.trim() !== '') {
          Text(this.gameText).fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 }).backgroundColor('#0B000000').borderRadius(8);
        }
      }
      Row({ space: 7 }) {
        if (this.opening) {
          DrawnLoadingSpinner({ ringSize: 16, ringColor: Color.White });
        }
      }
      .width('100%').height(this.prepared?.buttonHeight ?? 36)
      .justifyContent(FlexAlign.Center)
      .drawModifier(this.buttonPainter.bind(this.getUIContext(), {
        width: this.richWidth(), height: this.prepared?.buttonHeight ?? 36, environment: this.environment,
        center: this.opening ? '' : `▶ ${str(this.gameAvailable() ? 'game_play' : 'game_not_available')}`,
        centerFont: 13, centerColor: '#FFFFFF', background: this.gameAvailable() ? COLOR_PRIMARY : '#A7AFB8', radius: 9
      }));
      Row().width('100%').height(this.prepared?.footerHeight ?? 24)
        .drawModifier(this.footerPainter.bind(this.getUIContext(), {
          width: this.richWidth(), height: this.prepared?.footerHeight ?? 24, environment: this.environment,
          left: this.prepared?.footerText ?? (this.shortName.trim() !== '' ? `@${this.shortName.trim()}` : str('game_title')),
          leftFont: 10.5, leftColor: COLOR_TEXT_SECONDARY, paddingRight: 64, paddingBottom: 9
        }));
    }
    .width(this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth)))
    .height(this.prepared?.height)
    .alignItems(HorizontalAlign.Start)
    .stateStyles({
      normal: gameNormalStyle,
      pressed: gamePressedStyle
    })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .accessibilityText(`${this.displayTitle()}，${this.detailText()}`)
    .onClick((): void => { this.openGame(); });
  }
}
