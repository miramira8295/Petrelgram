import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  displayFileName, fileStatusText, fileTypeVisual, FileTypeVisual
} from '../../util/fileMessage';
import { str } from '../../util/strings';

@Component
export struct FileBubble {
  @Prop fileId: number = 0;
  @Prop fileName: string = '';
  @Prop mimeType: string = '';
  @Prop fileSize: number = 0;
  @Prop filePath: string = '';
  @Prop downloadProgress: number = 0;
  @Prop downloadFailed: boolean = false;
  @Prop downloadActive: boolean = false;
  @Prop maxWidth: number = 250;
  onOpen: () => void = (): void => {};
  onSave: () => void = (): void => {};
  // 下载中点一下 = 暂停（issue #93）。已下的那部分留着，再点继续断点续传。
  onPause: () => void = (): void => {};

  @Styles
  private cardNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private cardPressedStyle(): void {
    .scale({ x: 0.988, y: 0.988 })
    .opacity(0.84)
  }

  @Styles
  private actionNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private actionPressedStyle(): void {
    .scale({ x: 0.88, y: 0.88 })
    .opacity(0.65)
  }

  private visual(): FileTypeVisual {
    return fileTypeVisual(this.fileName, this.mimeType);
  }

  private sourceUnavailable(): boolean {
    return this.fileId === 0 && this.filePath === '';
  }

  private status(): string {
    return fileStatusText(
      this.fileId,
      this.filePath,
      this.fileSize,
      this.downloadActive,
      this.downloadProgress,
      this.downloadFailed
    );
  }

  private actionAccessibilityText(): string {
    if (this.sourceUnavailable()) {
      return str('file_unavailable');
    }
    if (this.filePath === '') {
      return this.downloadFailed ? str('file_redownload_to_save') : str('file_download_to_save');
    }
    return str('file_save_as');
  }

  @Builder
  private typeTile(): void {
    Stack() {
      Column()
        .width(48).height(48)
        .borderRadius(13)
        .backgroundColor(this.sourceUnavailable() ? '#AEB6BF' : this.visual().color);
      if (this.downloadActive) {
        if (this.downloadProgress > 0) {
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
            .width(40).height(40)
            .color(Color.White)
            .style({ strokeWidth: 2 });
          Text(`${this.downloadProgress}`)
            .fontSize(9)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White);
        } else {
          LoadingProgress().width(21).height(21).color(Color.White);
        }
      } else if (!this.downloadFailed && this.filePath === '' && this.downloadProgress > 0) {
        // 暂停态：停在百分比上的静止环 + ▶，一眼看出"点一下会继续"。
        Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
          .width(40).height(40)
          .color(Color.White)
          .style({ strokeWidth: 2 });
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([Color.White]);
      } else if (this.downloadFailed) {
        Text('!')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White);
      } else {
        Text(this.visual().label)
          .fontSize(this.visual().label.length > 4 ? 8.5 : 10.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1);
        if (this.filePath !== '') {
          Stack() {
            Circle({ width: 16, height: 16 }).fill('#F7FFFFFF');
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(10)
              .fontColor([this.visual().color]);
          }
          .width(16).height(16)
          .position({ x: 33, y: 33 });
        }
      }
    }
    .width(48).height(48);
  }

  build() {
    Row({ space: 10 }) {
      Row({ space: 10 }) {
        this.typeTile();
        Column({ space: 4 }) {
          Text(displayFileName(this.fileName))
            .fontSize(14.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
          Text(this.status())
            .fontSize(11)
            .fontColor(this.downloadFailed ? '#D95B57' : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.cardNormalStyle,
        pressed: this.cardPressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .onClick((): void => {
        if (this.sourceUnavailable()) {
          return;
        }
        if (this.downloadActive) {
          this.onPause();
          return;
        }
        this.onOpen();
      });
      Stack() {
        Circle({ width: 30, height: 30 })
          .fill(this.filePath !== '' ? '#143390EC' : '#0D000000');
        SymbolGlyph($r(this.filePath !== ''
          ? 'sys.symbol.arrow_down_circle' : 'sys.symbol.arrow_down'))
          .fontSize(this.filePath !== '' ? 20 : 16)
          .fontColor([this.sourceUnavailable() ? '#9EA6AF' : COLOR_TEXT_SECONDARY]);
      }
      .width(30).height(30)
      .opacity(this.sourceUnavailable() ? 0.45 : 1)
      .stateStyles({
        normal: this.actionNormalStyle,
        pressed: this.actionPressedStyle
      })
      .animation({ duration: 100, curve: Curve.EaseOut })
      .accessibilityText(this.actionAccessibilityText())
      .onClick((): void => {
        if (!this.sourceUnavailable()) {
          this.onSave();
        }
      });
    }
    .width(Math.max(190, Math.min(262, this.maxWidth)))
    .alignItems(VerticalAlign.Center)
    .padding({ top: 1, bottom: 10, right: 31 });
  }
}
