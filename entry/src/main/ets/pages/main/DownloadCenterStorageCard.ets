import { formatBytes } from '../../store/StorageApi';
import { storageBarWidths } from '../../util/downloadCenterModel';
import { str } from '../../util/strings';
import { COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 下载中心顶部的「存储占用」卡片（2026-09-15，照 Claude Design 稿）：两段占用条（缓存 / 已存本地）+ 图例 + 设备可用，
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

  private cacheWidth(): string {
    return `${storageBarWidths(this.cacheBytes, this.localBytes).cache}%`;
  }

  private localWidth(): string {
    return `${storageBarWidths(this.cacheBytes, this.localBytes).local}%`;
  }

  // 缓存总占用要等 getStorageStatistics 回来（可能几秒），没回来之前显示占位。
  private cacheText(): string {
    return this.cacheBytes > 0 ? formatBytes(this.cacheBytes) : '--';
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
      Row({ space: 2 }) {
        Row().width(this.cacheWidth()).height('100%').backgroundColor(COLOR_PRIMARY);
        Row().width(this.localWidth()).height('100%').backgroundColor($r('app.color.dc_ok'));
      }
      .width('100%').height(8).borderRadius(4).clip(true)
      .backgroundColor($r('app.color.dc_chip'))
      .margin({ top: 10, bottom: 9 });
      Row({ space: 14 }) {
        Row({ space: 5 }) {
          Row().width(8).height(8).borderRadius(4).backgroundColor(COLOR_PRIMARY);
          Text(str('dc_legend_cache', this.cacheText())).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        Row({ space: 5 }) {
          Row().width(8).height(8).borderRadius(4).backgroundColor($r('app.color.dc_ok'));
          Text(str('dc_legend_local', formatBytes(this.localBytes))).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        Blank();
        if (this.freeBytes >= 0) {
          Text(str('dc_device_free', formatBytes(this.freeBytes))).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
      .width('100%');
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
    .borderWidth('1px')
    .borderColor($r('app.color.dc_line'));
  }
}
