import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LoginHero } from './LoginHero';
import { authErrorText } from '../../util/authErrorText';

@Preview
@Component
export struct PasswordPage {
  // 窗口是全屏沉浸的（EntryAbility.setWindowLayoutFullScreen），页面自己让出
  // 状态栏高度，否则标题会压在时钟和信号图标底下。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State password: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;

  private submitPassword(): void {
    if (this.busy || this.password === '') { return; }
    this.busy = true;
    this.errorText = '';
    getAuthService().submitPassword(this.password).catch((caught: TdError): void => {
      this.errorText = authErrorText(caught.message);
    }).finally((): void => {
      this.busy = false;
    });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'password', active: this.password !== '' });

        Text($r('app.string.ps_two_step'))
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.lg_password_hint'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21)
          .padding({ left: 18, right: 18 });

        TextInput({ text: this.password, placeholder: $r('app.string.lg_password') })
          .type(InputType.Password)
          .showPasswordIcon(true)
          .fontSize(17).fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(COLOR_PRIMARY)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(13)
          .border({ width: 1, color: this.errorText !== '' ? '#FF3B30' : '#263390EC' })
          .width('100%').height(54)
          .padding({ left: 14, right: 12 })
          .enterKeyType(EnterKeyType.Go)
          .onChange((value: string): void => {
            this.password = value;
            this.errorText = '';
          })
          .onSubmit((): void => this.submitPassword());

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button(this.busy ? $r('app.string.lg_verifying') : $r('app.string.lg_continue'))
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY).borderRadius(14)
          .enabled(!this.busy && this.password !== '')
          .onClick((): void => this.submitPassword());

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
