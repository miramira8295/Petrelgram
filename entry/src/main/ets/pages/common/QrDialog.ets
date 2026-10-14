import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { getTdClient } from '../../tdkit/Globals';
import { QrLink, QrSession, QrSnapshot } from '../../util/qrSession';
import { fetchMyUserLink } from '../../util/userLink';
import { TAB_PROFILE } from '../../util/mainTabIndex';

// Shared QR dialog: renders a t.me link as a scannable code (ScanKit).
@CustomDialog
export struct QrDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  controller?: CustomDialogController;
  link: string = '';
  title: string = '';
  ownUser: boolean = false;
  onClosed: () => void = (): void => {};
  @StorageProp('mainTabIndex') @Watch('onMainTabChanged') mainTab: number = TAB_PROFILE;
  @StorageProp('appIsForeground') @Watch('onForegroundChanged') foreground: boolean = true;
  @State pix: image.PixelMap | null = null;
  @State displayedLink: string = '';
  @State failed: boolean = false;
  @State temporary: boolean = false;
  private session: QrSession<image.PixelMap> | null = null;

  aboutToAppear(): void {
    this.session = new QrSession<image.PixelMap>(
      (): Promise<QrLink> => this.ownUser ? fetchMyUserLink(getTdClient()) :
        Promise.resolve({ url: this.link, expiresIn: 0 } as QrLink),
      (url: string): Promise<image.PixelMap> => {
        const options: generateBarcode.CreateOptions = {
          scanType: scanCore.ScanType.QR_CODE, height: 400, width: 400
        };
        return generateBarcode.createBarcode(url, options);
      },
      (value: image.PixelMap): void => { value.release().catch((): void => {}); },
      (state: QrSnapshot<image.PixelMap>): void => {
        this.pix = state.image;
        this.displayedLink = state.link;
        this.failed = state.failed;
        this.temporary = state.temporary;
      });
    this.session.start();
  }

  aboutToDisappear(): void {
    this.session?.close();
    this.session = null;
    this.onClosed();
  }

  private onMainTabChanged(): void {
    if (this.ownUser && this.mainTab !== TAB_PROFILE) {
      this.session?.close();
      this.controller?.close();
    }
  }

  private onForegroundChanged(): void {
    // Dismiss before suspension: an expired bitmap must not flash on resume.
    if (!this.foreground) {
      this.session?.close();
      this.controller?.close();
    }
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
          Column({ space: 12 }) {
            Text($r('app.string.qr_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            Button($r('app.string.settings_retry')).onClick((): void => { this.session?.retry(); });
          }.width(220).height(220).justifyContent(FlexAlign.Center);
        } else {
          Column() {
            LoadingProgress().width(32).height(32).color(COLOR_ICON_SECONDARY);
          }.width(220).height(220).justifyContent(FlexAlign.Center);
        }
      }
      .backgroundColor(Color.White).padding(10).borderRadius(10);
      if (this.displayedLink !== '') {
        Text(this.displayedLink).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .copyOption(CopyOptions.LocalDevice)
          .textAlign(TextAlign.Center);
      }
      if (this.temporary) {
        Text($r('app.string.qr_temporary')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center);
      }
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
