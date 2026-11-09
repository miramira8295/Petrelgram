import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct PaidMediaBubble {
  @Param messageId: number = 0;
  @Param locked: boolean = true;
  @Param starCount: number = 0;
  @Param mediaCount: number = 0;
  @Param mediaKind: string = '';
  @Param caption: string = '';
  @Param photoPath: string = '';
  @Param photoFileId: number = 0;
  @Param photoProgress: number = 0;
  @Param photoFailed: boolean = false;
  @Param pending: boolean = false;
  @Param maxWidth: number = 260;
  @Param onUnlock: (messageId: number) => void = (_messageId: number): void => {};
  @Param onOpen: (messageId: number) => void = (_messageId: number): void => {};
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

  private countText(): string {
    const count = Math.max(1, this.mediaCount);
    return str('paid_items', count, this.locked ? str('paid_locked_word') : str('paid_unlocked_word'));
  }

  private available(): boolean {
    if (this.locked) {
      return this.starCount > 0;
    }
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

  private trigger(): void {
    if (!this.available() || this.pending) {
      return;
    }
    if (this.locked) {
      this.onUnlock(this.messageId);
    } else {
      this.onOpen(this.messageId);
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
      Column({ space: 7 }) {
        Stack() {
          Circle({ width: 44, height: 44 }).fill('#B8000000');
          SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(19).fontColor([Color.White]);
        }
        Text(this.countText())
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .textShadow({ radius: 5, color: '#66000000', offsetX: 0, offsetY: 1 });
      }
    }
    .width('100%').height(156)
    .borderRadius(12).clip(true);
  }

  @Builder
  private unlockedArtwork() {
    Stack() {
      if (this.photoPath !== '') {
        Image(this.photoPath.startsWith('/') ? `file://${this.photoPath}` : this.photoPath).draggable(false)
          .width('100%').height(156).objectFit(ImageFit.Cover)
          .transition(TransitionEffect.OPACITY.animation({
            duration: 180, curve: Curve.EaseOut
          }));
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r(this.mediaKind === 'video'
            ? 'sys.symbol.video_fill' : 'sys.symbol.photo_fill'))
            .fontSize(30).fontColor([COLOR_ICON_SECONDARY]);
          Text(this.photoFileId === 0 ? $r('app.string.paid_media_unavailable') : $r('app.string.paid_loading_unlocked'))
            .fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%').height(156)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E9EDF2');
      }
      if (this.photoPath === '' && this.photoFileId !== 0) {
        if (this.photoFailed) {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(19).fontColor([Color.White]);
            Text($r('app.string.settings_retry')).fontSize(10.5).fontColor(Color.White);
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#85000000').borderRadius(12)
          .onClick((): void => { this.onRetryPhoto(this.messageId); });
        } else if (this.photoProgress > 0) {
          Stack() {
            Progress({ value: this.photoProgress, total: 100, type: ProgressType.Ring })
              .width(34).height(34).color(Color.White);
            Text(`${this.photoProgress}%`).fontSize(9).fontColor(Color.White);
          }
          .padding(7).backgroundColor('#70000000').borderRadius(24);
        } else {
          LoadingProgress().width(26).height(26).color(Color.White)
            .padding(8).backgroundColor('#70000000').borderRadius(22);
        }
      }
      if (this.mediaKind === 'video' && this.available()) {
        Stack() {
          Circle({ width: 42, height: 42 }).fill('#98000000');
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([Color.White]);
        }
      }
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.lock_open_fill')).fontSize(11).fontColor([Color.White]);
        Text(this.countText()).fontSize(10.5).fontColor(Color.White);
      }
      .padding({ left: 7, right: 7, top: 4, bottom: 4 })
      .backgroundColor('#85000000').borderRadius(9)
      .position({ x: 8, y: 124 });
    }
    .width('100%').height(156)
    .borderRadius(12).clip(true);
  }

  build() {
    Column({ space: 9 }) {
      if (this.locked) {
        this.lockedArtwork();
      } else {
        this.unlockedArtwork();
      }
      Row() {
        Column({ space: 2 }) {
          Text(this.locked ? $r('app.string.paid_media') : $r('app.string.paid_media_unlocked'))
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          if (this.caption.trim() !== '') {
            Text(this.caption).fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          if (!this.locked && this.mediaCount > 1) {
            Text($r('app.string.paid_viewer_note'))
              .fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(2);
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      }.width('100%');
      Row({ space: 6 }) {
        if (this.pending) {
          LoadingProgress().width(16).height(16).color(Color.White);
          Text($r('app.string.paid_checking')).fontSize(12.5).fontColor(Color.White);
        } else {
          Text(this.actionText())
            .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
      }
      .width('100%').height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.available() ? COLOR_PRIMARY : '#A7AFB8')
      .borderRadius(10)
      .stateStyles({
        normal: this.normalStyle,
        pressed: this.pressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .onClick((): void => { this.trigger(); });
      Row().height(9).width('100%');
    }
    .width(Math.max(224, Math.min(280, this.maxWidth)))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.countText()}，${this.actionText()}`);
  }
}
