import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct GiftBubble {
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
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 140,
          colors: [[`${this.accent()}22`, 0], ['#F7F9FC', 1]]
        });
      if (this.photoPath !== '') {
        Image(this.photoPath.startsWith('/') ? `file://${this.photoPath}` : this.photoPath).draggable(false)
          .width(112).height(112).objectFit(ImageFit.Contain)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
            .animation({ duration: 220, curve: Curve.EaseOut }));
      } else {
        Text(this.fallbackEmoji()).fontSize(54)
          .opacity(this.refunded ? 0.5 : 1);
      }
      if (this.photoPath === '' && this.photoFileId !== 0) {
        if (this.photoFailed) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
            Text($r('app.string.gift_retry_image')).fontSize(10).fontColor(Color.White);
          }
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor('#78000000').borderRadius(10)
          .position({ x: 8, y: 92 })
          .onClick((): void => { this.onRetryPhoto(this.messageId); });
        } else {
          Stack() {
            if (this.photoProgress > 0) {
              Progress({ value: this.photoProgress, total: 100, type: ProgressType.Ring })
                .width(26).height(26).color(this.accent());
            } else {
              LoadingProgress().width(23).height(23).color(this.accent());
            }
          }.position({ x: 10, y: 91 });
        }
      }
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.gift')).fontSize(11).fontColor([this.accent()]);
        Text('TELEGRAM GIFT').fontSize(9.5).fontWeight(FontWeight.Medium)
          .fontColor(this.accent());
      }
      .position({ x: 10, y: 9 });
    }
    .width('100%').height(124)
    .borderRadius(12).clip(true);
  }

  build() {
    Column({ space: 8 }) {
      this.artwork();
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
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 }).fill(this.refunded ? '#8C96A1' : '#39A96B');
        Text(this.status.trim() !== '' ? this.status : $r('app.string.gift_status_unknown'))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        Blank();
        if (this.code !== '') {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_text')).fontSize(12).fontColor([COLOR_PRIMARY]);
            Text($r('app.string.gift_copy_code')).fontSize(11).fontColor(COLOR_PRIMARY);
          }
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .backgroundColor('#123390EC').borderRadius(9)
          .stateStyles({
            normal: this.normalStyle,
            pressed: this.pressedStyle
          })
          .animation({ duration: 110, curve: Curve.EaseOut })
          .onClick((): void => { this.onCopyCode(this.code); });
        }
      }.width('100%').padding({ bottom: 9 });
    }
    .width(Math.max(220, Math.min(278, this.maxWidth)))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.title}，${this.value}，${this.status}`);
  }
}
