import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LoginHero } from './LoginHero';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { authErrorText } from '../../util/authErrorText';

// 号码尚未注册 Telegram 时走到这里（authorizationStateWaitRegistration）。
// 此前没有这个页面，该状态映射不到任何 stage，界面会停在验证码页毫无反应 ——
// 用户只会觉得"验证码输对了但没下文"。
//
// 服务条款必须展示并显式同意：它是 Telegram 注册流程的一部分，不是可选的礼貌。
@Preview
@Component
export struct RegisterPage {
  // 窗口是全屏沉浸的（EntryAbility.setWindowLayoutFullScreen），页面自己让出
  // 状态栏高度，否则标题会压在时钟和信号图标底下。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @State firstName: string = '';
  @State lastName: string = '';
  @State termsText: string = '';
  @State minUserAge: number = 0;
  @State agreed: boolean = false;
  @State errorText: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    const auth = getAuthService();
    this.termsText = auth.getTermsOfServiceText();
    this.minUserAge = auth.getTermsMinUserAge();
  }

  private canSubmit(): boolean {
    return !this.busy && this.firstName.trim() !== '' && this.agreed;
  }

  private submit(): void {
    if (!this.canSubmit()) { return; }
    this.busy = true;
    this.errorText = '';
    getAuthService().registerUser(this.firstName.trim(), this.lastName.trim())
      .catch((caught: TdError): void => {
        this.errorText = authErrorText(caught.message);
      })
      .finally((): void => {
        this.busy = false;
      });
  }

  private agreementLabel(): string {
    void this.langEpoch;
    return this.minUserAge > 0
      ? str('lg_terms_with_age', this.minUserAge)
      : str('lg_terms');
  }

  // str() 出来的是普通字符串，节点只有在构建时读过某个状态才会随它重建。
  // langEpoch 光声明不读，切语言时这些文案纹丝不动 —— 经这里显式读一次。
  private label(key: string): string {
    void this.langEpoch;
    return str(key);
  }

  @Builder
  private nameField(placeholder: string, value: string, required: boolean,
    onInput: (v: string) => void) {
    TextInput({ text: value, placeholder: placeholder })
      .fontSize(17).fontColor(COLOR_TEXT_PRIMARY)
      .placeholderColor(COLOR_TEXT_SECONDARY)
      .caretColor(COLOR_PRIMARY)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(13)
      .border({
        width: 1,
        color: required && this.errorText !== '' ? '#FF3B30' : '#263390EC'
      })
      .width('100%').height(54)
      .padding({ left: 14, right: 12 })
      .enterKeyType(EnterKeyType.Next)
      .onChange((v: string): void => {
        onInput(v);
        this.errorText = '';
      });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'phone', active: this.firstName !== '' });

        Text($r('app.string.lg_create_account'))
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.lg_no_account_yet'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21)
          .padding({ left: 18, right: 18 });

        this.nameField(this.label('ct_first_name'), this.firstName, true,
          (v: string): void => { this.firstName = v; });
        this.nameField(this.label('lg_last_name_optional'), this.lastName, false,
          (v: string): void => { this.lastName = v; });

        if (this.termsText !== '') {
          Scroll() {
            Text(this.termsText)
              .fontSize(12.5).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19)
              .width('100%');
          }
          .width('100%').height(160)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(13)
          .scrollBar(BarState.Auto)
          .align(Alignment.Top);
        }

        Row({ space: 10 }) {
          Checkbox()
            .select(this.agreed)
            .selectedColor(COLOR_PRIMARY)
            .onChange((checked: boolean): void => { this.agreed = checked; });
          Text(this.agreementLabel())
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .layoutWeight(1);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button(this.busy ? $r('app.string.lg_creating') : $r('app.string.lg_create_account'))
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY).borderRadius(14)
          .enabled(this.canSubmit())
          .onClick((): void => this.submit());

        if (canReturnToPreviousTdAccount()) {
          Button($r('app.string.lg_back_to_account'))
            .width('100%').height(45)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => {
              this.busy = true;
              returnToPreviousTdAccount().catch((caught: Error): void => {
                this.errorText = authErrorText(caught.message);
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
