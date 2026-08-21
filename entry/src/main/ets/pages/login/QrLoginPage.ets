import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { authErrorText } from '../../util/authErrorText';

interface QrLoginStep {
  index: string;
  text: string;
}

// 函数而非 const：文案来自 str()，调用时才解析。模块级数组在首次 import 时
// 就求值一次，之后语言再怎么变都不会更新（CountryData 里同样的坑）。
function qrSteps(): QrLoginStep[] {
  return [
    { index: '1', text: str('lg_qr_step1') },
    { index: '2', text: str('lg_qr_step2') },
    { index: '3', text: str('lg_qr_step3') }
  ];
}

const QR_PIXEL_SIZE: number = 400;

@Preview
@Component
export struct QrLoginPage {
  // 窗口是全屏沉浸的（EntryAbility.setWindowLayoutFullScreen），页面自己让出
  // 状态栏高度，否则标题会压在时钟和信号图标底下。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // 语言变了要把三条步骤说明重新解析一遍；@Watch 的回调和 build 里读没读过
  // 它无关，所以不需要再 void 一次。
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageChanged') langEpoch: number = 0;
  @State steps: QrLoginStep[] = qrSteps();
  @State link: string = '';
  @State code: image.PixelMap | null = null;
  @State failed: boolean = false;
  @State busy: boolean = false;
  @State errorText: string = '';
  private unsubscribeLink: (() => void) | null = null;
  private disposed: boolean = false;
  // TDLib 周期性刷新 token，二维码生成是异步的；用序号丢弃过期链接的迟到结果，
  // 避免旧二维码覆盖新二维码。
  private renderSeq: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.unsubscribeLink = getAuthService().onQrLinkChange((link: string): void => {
      if (this.disposed || link === this.link) { return; }
      this.link = link;
      this.renderCode(link);
    });
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.unsubscribeLink !== null) {
      this.unsubscribeLink();
      this.unsubscribeLink = null;
    }
  }

  private onLanguageChanged(): void {
    this.steps = qrSteps();
  }

  private renderCode(link: string): void {
    if (link === '') {
      this.code = null;
      return;
    }
    this.renderSeq += 1;
    const seq: number = this.renderSeq;
    // Scan Kit 缺席的环境（模拟器镜像没有 HMS 扫码服务）里 createBarcode 会
    // 既不成功也不报错地挂死，页面永远转圈。10 秒兜底进失败态，用户至少能
    // 看到"生成失败"并改走手机号登录。
    setTimeout((): void => {
      if (this.disposed || seq !== this.renderSeq || this.code !== null) { return; }
      this.failed = true;
    }, 10000);
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      height: QR_PIXEL_SIZE,
      width: QR_PIXEL_SIZE
    };
    generateBarcode.createBarcode(link, options).then((pixels: image.PixelMap): void => {
      if (this.disposed || seq !== this.renderSeq) { return; }
      this.code = pixels;
      this.failed = false;
    }).catch((caught: Object): void => {
      logE(`QrLoginPage.createBarcode failed: ${JSON.stringify(caught)}`);
      if (this.disposed || seq !== this.renderSeq) { return; }
      this.failed = true;
    });
  }

  private switchToPhoneLogin(): void {
    if (this.busy) { return; }
    getAuthService().switchToPhoneLogin();
  }

  private returnToOriginalAccount(): void {
    this.busy = true;
    returnToPreviousTdAccount().catch((caught: Error): void => {
      this.errorText = authErrorText(caught.message);
      this.busy = false;
    });
  }

  @Builder
  qrSurface() {
    // 白底保证深色模式下二维码依然可被扫描。
    Column() {
      if (this.code !== null) {
        Image(this.code).draggable(false).width(212).height(212).interpolation(ImageInterpolation.None);
      } else if (this.failed) {
        Text($r('app.string.lg_qr_failed'))
          .fontSize(14).fontColor('#FF3B30')
          .width(212).height(212).textAlign(TextAlign.Center);
      } else {
        Column() {
          LoadingProgress().width(34).height(34).color(COLOR_TEXT_SECONDARY);
        }.width(212).height(212).justifyContent(FlexAlign.Center);
      }
    }
    .backgroundColor(Color.White)
    .padding(14)
    .borderRadius(18);
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text($r('app.string.lg_qr_title'))
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.lg_qr_body'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21)
          .padding({ left: 18, right: 18 });

        this.qrSurface();

        Column({ space: 12 }) {
          ForEach(this.steps, (step: QrLoginStep) => {
            Row({ space: 12 }) {
              Text(step.index)
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
                .width(24).height(24).textAlign(TextAlign.Center)
                .backgroundColor(COLOR_PRIMARY).borderRadius(12);
              Text(step.text)
                .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                .layoutWeight(1);
            }
            .width('100%')
            .alignItems(VerticalAlign.Center);
            // 键里带上文案：ForEach 对键没变的项直接复用旧节点，只用序号做键
            // 的话切了语言文字不会更新。
          }, (step: QrLoginStep): string => `${step.index}_${step.text}`);
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start);

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button($r('app.string.lg_use_phone'))
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(Color.Transparent)
          .enabled(!this.busy)
          .onClick((): void => this.switchToPhoneLogin());

        if (canReturnToPreviousTdAccount()) {
          Button($r('app.string.lg_back_to_account'))
            .width('100%').height(45)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => this.returnToOriginalAccount());
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 430 })
      .padding({ left: 24, right: 24, top: this.topSafe + 28, bottom: 28 });
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_bg'));
  }
}
