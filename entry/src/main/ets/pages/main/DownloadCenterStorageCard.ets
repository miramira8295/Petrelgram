import { formatBytes } from '../../store/StorageApi';
import { storageBarWidths } from '../../util/downloadCenterModel';
import { str } from '../../util/strings';
import { accentSoft, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 下载中心顶部的「存储占用」卡片（2026-09-15，照 Claude Design 稿）：左侧环形图 + 右侧 2+1 仪表盘小色块，
// 右上角「清理缓存」；底下是「仅在 Wi‑Fi 下后台缓存」开关。只负责画，清理的确认和执行、开关的落盘在页面里。
@Component
export struct DownloadCenterStorageCard {
  @Prop cacheBytes: number = 0;
  @Prop localBytes: number = 0;
  @Prop freeBytes: number = -1;
  @Prop clearing: boolean = false;
  @Prop wifiOnly: boolean = true;
  onClear: () => void = (): void => {};
  onWifiOnlyChange: (on: boolean) => void = (_on: boolean): void => {};

  private cacheRingPercent(): number {
    if (this.cacheBytes <= 0) {
      return 0;
    }
    if (this.localBytes <= 0) {
      return 100;
    }
    const w = storageBarWidths(this.cacheBytes, this.localBytes);
    return Math.min(94, Math.max(6, Math.round(w.cache)));
  }

  private totalUsedText(): string {
    return formatBytes(Math.max(0, this.cacheBytes) + Math.max(0, this.localBytes));
  }

  // 缓存总占用要等 getStorageStatistics 回来（可能几秒），没回来之前显示占位。
  private cacheText(): string {
    return this.cacheBytes > 0 ? formatBytes(this.cacheBytes) : '--';
  }

  private cacheLabel(): string {
    return str('dc_legend_cache', '').trim();
  }

  private freeLabel(): string {
    return str('dc_device_free', '').trim();
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.dc_storage_title'))
          .fontSize(13.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
        if (this.clearing) {
          LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        } else {
          Text($r('app.string.dc_clear_cache'))
            .fontSize(13).fontWeight(600).fontColor(COLOR_PRIMARY)
            .onClick((): void => { this.onClear(); });
        }
      }
      .width('100%');
      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.Center }) {
          Progress({ value: this.cacheRingPercent(), total: 100, type: ProgressType.Ring })
            .width(74)
            .height(74)
            .color(COLOR_PRIMARY)
            .backgroundColor(this.localBytes > 0 ? $r('app.color.dc_ok') : $r('app.color.dc_chip'))
            .style({ strokeWidth: 7.5 });
          Text(this.totalUsedText())
            .fontSize(11)
            .fontWeight(600)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .constraintSize({ maxWidth: 54 })
            .textAlign(TextAlign.Center);
        }
        .width(74)
        .height(74);
        Column({ space: 7 }) {
          Row({ space: 7 }) {
            Column({ space: 3 }) {
              Row({ space: 5 }) {
                Row().width(7).height(7).borderRadius(3.5).backgroundColor(COLOR_PRIMARY);
                Text(this.cacheLabel())
                  .fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              Text(this.cacheText())
                .fontSize(13.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor(accentSoft())
            .borderRadius(10);

            Column({ space: 3 }) {
              Row({ space: 5 }) {
                Row().width(7).height(7).borderRadius(3.5).backgroundColor($r('app.color.dc_ok'));
                Text($r('app.string.dc_badge_saved_local'))
                  .fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              Text(formatBytes(this.localBytes))
                .fontSize(13.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.dc_ok_soft'))
            .borderRadius(10);
          }
          .width('100%');

          if (this.freeBytes >= 0) {
            Row({ space: 6 }) {
              Row().width(7).height(7).borderRadius(3.5).backgroundColor($r('app.color.dc_chip'));
              Text(this.freeLabel())
                .fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                .layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
              Text(formatBytes(this.freeBytes))
                .fontSize(12.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY).maxLines(1);
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(9);
          }
        }
        .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 10, bottom: 2 });
      Divider().strokeWidth('1px').color($r('app.color.dc_line')).margin({ top: 12, bottom: 10 });
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text($r('app.string.dc_wifi_only_title')).fontSize(13.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.dc_wifi_only_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        Toggle({ type: ToggleType.Switch, isOn: this.wifiOnly })
          .selectedColor(COLOR_PRIMARY)
          .onChange((on: boolean): void => { this.onWifiOnlyChange(on); });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(14)
    .clip(true)
    .borderWidth('1px')
    .borderColor($r('app.color.dc_line'));
  }
}
