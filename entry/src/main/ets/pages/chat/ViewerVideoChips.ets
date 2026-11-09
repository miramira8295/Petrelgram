import { str } from '../../util/strings';
import {
  QUALITY_AUTO, VideoVariant, variantLabel, variantLabelHeight
} from '../../util/videoVariants';

const CHIP_HEIGHT: number = 24;
const CHIP_TEXT: string = '#E6FFFFFF';
const CHIP_BG: string = '#33FFFFFF';

// 查看器顶栏里视频专属的两枚小标签（2026-10-10）：
//   「硬解 / 软解」——这一次播放实际用的解码器（播放器起播后才知道，之前不显示）；
//   「720p ▾」——清晰度，点开选档（只有不止一档时才显示）。
// 逻辑都在 util/videoVariants，这里只画、只发事件。
@ComponentV2
export struct ViewerVideoChips {
  // 'hw' | 'sw' | ''（还不知道）
  @Param decoder: string = '';
  // 可选的档（第一项是原片）；不到两项不显示清晰度标签。
  @Param variants: VideoVariant[] = [];
  @Param quality: number = QUALITY_AUTO;
  // 这次实际在播的那一档（自动档时用来显示「自动（720p）」）。
  @Param playing: VideoVariant | null = null;
  @Event onPickQuality: (quality: number) => void = (_q: number): void => {};
  // 点「ⓘ 硬解」打开详细统计信息面板（VideoStatsPanel）。
  @Event onMinimize: () => void = (): void => {};
  @Event onShowStats: () => void = (): void => {};

  private qualityText(): string {
    const label: string = this.playing !== null ? variantLabel(this.playing) : '';
    if (this.quality === QUALITY_AUTO) {
      return label !== '' ? str('mv_quality_auto_with', label) : str('mv_quality_auto');
    }
    return label;
  }

  private optionText(v: VideoVariant, index: number): string {
    const label: string = variantLabel(v);
    return index === 0 ? str('mv_quality_original', label) : label;
  }

  @Builder
  qualityMenu() {
    Menu() {
      MenuItem({ content: str('mv_quality_auto') })
        .selected(this.quality === QUALITY_AUTO)
        .selectIcon(true)
        .onChange((selected: boolean): void => {
          if (selected) {
            this.onPickQuality(QUALITY_AUTO);
          }
        });
      ForEach(this.variants, (v: VideoVariant, index: number) => {
        MenuItem({ content: this.optionText(v, index) })
          .selected(this.quality !== QUALITY_AUTO && this.quality === variantLabelHeight(v))
          .selectIcon(true)
          .onChange((selected: boolean): void => {
            if (selected) {
              this.onPickQuality(variantLabelHeight(v));
            }
          });
      }, (v: VideoVariant): string => `${v.fileId}`);
    }
  }

  build() {
    Row({ space: 6 }) {
      Text(str('vf_minimize')).fontSize(11).fontColor(CHIP_TEXT)
        .height(CHIP_HEIGHT).padding({ left: 8, right: 8 }).borderRadius(CHIP_HEIGHT / 2)
        .backgroundColor(CHIP_BG).onClick((): void => { this.onMinimize(); });
      if (this.decoder !== '') {
        Row({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(12).fontColor([CHIP_TEXT]);
          Text(this.decoder === 'hw' ? str('mv_decoder_hw') : str('mv_decoder_sw'))
            .fontSize(11).fontColor(CHIP_TEXT);
        }
        .height(CHIP_HEIGHT).padding({ left: 6, right: 8 })
        .borderRadius(CHIP_HEIGHT / 2).backgroundColor(CHIP_BG)
        .onClick((): void => { this.onShowStats(); });
      }
      if (this.variants.length > 1) {
        Row({ space: 2 }) {
          Text(this.qualityText()).fontSize(11).fontColor(CHIP_TEXT).maxLines(1);
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([CHIP_TEXT]);
        }
        .height(CHIP_HEIGHT).padding({ left: 8, right: 6 })
        .borderRadius(CHIP_HEIGHT / 2).backgroundColor(CHIP_BG)
        .bindMenu(this.qualityMenu());
      }
    }
    .alignItems(VerticalAlign.Center);
  }
}
