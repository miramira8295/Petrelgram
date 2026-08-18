import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { AuthStage } from '../../tdkit/AuthService';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LoginHero } from './LoginHero';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

@Preview
@Component
export struct CodePage {
  // 窗口是全屏沉浸的（EntryAbility.setWindowLayoutFullScreen），页面自己让出
  // 状态栏高度，否则标题会压在时钟和信号图标底下。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @State code: string = '';
  @State errorText: string = '';
  @State resendText: string = '';
  @State busy: boolean = false;
  @State codeLength: number = 5;
  @State phoneNumber: string = '';
  @State codeType: string = '';
  @State codeDestination: string = '';
  @State nextCodeType: string = '';
  @State codeSlots: number[] = [0, 1, 2, 3, 4];
  // 距离允许重发还剩多少秒（来自 codeInfo.timeout）。
  @State resendCountdown: number = 0;
  @State resendAvailable: boolean = false;
  private lastSubmittedCode: string = '';
  private unsubscribeStage: (() => void) | null = null;
  private countdownTimer: number = -1;

  aboutToAppear(): void {
    const auth = getAuthService();
    this.unsubscribeStage = auth.onStageChange((stage: AuthStage): void => {
      if (stage === AuthStage.WaitCode) { this.refreshCodeInfo(); }
    });
    this.refreshCodeInfo();
    setTimeout((): void => {
      focusControl.requestFocus('telegram_login_code');
    }, 220);
  }

  aboutToDisappear(): void {
    this.clearCountdown();
    if (this.unsubscribeStage !== null) {
      this.unsubscribeStage();
      this.unsubscribeStage = null;
    }
  }

  private refreshCodeInfo(): void {
    const auth = getAuthService();
    this.codeLength = auth.getCodeLength();
    this.phoneNumber = auth.getPhoneNumber();
    this.codeType = auth.getCodeType();
    this.codeDestination = auth.getCodeDestination();
    this.nextCodeType = auth.getNextCodeType();
    this.resendAvailable = auth.canResendCode();
    this.startCountdown(auth.getCodeTimeout());
    const slots: number[] = [];
    for (let index = 0; index < this.codeLength; ++index) {
      slots.push(index);
    }
    this.codeSlots = slots;
  }

  // 服务端给的等待时间。到点前重发一定被拒（Code can't be resent），所以
  // 按钮在倒计时期间置灰并显示剩余秒数，而不是让用户点出个报错。
  private startCountdown(seconds: number): void {
    this.clearCountdown();
    this.resendCountdown = Math.max(0, Math.floor(seconds));
    if (this.resendCountdown <= 0) {
      return;
    }
    this.countdownTimer = setInterval((): void => {
      this.resendCountdown = this.resendCountdown - 1;
      if (this.resendCountdown <= 0) {
        this.clearCountdown();
      }
    }, 1000);
  }

  private clearCountdown(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private resendEnabled(): boolean {
    return !this.busy && this.resendAvailable && this.resendCountdown <= 0;
  }

  private phoneTarget(): string {
    return this.phoneNumber !== '' ? this.phoneNumber : str('lg_your_phone');
  }

  private deliveryDescription(): string {
    // str() 出来的是普通字符串，节点只有在构建时读过某个状态才会随它重建。
    // langEpoch 光声明不读，切语言时这段文案纹丝不动 —— 显式读一次建依赖。
    void this.langEpoch;
    switch (this.codeType) {
      case 'authenticationCodeTypeTelegramMessage':
        return str('lg_code_other_device');
      case 'authenticationCodeTypeSms':
      case 'authenticationCodeTypeSmsWord':
      case 'authenticationCodeTypeSmsPhrase':
      case 'authenticationCodeTypeFirebaseAndroid':
        return str('lg_code_sms', this.phoneTarget());
      case 'authenticationCodeTypeCall':
        return str('lg_code_call', this.phoneTarget());
      case 'authenticationCodeTypeFlashCall':
        return str('lg_code_flash_call', this.phoneTarget());
      case 'authenticationCodeTypeMissedCall':
        return str('lg_code_missed_call', this.phoneTarget());
      case 'authenticationCodeTypeEmailAddress':
        return this.codeDestination !== ''
          ? str('lg_code_email_to', this.codeDestination)
          : str('lg_code_email');
      case 'authenticationCodeTypeFragment':
        return str('lg_code_fragment');
      default:
        return this.phoneNumber !== ''
          ? str('lg_code_sent_to', this.phoneNumber)
          : str('lg_code_telegram_or_sms');
    }
  }

  private resendButtonText(): string {
    void this.langEpoch; // 同 deliveryDescription：建立语言依赖
    // 倒计时优先：它反映的是服务端给的等待时间，跟"有没有下一种通道"是两回事。
    if (this.resendCountdown > 0) {
      return plural('lg_resend_in', this.resendCountdown, this.resendCountdown);
    }
    if (!this.resendAvailable) {
      return str('lg_no_resend');
    }
    switch (this.nextCodeType) {
      case 'authenticationCodeTypeTelegramMessage':
        return str('lg_use_telegram');
      case 'authenticationCodeTypeSms':
      case 'authenticationCodeTypeSmsWord':
      case 'authenticationCodeTypeSmsPhrase':
        return str('lg_use_sms');
      case 'authenticationCodeTypeCall':
      case 'authenticationCodeTypeFlashCall':
      case 'authenticationCodeTypeMissedCall':
        return str('lg_use_call');
      default:
        return str('lg_resend');
    }
  }

  private onCodeChange(value: string): void {
    const digits = value.replace(/[^0-9]/g, '');
    const next = digits.substring(0, Math.min(this.codeLength, digits.length));
    this.code = next;
    this.errorText = '';
    this.resendText = '';
    if (next.length === this.codeLength && next !== this.lastSubmittedCode && !this.busy) {
      setTimeout((): void => this.submitCode(), 120);
    }
  }

  private submitCode(): void {
    if (this.busy || this.code.length !== this.codeLength) { return; }
    this.busy = true;
    this.errorText = '';
    this.lastSubmittedCode = this.code;
    getAuthService().submitCode(this.code).catch((caught: TdError): void => {
      this.errorText = caught.message;
      this.code = '';
      this.lastSubmittedCode = '';
      setTimeout((): void => {
        focusControl.requestFocus('telegram_login_code');
      }, 80);
    }).finally((): void => {
      this.busy = false;
    });
  }

  private resendCode(): void {
    if (this.busy) { return; }
    this.busy = true;
    this.errorText = '';
    this.resendText = '';
    getAuthService().resendCode().then((): void => {
      this.resendText = str('lg_code_resent');
      this.code = '';
      this.lastSubmittedCode = '';
      setTimeout((): void => {
        focusControl.requestFocus('telegram_login_code');
      }, 80);
    }).catch((caught: TdError): void => {
      this.errorText = caught.message;
    }).finally((): void => {
      this.busy = false;
    });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'code' });

        Text($r('app.string.lg_enter_code'))
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.deliveryDescription())
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21);

        Stack({ alignContent: Alignment.Center }) {
          Row({ space: 8 }) {
            ForEach(this.codeSlots, (index: number) => {
              Column({ space: 4 }) {
                Text(index < this.code.length ? this.code.substring(index, index + 1) : '_')
                  .fontSize(27)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(index < this.code.length
                    ? COLOR_TEXT_PRIMARY
                    : (index === this.code.length ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY))
                  .textAlign(TextAlign.Center);
                Divider()
                  .strokeWidth(index === this.code.length ? 2.5 : 1.5)
                  .color(index === this.code.length ? COLOR_PRIMARY : '#4D8E8E93');
              }
              .layoutWeight(1)
              .constraintSize({ maxWidth: 48 })
              .height(58)
              .justifyContent(FlexAlign.Center);
            }, (index: number): string => `${index}`);
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 4, right: 4 });

          TextInput({ text: this.code })
            .key('telegram_login_code')
            .type(InputType.Number)
            .maxLength(this.codeLength)
            .fontColor(Color.Transparent)
            .caretColor(Color.Transparent)
            .selectedBackgroundColor(Color.Transparent)
            .backgroundColor(Color.Transparent)
            .width('100%').height(64)
            .opacity(0.02)
            .onChange((value: string): void => this.onCodeChange(value))
            .onSubmit((): void => this.submitCode());
        }
        .width('100%')
        .margin({ top: 10, bottom: 6 })
        .onClick((): void => {
          focusControl.requestFocus('telegram_login_code');
        });

        if (this.busy) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text($r('app.string.lg_verifying')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .textAlign(TextAlign.Center);
        }
        if (this.resendText !== '') {
          Text(this.resendText)
            .width('100%').fontSize(13).fontColor('#34C759')
            .textAlign(TextAlign.Center);
        }

        Button($r('app.string.lg_verify_and_sign_in'))
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY).borderRadius(14)
          .enabled(!this.busy && this.code.length === this.codeLength)
          .onClick((): void => this.submitCode());

        Button(this.resendButtonText())
          .width('100%').height(45)
          .fontSize(14)
          .fontColor(this.resendEnabled() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .enabled(this.resendEnabled())
          .onClick((): void => this.resendCode());
        if (!this.resendAvailable) {
          Text($r('app.string.lg_use_other_device'))
            .width('100%').fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .textAlign(TextAlign.Center);
        }

        if (canReturnToPreviousTdAccount()) {
          Button($r('app.string.lg_back_to_account'))
            .width('100%').height(45)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => {
              this.busy = true;
              returnToPreviousTdAccount().catch((caught: Error): void => {
                this.errorText = caught.message;
                this.busy = false;
              });
            });
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
