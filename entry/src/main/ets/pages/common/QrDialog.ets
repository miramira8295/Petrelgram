import { showToast } from '../../util/toast';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { fetchChatQrLink } from '../../util/chatQrLink';
import { exportQrImage } from '../../services/QrImageExport';
import { str } from '../../util/strings';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
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
  chatId: number = 0;
  onScan: () => void = (): void => {};
  @State exporting: boolean = false;
  @State failureText: string = '';
  private alive: boolean = false;
  private revision: number = 0;
  onClosed: () => void = (): void => {};
  @StorageProp('mainTabIndex') @Watch('onMainTabChanged') mainTab: number = TAB_PROFILE;
  @StorageProp('appIsForeground') @Watch('onForegroundChanged') foreground: boolean = true;
  @State pix: image.PixelMap | null = null;
  @State displayedLink: string = '';
  @State failed: boolean = false;
  @State temporary: boolean = false;
  private session: QrSession<image.PixelMap> | null = null;

  aboutToAppear(): void {
    this.alive = true;
    const client = getTdClient();
    this.session = new QrSession<image.PixelMap>(
      (): Promise<QrLink> => {
        this.failureText = '';
        const request: Promise<QrLink> = this.ownUser ? fetchMyUserLink(client) :
          (this.chatId !== 0 ? fetchChatQrLink({ send: (request: TdRequest, timeout?: number): Promise<TdObject> => client.send(request, timeout) }, this.chatId,
            (): boolean => this.alive && getTdClient() === client) :
            Promise.resolve({ url: this.link, expiresIn: 0 } as QrLink));
        return request.then((link: QrLink): QrLink => {
          if (!this.alive || getTdClient() !== client) { throw new TdError(499, 'QR closed'); }
          return link;
        }).catch((error: TdError): QrLink => {
          if (this.alive && this.chatId !== 0 && error.code === 403) {
            this.failureText = str('qr_group_unavailable');
          }
          throw error;
        });
      },
      (url: string): Promise<image.PixelMap> => {
        const options: generateBarcode.CreateOptions = {
          scanType: scanCore.ScanType.QR_CODE, height: 400, width: 400, margin: 10
        };
        return generateBarcode.createBarcode(url, options);
      },
      (value: image.PixelMap): void => { value.release().catch((): void => {}); },
      (state: QrSnapshot<image.PixelMap>): void => {
        this.revision++;
        this.pix = state.image;
        this.displayedLink = state.link;
        this.failed = state.failed;
        this.temporary = state.temporary;
      });
    this.session.start();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.revision++;
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

  private async copyLink(): Promise<void> {
    if (this.displayedLink === '') { return; }
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.displayedLink));
      if (this.alive) { showToast(str('copied'), 1200); }
    } catch (_) {
      if (this.alive) { showToast(str('copy_failed'), 2000); }
    }
  }

  @Builder
  imageMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.save') })
        .enabled(this.pix !== null && !this.exporting)
        .onClick((event: ClickEvent): void => { this.exportImage(false, event); });
      MenuItem({ content: $r('app.string.share') })
        .enabled(this.pix !== null && !this.exporting)
        .onClick((event: ClickEvent): void => { this.exportImage(true, event); });
    }
  }

  private async exportImage(share: boolean, event: ClickEvent): Promise<void> {
    if (this.exporting || this.pix === null || this.displayedLink === '') { return; }
    this.exporting = true;
    const revision = this.revision;
    const client = getTdClient();
    const current = (): boolean => this.alive && this.revision === revision && getTdClient() === client;
    const ui = this.getUIContext();
    try {
      await exportQrImage(this.getUIContext().getHostContext() as common.UIAbilityContext, this.displayedLink,
        this.title, share, { windowOffset: { x: ui.vp2px(event.windowX), y: ui.vp2px(event.windowY) } }, current);
    } catch (_) {
      if (current()) { showToast(str(share ? 'share_failed' : 'media_save_failed'), 2000); }
    } finally {
      if (this.alive) { this.exporting = false; }
    }
  }

  build() {
    Column({ space: 20 }) {
      Text(this.title)
        .fontSize(20).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 240 });
      // White backing keeps the code scannable in dark mode.
      Column() {
        if (this.pix !== null) {
          Image(this.pix).draggable(false).width(220).height(220);
        } else if (this.failed) {
          Column({ space: 12 }) {
            Text(this.failureText !== '' ? this.failureText : $r('app.string.qr_failed'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
            Button($r('app.string.settings_retry')).onClick((): void => { this.session?.retry(); });
          }.width(220).height(220).justifyContent(FlexAlign.Center);
        } else {
          Column() {
            LoadingProgress().width(32).height(32).color(COLOR_ICON_SECONDARY);
          }.width(220).height(220).justifyContent(FlexAlign.Center);
        }
      }
      .backgroundColor(Color.White).padding(12).borderRadius(20)
      .bindContextMenu(this.imageMenu, ResponseType.LongPress);
      if (this.displayedLink !== '') {
        Row({ space: 8 }) {
          Text(this.displayedLink).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Button({ type: ButtonType.Circle }) {
            Image($r('sys.media.ohos_ic_public_copy')).width(20).height(20).fillColor(COLOR_PRIMARY);
          }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText(str('copy'))
          .onClick((): void => { this.copyLink(); });
        }
        .width(244).padding({ left: 12, right: 4, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.surface_alt')).borderRadius(14);
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
    .borderRadius(28)
    .alignItems(HorizontalAlign.Center);
  }
}
