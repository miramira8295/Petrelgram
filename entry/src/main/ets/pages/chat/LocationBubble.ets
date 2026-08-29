import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';

@Component
export struct LocationBubble {
  @Prop latitude: number = 0;
  @Prop longitude: number = 0;
  @Prop accuracy: number = 0;
  @Prop valid: boolean = false;
  @Prop livePeriod: number = 0;
  @Prop expiresIn: number = 0;
  @Prop messageDate: number = 0;
  @Prop nowSec: number = 0;
  @Prop venueTitle: string = '';
  @Prop venueAddress: string = '';
  @Prop venueProvider: string = '';
  @Prop proximityRadius: number = 0;
  @Prop maxWidth: number = 250;
  // 本机正在共享的就是这一条。停止入口必须长在气泡上——之前只放在会话页顶部
  // 的「⋯」菜单里，用户盯着气泡根本找不到。
  @Prop sharing: boolean = false;
  onOpen: () => void = (): void => {};
  onStopLive: () => void = (): void => {};

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
      Column()
        .width('100%').height('100%')
        .backgroundColor(this.valid ? '#DCE9DF' : '#E4E7EA');
      if (this.valid) {
        Divider().width(290).strokeWidth(5).color('#C5D7C9')
          .rotate({ angle: 14 }).position({ x: -20, y: 25 });
        Divider().width(290).strokeWidth(2).color('#F8FAF7')
          .rotate({ angle: -18 }).position({ x: -18, y: 65 });
        Divider().width(210).strokeWidth(3).color('#CCDCCF')
          .rotate({ angle: 70 }).position({ x: 38, y: 44 });
        Divider().width(180).strokeWidth(1).color('#F7FAF6')
          .rotate({ angle: 42 }).position({ x: 50, y: 10 });
        Stack() {
          Circle({ width: 38, height: 38 }).fill('#203390EC');
          Circle({ width: 28, height: 28 }).fill(COLOR_PRIMARY)
            .shadow({ radius: 6, color: '#4A1F78B4', offsetX: 0, offsetY: 2 });
          SymbolGlyph($r('sys.symbol.mappin_and_rectangle'))
            .fontSize(15).fontColor([Color.White]);
        }.width(42).height(42);
      } else {
        Column({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.map')).fontSize(24).fontColor(['#8E969F']);
          Text($r('app.string.loc_coords_missing')).fontSize(11).fontColor('#737B84');
        }.justifyContent(FlexAlign.Center);
      }
      if (this.livePeriod > 0) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.liveActive() ? '#32B66A' : '#929AA3');
          Text(this.liveActive() ? $r('app.string.loc_live_short') : $r('app.string.ended'))
            .fontSize(10.5).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#EFFFFFFF').borderRadius(12)
        .position({ x: 8, y: 8 });
      }
    }
    .width('100%').height(104)
    .borderRadius(10)
    .clip(true);
  }

  build() {
    Column({ space: 9 }) {
      this.mapPreview();
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.title())
            .fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(this.detail())
            .fontSize(11.5)
            .fontColor(this.available() ? COLOR_TEXT_SECONDARY : '#D95B57')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        if (this.available()) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13).fontColor([COLOR_ICON_SECONDARY]);
        }
      }
      .padding({ left: 2, right: 30, bottom: this.sharing ? 4 : 10 });
      if (this.sharing) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.stop_circle')).fontSize(16).fontColor(['#D95B57']);
          Text($r('app.string.loc_stop_sharing'))
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#D95B57');
        }
        .justifyContent(FlexAlign.Center)
        .width('100%').height(34)
        .backgroundColor('#14D95B57')
        .borderRadius(8)
        // 气泡右下角浮着时间和已读对号（详情行靠 right:30 给它让位）。这一条
        // 是整宽的，只能靠下方留一条空带让浮层落在它外面。
        .margin({ bottom: 22 })
        .onClick((): void => { this.onStopLive(); });
      }
    }
    .width(Math.max(210, Math.min(270, this.maxWidth)))
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
