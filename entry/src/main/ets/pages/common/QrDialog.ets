import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { logE } from '../../util/log';

// Shared QR dialog: renders a t.me link as a scannable code (ScanKit).
@CustomDialog
export struct QrDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  controller?: CustomDialogController;
  link: string = '';
  title: string = '';
  @State pix: image.PixelMap | null = null;
  @State failed: boolean = false;

  aboutToAppear(): void {
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      height: 400,
      width: 400
    };
    generateBarcode.createBarcode(this.link, options).then((p: image.PixelMap) => {
      this.pix = p;
    }).catch((e: Object) => {
      logE(`QrDialog.createBarcode failed: ${JSON.stringify(e)}`);
      this.failed = true;
    });
  }

  build() {
    Column({ space: 14 }) {
      Text(this.title)
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 240 });
      // White backing keeps the code scannable in dark mode.
      Column() {
        if (this.pix !== null) {
          Image(this.pix).draggable(false).width(220).height(220);
        } else if (this.failed) {
          Text($r('app.string.qr_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .width(220).height(220).textAlign(TextAlign.Center);
        } else {
          Column() {
            LoadingProgress().width(32).height(32).color(COLOR_ICON_SECONDARY);
          }.width(220).height(220).justifyContent(FlexAlign.Center);
        }
      }
      .backgroundColor(Color.White).padding(10).borderRadius(10);
      Text(this.link).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .copyOption(CopyOptions.LocalDevice)
        .textAlign(TextAlign.Center);
    }
    .padding(24)
    // 不走玻璃/材质，用实底。理由同 DeleteMessagesDialog：设备自报支持沉浸材质
    // 时 overlayGlassFill 给的是 material_tint，那只是叠在**真的渲染出来的**材质
    // 之上的一层淡色；而这台机器实测挂了材质却不渲染（见 overlayMaterial 里
    // 08-29 那段），淡色就成了唯一背板，弹窗压在内容上直接读不清。
    // 弹窗要的是可读，不是通透。
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center);
  }
}
