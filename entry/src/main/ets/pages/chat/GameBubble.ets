import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

@Component
export struct GameBubble {
  @Prop messageId: number = 0;
  @Prop title: string = '';
  @Prop shortName: string = '';
  @Prop description: string = '';
  @Prop gameText: string = '';
  @Prop photoPath: string = '';
  @Prop photoFileId: number = 0;
  @Prop photoProgress: number = 0;
  @Prop photoFailed: boolean = false;
  @Prop maxWidth: number = 260;
  @State opening: boolean = false;
  private photoActionAtMs: number = 0;
  private openingTimer: number = -1;
  onOpen: (messageId: number) => void = (_messageId: number): void => {};
  onRetryPhoto: (messageId: number) => void = (_messageId: number): void => {};

  @Styles
  private normalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private pressedStyle(): void {
    .scale({ x: 0.985, y: 0.985 })
    .opacity(0.8)
  }

  private gameAvailable(): boolean {
    return this.title.trim() !== '' || this.shortName.trim() !== '';
  }

  private displayTitle(): string {
    if (this.title.trim() !== '') {
      return this.title.trim();
    }
    if (this.shortName.trim() !== '') {
      return this.shortName.trim();
    }
    return str('game_unavailable');
  }

  private detailText(): string {
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
      Date.now() - this.photoActionAtMs < 300) {
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

  aboutToReuse(_params: Record<string, Object>): void {
    this.resetTransientState();
  }

  aboutToDisappear(): void {
    this.resetTransientState();
  }

  private retryCover(): void {
    this.photoActionAtMs = Date.now();
    this.onRetryPhoto(this.messageId);
  }

  @Builder
  private cover() {
    Stack() {
      if (this.photoPath !== '') {
        Image(this.photoPath.startsWith('/') ? `file://${this.photoPath}` : this.photoPath).draggable(false)
          .width('100%').height(116)
          .objectFit(ImageFit.Cover)
          .transition(TransitionEffect.OPACITY.animation({
            duration: 180, curve: Curve.EaseOut
          }));
      } else {
        Column({ space: 7 }) {
          Text('🎮').fontSize(34);
          if (this.photoFileId === 0) {
            Text(this.gameAvailable() ? $r('app.string.game_no_cover') : $r('app.string.game_unavailable'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        .width('100%').height(116)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E7EDF5');
      }

      if (this.photoPath === '' && this.photoFileId !== 0) {
        if (this.photoFailed) {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20).fontColor([Color.White]);
            Text($r('app.string.game_retry_cover')).fontSize(10.5).fontColor(Color.White);
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#80000000')
          .borderRadius(12)
          .onClick((): void => { this.retryCover(); });
        } else {
          Stack() {
            if (this.photoProgress > 0) {
              Progress({ value: this.photoProgress, total: 100, type: ProgressType.Ring })
                .width(30).height(30).color(Color.White);
              Text(`${this.photoProgress}%`).fontSize(9).fontColor(Color.White);
            } else {
              LoadingProgress().width(24).height(24).color(Color.White);
            }
          }
          .padding(7).backgroundColor('#68000000').borderRadius(22);
        }
      }
    }
    .width('100%').height(116)
    .borderRadius(10)
    .clip(true);
  }

  build() {
    Column({ space: 8 }) {
      this.cover();
      Text(this.displayTitle())
        .fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.gameAvailable() ? COLOR_TEXT_PRIMARY : '#B05D58')
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      Text(this.detailText())
        .fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_SECONDARY)
        .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      if (this.gameText.trim() !== '' && this.description.trim() !== '') {
        Text(this.gameText)
          .fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor('#0B000000').borderRadius(8);
      }
      Row({ space: 7 }) {
        if (this.opening) {
          LoadingProgress().width(16).height(16).color(Color.White);
        } else {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([Color.White]);
          Text(this.gameAvailable() ? $r('app.string.game_play') : $r('app.string.game_not_available'))
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
      }
      .width('100%').height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.gameAvailable() ? COLOR_PRIMARY : '#A7AFB8')
      .borderRadius(9);
      Row() {
        Text(this.shortName.trim() !== '' ? `@${this.shortName.trim()}` : $r('app.string.game_title'))
          .fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.width('100%').padding({ right: 64, bottom: 9 });
    }
    .width(Math.max(220, Math.min(278, this.maxWidth)))
    .alignItems(HorizontalAlign.Start)
    .stateStyles({
      normal: this.normalStyle,
      pressed: this.pressedStyle
    })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .accessibilityText(`${this.displayTitle()}，${this.detailText()}`)
    .onClick((): void => { this.openGame(); });
  }
}
