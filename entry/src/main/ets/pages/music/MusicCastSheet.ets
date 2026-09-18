import { AVCastPicker } from '@kit.AVSessionKit';
import { MusicCastRow } from '../../util/musicCastDevices';
import { musicGlassBlur, musicGlassFill } from '../../util/musicCenterStyle';
import { MusicSheetShell } from './MusicSheetShell';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 音频流转（设计稿 showCast）。
//
// 【设备是真的，切换交给系统】列表来自 services/AudioOutputDevices（可用的媒体输出
// 设备 + 当前正在用的那一个），所以「已连接的耳机」「客厅的音箱」显示的是实况。
// 但公共接口里**没有**「把本应用的音频改到某台设备上」这一条：能真正投出去的只有
// 系统的流转选择器。所以设备行是状态、不可点，最后一行是 AVCastPicker——它的外观
// 用 customPicker 按设计稿画成同样的一行，点下去弹的是系统的超级终端。

const LIST_MAX_HEIGHT: number = 360;

@Component
export struct MusicCastSheet {
  @Prop rows: MusicCastRow[];
  @Prop bottomInset: number;

  @Builder
  deviceRow(row: MusicCastRow) {
    Row({ space: 12 }) {
      Text(str(row.tagKey))
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
        .width(38).height(38).borderRadius(10)
        .backgroundColor(musicGlassFill());
      Column({ space: 2 }) {
        Text(row.name !== '' ? row.name : str(row.tagKey))
          .fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(str(row.descKey))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      // 圆点用 Column + borderRadius 画：Shape 的 fill() 接非常量实参时编译器按
      // API 26 的新重载算，而本应用底线是 API 20。
      Column()
        .width(10).height(10).borderRadius(5)
        .backgroundColor(row.active ? COLOR_PRIMARY : $r('app.color.divider'));
    }
    .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(16)
    .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: row.active ? COLOR_PRIMARY : $r('app.color.divider') });
  }

  // 系统流转选择器的外观。AVCastPicker 只借它的点击与弹窗，长相完全由这里定。
  @Builder
  pickerRow() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.superdevice')).fontSize(18).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(38).height(38).borderRadius(10)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(musicGlassFill());
      Column({ space: 2 }) {
        Text($r('app.string.mc_cast_more'))
          .fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .width('100%');
        Text($r('app.string.mc_cast_more_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider'), style: BorderStyle.Dashed });
  }

  build() {
    MusicSheetShell({
      title: $r('app.string.mc_cast_title'),
      subTitle: str('mc_cast_subtitle'),
      bottomInset: this.bottomInset
    }) {
      Scroll() {
        Column({ space: 8 }) {
          if (this.rows.length === 0) {
            Text($r('app.string.mc_cast_empty'))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
              .width('100%').padding(24);
          }
          ForEach(this.rows, (row: MusicCastRow): void => {
            this.deviceRow(row);
          }, (row: MusicCastRow): string => `${row.id}`);
          AVCastPicker({ customPicker: (): void => { this.pickerRow(); } })
            .width('100%').height(60);
        }
        .width('100%').padding({ left: 20, right: 20 });
      }
      .width('100%').constraintSize({ maxHeight: LIST_MAX_HEIGHT })
      .scrollBar(BarState.Off)
      .align(Alignment.Top);
    }
  }
}
