import { FileMessagePreview } from './FileMessagePreview';
import { FilePreviewSource, filePreviewKind, fileHasPreview } from '../../util/filePreview';
import { DrawnFileCardLayout, fileCardTileSize, fileCardTextWidth, FILE_CARD_TOP, FILE_CARD_BOTTOM } from './DrawnFileCardLayout';
import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { DrawnMediaTextPlan, DrawnMediaTexts, DrawnMediaTextPainter } from './DrawnMediaText';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  displayFileName, fileStatusText, fileTypeVisual, FileTypeVisual, isAudioFileName
} from '../../util/fileMessage';
import { str } from '../../util/strings';

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct FileBubble {
  private actionPainter: DrawnMediaControl = new DrawnMediaControl();
  private labelLayouts: DrawnMediaTexts = new DrawnMediaTexts();
  private labelPainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private previewPainter: DrawnMediaControl = new DrawnMediaControl();
  private controlPainter: DrawnMediaControl = new DrawnMediaControl();
  private paintEnv = chatEnv;
  @Computed private get paintEnvironment(): string {
    return `${this.paintEnv.appearanceEpoch}:${this.paintEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Param thumbnailId: number = 0;
  @Param thumbnailPath: string = '';
  @Param mini: string = '';
  @Param preparedCard: DrawnFileCardLayout | undefined = undefined;
  @Param fileId: number = 0;
  @Param fileName: string = '';
  @Param mimeType: string = '';
  @Param fileSize: number = 0;
  @Param filePath: string = '';
  @Param downloadProgress: number = 0;
  @Param downloadFailed: boolean = false;
  @Param downloadActive: boolean = false;
  // 出站发送中：图块画上传环，点击不打开也不暂停，右侧箭头朝上。
  @Param uploading: boolean = false;
  @Param maxWidth: number = 250;
  @Param fitAvailableWidth: boolean = false;
  @Param onOpen: () => void = (): void => {};
  @Param onSave: () => void = (): void => {};
  // 下载中点一下 = 暂停（issue #93）。已下的那部分留着，再点继续断点续传。
  @Param onPause: () => void = (): void => {};

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

  @Computed private get displayName(): string { return displayFileName(this.fileName); }
  @Computed private get typeVisual(): FileTypeVisual { return fileTypeVisual(this.fileName, this.mimeType); }
  private visual(): FileTypeVisual { return this.typeVisual; }

  @Computed private get tileSize(): number {
    return this.preparedCard?.tileSize ?? fileCardTileSize(this.fileName, this.mimeType, this.thumbnailId, this.mini);
  }
  @Computed private get previewSource(): FilePreviewSource {
    return { fileId: this.fileId, filePath: this.filePath, fileSize: this.fileSize,
      thumbnailId: this.thumbnailId, thumbnailPath: this.thumbnailPath, mini: this.mini,
      kind: filePreviewKind(this.fileName, this.mimeType) };
  }

  @Builder private previewTile(): void {
    Stack() {
      // BuilderParam otherwise rebinds this to FileMessagePreview, which owns no controlPainter.
      FileMessagePreview({ source: this.previewSource, boxSize: this.tileSize,
        placeholder: (): void => { this.typeTile(); } });
      if (this.uploading || this.downloadActive || this.filePath === '' || this.previewSource.kind === 'video') {
        Stack() {
          if ((this.uploading || this.downloadActive) && this.downloadProgress <= 0) {
            DrawnLoadingSpinner({ ringSize: 21, ringColor: Color.White });
          }
        }.width(28).height(28)
          .drawModifier(this.previewPainter.bind(this.getUIContext(), this.paintEnvironment, 28,
            '#66000000', '#FFFFFF', this.uploading || this.downloadActive ? 'percent' :
              this.downloadFailed ? 'retry' : this.filePath !== '' ? 'play' : 'download',
            this.tileProgress(), false));
      }
    }.width(this.tileSize).height(this.tileSize);
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
      this.downloadFailed,
      this.uploading
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
      if ((this.uploading || this.downloadActive) && this.downloadProgress <= 0) {
        DrawnLoadingSpinner({ ringSize: 21, ringColor: Color.White });
      }
    }
    .width(this.tileSize).height(this.tileSize)
    .drawModifier(this.controlPainter.bind(this.getUIContext(), this.paintEnvironment, this.tileSize,
      this.sourceUnavailable() ? '#AEB6BF' : this.visual().color, '#FFFFFF', this.tileGlyph(),
      this.tileProgress(), true, this.tileLabel()));
  }

  private tileProgress(): number {
    return this.uploading || this.downloadActive || (!this.downloadFailed && this.filePath === '')
      ? this.downloadProgress : 0;
  }

  private tileGlyph(): string {
    if (this.uploading || this.downloadActive) { return 'percent'; }
    if (!this.downloadFailed && this.filePath === '' && this.downloadProgress > 0) {
      return isAudioFileName(this.fileName, this.mimeType) ? 'play' : 'download';
    }
    if (this.downloadFailed) { return 'error'; }
    return this.filePath !== '' ? 'label-check' : 'label';
  }

  private tileLabel(): string {
    if (this.uploading || this.downloadActive) { return this.downloadProgress > 0 ? `${this.downloadProgress}` : ''; }
    if (!this.downloadFailed && this.filePath === '' && this.downloadProgress > 0) { return ''; }
    return this.downloadFailed ? '!' : this.visual().label;
  }

  @Computed private get labelPlan(): DrawnMediaTextPlan {
    const width = this.fitAvailableWidth ? Math.max(0, this.maxWidth) : Math.max(190, Math.min(262, this.maxWidth));
    const textWidth = fileCardTextWidth(width, this.tileSize);
    const labels = this.preparedCard?.labels ?? this.labelLayouts;
    return labels.prepare(this.getUIContext(), this.preparedCard?.environment ?? this.paintEnvironment, textWidth,
      this.displayName, 14.5, COLOR_TEXT_PRIMARY, this.status(), 11,
      this.downloadFailed ? '#D95B57' : COLOR_TEXT_SECONDARY, 2, true, 4, this.tileSize);
  }

  build() {
    Row({ space: 10 }) {
      Row({ space: 10 }) {
        if (fileHasPreview(this.previewSource)) { this.previewTile(); } else { this.typeTile(); }
        Row()
          .width(this.labelPlan.width).height(this.labelPlan.height)
          .drawModifier(this.labelPainter.bind(this.labelPlan))
          .accessibilityText(`${this.displayName}. ${this.status()}`);

      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.cardNormalStyle,
        pressed: this.cardPressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .onClick((): void => {
        if (this.sourceUnavailable() || this.uploading) {
          return;
        }
        if (this.downloadActive) {
          this.onPause();
          return;
        }
        this.onOpen();
      });
    // 右侧动作按钮：**没下载 = 下载图标，下载完 = 保存图标**，两者都是图标
    // （用户 2026-11-05）。下载中/上传中不显示，让左侧的进度环独占表达状态。
    if (!this.uploading && !this.downloadActive && !this.sourceUnavailable()) {
      Row()
      .width(28).height(28).borderRadius(14)
      .drawModifier(this.actionPainter.bind(this.getUIContext(), this.paintEnvironment, 28,
        '#00000000', COLOR_ICON_SECONDARY, this.filePath === '' ? 'download' : 'save'))
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.actionNormalStyle,
        pressed: this.actionPressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .accessibilityText(this.actionAccessibilityText())
      .onClick((): void => {
        if (this.filePath === '') {
          this.onOpen();
        } else {
          this.onSave();
        }
      });
    }
  }
  .width(this.fitAvailableWidth ? Math.max(0, this.maxWidth) : Math.max(190, Math.min(262, this.maxWidth)))
  .alignItems(VerticalAlign.Center)
  // 右侧给动作按钮留位（28vp + 间距），其余交给时间浮层。
  .padding({ top: FILE_CARD_TOP, bottom: FILE_CARD_BOTTOM, right: 4 });
}
}
