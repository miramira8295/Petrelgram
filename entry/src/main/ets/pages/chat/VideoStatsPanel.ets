import { str } from '../../util/strings';
import { StatsRow, VideoStatsSnapshot, videoStatsRows } from '../../util/videoStats';

const REFRESH_MS: number = 1000;
const PANEL_BG: string = '#B3000000';
const LABEL_COLOR: string = '#B3FFFFFF';
const VALUE_COLOR: string = '#FFFFFF';
const LABEL_WIDTH: number = 92;

// 「详细统计信息」面板（2026-10-10，仿 YouTube 的 Stats for nerds）：半透明深色底、等宽小字、
// 每秒刷新一次。数据从播放器交出来的 source 函数现取（见 StreamingVideoPlayer.collectStats），
// 格式化在 util/videoStats。source 为 null（播放器已释放）时停在最后一次的读数上。
@ComponentV2
export struct VideoStatsPanel {
  @Param source: (() => VideoStatsSnapshot) | null = null;
  // 档位说明（查看器才知道），拼进 Quality 那一行。
  @Param quality: string = '';
  @Event onClose: () => void = (): void => {};
  @Local private rows: StatsRow[] = [];
  private timer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timer = setInterval((): void => {
      this.refresh();
    }, REFRESH_MS);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private refresh(): void {
    const source: (() => VideoStatsSnapshot) | null = this.source;
    if (source === null) {
      return;
    }
    const snapshot: VideoStatsSnapshot = source();
    snapshot.quality = this.quality;
    this.rows = videoStatsRows(snapshot);
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(str('mv_stats_title')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(VALUE_COLOR)
          .layoutWeight(1);
        Stack() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([VALUE_COLOR]);
        }
        .width(28).height(28)
        .onClick((): void => { this.onClose(); });
      }
      .width('100%');
      ForEach(this.rows, (r: StatsRow) => {
        Row() {
          Text(r.label).fontSize(11).fontColor(LABEL_COLOR).fontFamily('monospace')
            .width(LABEL_WIDTH);
          Text(r.value).fontSize(11).fontColor(VALUE_COLOR).fontFamily('monospace')
            .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%').alignItems(VerticalAlign.Top);
      }, (r: StatsRow): string => `${r.label}|${r.value}`);
    }
    .width('92%').constraintSize({ maxWidth: 460 })
    .padding({ left: 12, right: 6, top: 6, bottom: 10 })
    .backgroundColor(PANEL_BG).borderRadius(12)
    // 面板本身吃掉点击：别透下去触发播放器的「点一下显隐控制条」。
    .onClick((): void => {});
  }
}
