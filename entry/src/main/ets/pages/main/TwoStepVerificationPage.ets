import { router, promptAction } from '@kit.ArkUI';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  cancelRecoveryEmailVerification, checkRecoveryEmailCode, getPasswordState,
  recoverPassword, requestPasswordRecovery, resendRecoveryEmailCode, setPassword, setRecoveryEmail
} from '../../store/PrivacyApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { contentSideGutter } from '../../util/contentWidth';

const CARD_RADIUS: number = 16;
const COLOR_DANGER: string = '#E5484D';

@Entry
@Component
struct TwoStepVerificationPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State loadState: string = 'loading';
  @State passwordState: TdObject | null = null;
  @State mode: string = 'password';
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State hint: string = '';
  @State recoveryEmail: string = '';
  @State code: string = '';
  @State errorText: string = '';
  @State saving: boolean = false;
  @State revealPassword: boolean = false;
  @State recoveryPattern: string = '';
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
    this.oldPassword = '';
    this.newPassword = '';
    this.confirmPassword = '';
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    getPasswordState().then((state: TdObject): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      this.passwordState = state;
      this.hint = (state['password_hint'] as string | undefined) ?? '';
      this.loadState = 'ready';
      this.errorText = '';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      logE(`TwoStepVerificationPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private hasPassword(): boolean {
    return this.passwordState !== null &&
      ((this.passwordState['has_password'] as boolean | undefined) ?? false);
  }

  private pendingEmailInfo(): TdObject | null {
    if (this.passwordState === null) { return null; }
    return (this.passwordState['recovery_email_address_code_info'] as TdObject | undefined) ?? null;
  }

  private clearSensitive(): void {
    this.oldPassword = '';
    this.newPassword = '';
    this.confirmPassword = '';
    this.code = '';
  }

  private friendlyError(error: TdError): string {
    const message = error.message.toUpperCase();
    if (message.indexOf('PASSWORD_HASH_INVALID') >= 0) { return str('tsv_wrong_password'); }
    if (message.indexOf('PASSWORD_TOO_FRESH') >= 0) { return str('tsv_too_soon'); }
    if (message.indexOf('NEW_PASSWORD_BAD') >= 0) { return str('tsv_weak_password'); }
    if (message.indexOf('EMAIL_INVALID') >= 0) { return str('tsv_bad_email'); }
    if (message.indexOf('CODE_INVALID') >= 0) { return str('tsv_bad_code'); }
    if (message.indexOf('FLOOD_WAIT') >= 0) { return str('too_many_attempts'); }
    return str('ae_save_failed');
  }

  private validatePasswordForm(): boolean {
    this.errorText = '';
    if (this.hasPassword() && this.oldPassword.length === 0) {
      this.errorText = str('tsv_enter_password'); return false;
    }
    if (this.newPassword.length < 4) {
      this.errorText = str('tsv_min_length'); return false;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.errorText = str('tsv_mismatch'); return false;
    }
    if (this.hint !== '' && this.hint === this.newPassword) {
      this.errorText = str('tsv_hint_equals_password'); return false;
    }
    return true;
  }

  private savePassword(): void {
    if (this.saving || !this.validatePasswordForm()) { return; }
    const wasEnabled = this.hasPassword();
    this.saving = true;
    const setEmail = !wasEnabled && this.recoveryEmail.trim() !== '';
    setPassword(this.oldPassword, this.newPassword, this.hint.trim(), setEmail,
      this.recoveryEmail.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.clearSensitive();
      promptAction.showToast({ message: wasEnabled ? $r('app.string.tsv_updated') : $r('app.string.tsv_enabled'), duration: 1600 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private beginRecovery(): void {
    if (this.saving) { return; }
    const hasEmail = this.passwordState !== null &&
      ((this.passwordState['has_recovery_email_address'] as boolean | undefined) ?? false);
    if (!hasEmail) {
      this.errorText = str('tsv_no_recovery_email');
      return;
    }
    this.saving = true;
    requestPasswordRecovery().then((info: TdObject): void => {
      if (!this.active) { return; }
      this.recoveryPattern = (info['email_address_pattern'] as string | undefined) ?? str('tsv_recovery_email');
      this.mode = 'recover';
      this.code = '';
      this.newPassword = '';
      this.confirmPassword = '';
      this.errorText = '';
      this.saving = false;
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private finishRecovery(): void {
    if (this.saving) { return; }
    this.errorText = '';
    if (this.code.trim() === '') { this.errorText = str('tsv_enter_code'); return; }
    if (this.newPassword.length < 4) { this.errorText = str('tsv_min_length'); return; }
    if (this.newPassword !== this.confirmPassword) { this.errorText = str('tsv_mismatch'); return; }
    this.saving = true;
    recoverPassword(this.code.trim(), this.newPassword, this.hint.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.mode = 'password';
      this.recoveryPattern = '';
      this.saving = false;
      this.clearSensitive();
      promptAction.showToast({ message: $r('app.string.tsv_reset_done'), duration: 1700 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private saveEmail(): void {
    if (this.saving) { return; }
    this.errorText = '';
    if (this.oldPassword === '') { this.errorText = str('tsv_enter_password'); return; }
    if (this.recoveryEmail.trim().indexOf('@') <= 0) { this.errorText = str('tsv_enter_email'); return; }
    this.saving = true;
    setRecoveryEmail(this.oldPassword, this.recoveryEmail.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.oldPassword = '';
      this.recoveryEmail = '';
      this.errorText = '';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private verifyEmail(): void {
    if (this.saving || this.code.trim() === '') { return; }
    this.saving = true;
    checkRecoveryEmailCode(this.code.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.code = '';
      promptAction.showToast({ message: $r('app.string.tsv_email_confirmed'), duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private resendCode(): void {
    if (this.saving) { return; }
    this.saving = true;
    resendRecoveryEmailCode().then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      promptAction.showToast({ message: $r('app.string.tsv_code_resent'), duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private cancelEmail(): void {
    if (this.saving) { return; }
    this.saving = true;
    cancelRecoveryEmailVerification().then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.code = '';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private confirmDisable(): void {
    if (this.saving) { return; }
    if (this.oldPassword === '') { this.errorText = str('tsv_password_before_disable'); return; }
    promptAction.showDialog({
      title: $r('app.string.tsv_disable'),
      message: $r('app.string.tsv_disable_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.turn_off'), color: COLOR_DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.saving) { return; }
      this.saving = true;
      setPassword(this.oldPassword, '', '', false, '').then((state: TdObject): void => {
        if (!this.active) { return; }
        this.passwordState = state;
        this.saving = false;
        this.clearSensitive();
        this.mode = 'password';
        promptAction.showToast({ message: $r('app.string.tsv_disabled'), duration: 1600 });
      }).catch((error: TdError): void => {
        if (!this.active) { return; }
        this.saving = false;
        this.errorText = this.friendlyError(error);
      });
    }).catch((): void => {});
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.ps_two_step')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.saving) { LoadingProgress().width(21).height(21).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  passwordInput(value: string, placeholder: ResourceStr, onChange: (value: string) => void) {
    TextInput({ text: value, placeholder })
      .type(this.revealPassword ? InputType.Normal : InputType.Password)
      .height(48).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).placeholderColor(COLOR_TEXT_SECONDARY)
      .caretColor(COLOR_PRIMARY).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
      .padding({ left: 14, right: 14 }).enabled(!this.saving)
      .onChange((text: string): void => { onChange(text); this.errorText = ''; });
  }

  @Builder
  pendingEmailCard(info: TdObject) {
    Column({ space: 12 }) {
      Text($r('app.string.tsv_confirm_email')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%');
      Text(str('tsv_code_sent_note', (info['email_address_pattern'] as string | undefined) ?? str('tsv_your_email')))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).width('100%');
      TextInput({ text: this.code, placeholder: $r('app.string.tsv_email_code') })
        .type(InputType.Number).height(48).fontSize(17).caretColor(COLOR_PRIMARY)
        .backgroundColor($r('app.color.surface_alt')).borderRadius(12).padding({ left: 14, right: 14 })
        .onChange((value: string): void => { this.code = value; this.errorText = ''; });
      Button(this.saving ? $r('app.string.verifying') : $r('app.string.tsv_confirm_email_button')).width('100%').height(46).borderRadius(23)
        .fontColor(Color.White).backgroundColor(COLOR_PRIMARY).enabled(!this.saving && this.code.trim() !== '')
        .onClick((): void => { this.verifyEmail(); });
      Row() {
        Text($r('app.string.resend')).fontSize(14).fontColor(COLOR_PRIMARY).onClick((): void => { this.resendCode(); });
        Blank();
        Text($r('app.string.cancel_change')).fontSize(14).fontColor(COLOR_DANGER).onClick((): void => { this.cancelEmail(); });
      }.width('100%');
    }
    .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  modePicker() {
    Row() {
      ForEach(['password', 'email', 'disable'], (mode: string) => {
        Text(mode === 'password' ? $r('app.string.tsv_change_password') : (mode === 'email' ? $r('app.string.tsv_recovery_email') : $r('app.string.turn_off')))
          .fontSize(14).fontWeight(this.mode === mode ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.mode === mode ? Color.White : COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).layoutWeight(1).height(36)
          .backgroundColor(this.mode === mode ? COLOR_PRIMARY : Color.Transparent)
          .borderRadius(18).onClick((): void => { if (!this.saving) { this.mode = mode; this.errorText = ''; } });
      }, (mode: string): string => `password_mode_${mode}_${this.mode}`);
    }
    .width('100%').padding(3).backgroundColor($r('app.color.surface_alt')).borderRadius(21);
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column() { LoadingProgress().width(34).height(34).color(COLOR_PRIMARY); }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.tsv_load_failed')).fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => { this.load(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.pendingEmailInfo() !== null) {
              this.pendingEmailCard(this.pendingEmailInfo() as TdObject);
            }

            Column({ space: 8 }) {
              SymbolGlyph($r(this.hasPassword() ? 'sys.symbol.lock_fill' : 'sys.symbol.lock_open_fill'))
                .fontSize(48).fontColor([this.hasPassword() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
              Text(this.hasPassword() ? $r('app.string.tsv_enabled') : $r('app.string.tsv_protect_sub'))
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
              Text(this.hasPassword()
                ? $r('app.string.tsv_explain_1')
                : $r('app.string.tsv_explain_2'))
                .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).textAlign(TextAlign.Center);
            }
            .width('100%').padding({ left: 22, right: 22, top: 18, bottom: 18 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            if (this.hasPassword() && this.mode !== 'recover') { this.modePicker(); }

            Column({ space: 11 }) {
              if (this.hasPassword() && this.mode !== 'recover') {
                Text($r('app.string.tsv_current_password')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                this.passwordInput(this.oldPassword, $r('app.string.tsv_enter_current'), (value: string): void => { this.oldPassword = value; });
                if (this.mode !== 'disable') {
                  Text($r('app.string.tsv_forgot')).fontSize(13).fontColor(COLOR_PRIMARY)
                    .width('100%').textAlign(TextAlign.End)
                    .onClick((): void => { this.beginRecovery(); });
                }
              }

              if (this.mode === 'recover') {
                Text(str('tsv_code_sent', this.recoveryPattern)).fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY).width('100%');
                TextInput({ text: this.code, placeholder: $r('app.string.tsv_email_code') })
                  .type(InputType.Number).height(48).fontSize(17)
                  .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.code = value; this.errorText = ''; });
                this.passwordInput(this.newPassword, $r('app.string.tsv_set_new'), (value: string): void => { this.newPassword = value; });
                this.passwordInput(this.confirmPassword, $r('app.string.tsv_repeat_new'),
                  (value: string): void => { this.confirmPassword = value; });
                TextInput({ text: this.hint, placeholder: $r('app.string.tsv_new_hint') })
                  .height(48).fontSize(16).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.hint = value; this.errorText = ''; });
              } else if (!this.hasPassword() || this.mode === 'password') {
                Text(this.hasPassword() ? $r('app.string.tsv_new_password') : $r('app.string.tsv_set_password')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                this.passwordInput(this.newPassword, $r('app.string.tsv_min_chars'), (value: string): void => { this.newPassword = value; });
                this.passwordInput(this.confirmPassword, $r('app.string.tsv_repeat_new'),
                  (value: string): void => { this.confirmPassword = value; });
                TextInput({ text: this.hint, placeholder: $r('app.string.tsv_hint') })
                  .height(48).fontSize(16).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.hint = value; this.errorText = ''; });
                if (!this.hasPassword()) {
                  TextInput({ text: this.recoveryEmail, placeholder: $r('app.string.tsv_recovery_email_recommended') })
                    .type(InputType.Email).height(48).fontSize(16)
                    .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                    .padding({ left: 14, right: 14 }).enabled(!this.saving)
                    .onChange((value: string): void => { this.recoveryEmail = value; this.errorText = ''; });
                }
              } else if (this.mode === 'email') {
                Text($r('app.string.tsv_recovery_email')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                TextInput({ text: this.recoveryEmail, placeholder: 'name@example.com' })
                  .type(InputType.Email).height(48).fontSize(16)
                  .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.recoveryEmail = value; this.errorText = ''; });
              } else {
                Text($r('app.string.tsv_disable_note'))
                  .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).width('100%');
              }

              Row() {
                Text($r('app.string.tsv_show_password')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.revealPassword }).selectedColor(COLOR_PRIMARY)
                  .onChange((value: boolean): void => { this.revealPassword = value; });
              }.width('100%').height(42);

              if (this.errorText !== '') {
                Text(this.errorText).fontSize(13).fontColor(COLOR_DANGER).width('100%');
              }

              Button(this.saving ? $r('app.string.saving') :
                (this.mode === 'recover' ? $r('app.string.tsv_reset_password') : (!this.hasPassword() ? $r('app.string.tsv_enable') :
                  (this.mode === 'password' ? $r('app.string.tsv_save_new') : (this.mode === 'email' ? $r('app.string.tsv_update_email') : $r('app.string.tsv_disable'))))))
                .width('100%').height(48).borderRadius(24).fontSize(16).fontWeight(FontWeight.Medium)
                .fontColor(Color.White).backgroundColor(this.mode === 'disable' ? COLOR_DANGER : COLOR_PRIMARY)
                .enabled(!this.saving)
                .onClick((): void => {
                  if (this.mode === 'recover') { this.finishRecovery(); }
                  else if (!this.hasPassword() || this.mode === 'password') { this.savePassword(); }
                  else if (this.mode === 'email') { this.saveEmail(); }
                  else { this.confirmDisable(); }
                });
            }
            .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .alignItems(HorizontalAlign.Start);

            Text($r('app.string.tsv_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
              .width('100%').padding({ left: 16, right: 16 });
          }
          .width('100%')
          // 限宽做在内容列的内边距上而不是 Scroll 的宽度上：Scroll 仍铺满窗口，
          // 两侧让出来的留白因此还在它的命中区里，手指按在留白上照样能滚页面。
          // 密码输入框跟着这一列收窄，不再在 2880px 上拉成一条通栏。
          // 手机上 contentSideGutter 恒为 0，两个值逐像素等于改动前的 12。
          .padding({
            left: 12 + contentSideGutter(this.screenW),
            right: 12 + contentSideGutter(this.screenW),
            top: 6,
            bottom: this.bottomSafe + 24
          });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
