import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { AuthStage } from '../tdkit/AuthService';
import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../tdkit/Globals';
import { PhoneNumberPage } from './login/PhoneNumberPage';
import { CodePage } from './login/CodePage';
import { PasswordPage } from './login/PasswordPage';
import { RegisterPage } from './login/RegisterPage';
import { QrLoginPage } from './login/QrLoginPage';
import { MainScreen } from './main/MainScreen';
import { handleIncomingLink } from '../util/deepLink';
import { COLOR_TEXT_PRIMARY } from '../util/theme';
import { refreshNetworkState } from '../services/NetworkStateService';
import { navigateToChat } from '../util/chatNav';

@Entry
@Preview
@Component
struct Index {
  @State stage: AuthStage = AuthStage.Init;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageLink('tdSessionEpoch') @Watch('onTdSessionEpoch') tdSessionEpoch: number = 0;
  @StorageLink('tdAccountRegistryEpoch') tdAccountRegistryEpoch: number = 0;
  @StorageLink('tdAccountSwitching') tdAccountSwitching: boolean = false;
  // Set by EntryAbility when the app is opened via a tg:// deep link. Held here
  // until auth is Ready (routing needs a logged-in session + a live router).
  @StorageLink('pendingDeepLink') @Watch('onDeepLink') pendingDeepLink: string = '';
  // 点击本地通知进入的目标会话（EntryAbility 写入，登录就绪后路由）。
  @StorageLink('pendingNotifyChatId') @Watch('onNotifyChat') pendingNotifyChatId: number = 0;
  private offAuth: (() => void) | null = null;

  aboutToAppear(): void {
    this.bindAuthService();
  }

  aboutToDisappear(): void {
    if (this.offAuth !== null) {
      this.offAuth();
      this.offAuth = null;
    }
  }

  private onTdSessionEpoch(): void {
    this.bindAuthService();
    // Account switching replaces the TDLib client while the Ability can stay in
    // foreground. Republish the current bearer to the new client immediately.
    refreshNetworkState(true);
  }

  private bindAuthService(): void {
    if (this.offAuth !== null) {
      this.offAuth();
      this.offAuth = null;
    }
    this.stage = AuthStage.Init;
    this.offAuth = getAuthService().onStageChange((s: AuthStage): void => {
      this.stage = s;
      // A link that arrived (or waited) through cold start / login flow.
      this.consumeDeepLink();
      this.consumeNotifyChat();
    });
  }

  // Fires when a deep link arrives while the app is already running.
  private onDeepLink(): void {
    this.consumeDeepLink();
  }

  private onNotifyChat(): void {
    this.consumeNotifyChat();
  }

  private consumeNotifyChat(): void {
    if (this.stage !== AuthStage.Ready || this.pendingNotifyChatId === 0) {
      return;
    }
    const chatId: number = this.pendingNotifyChatId;
    this.pendingNotifyChatId = 0;
    const params: Record<string, Object> = { 'chatId': chatId };
    navigateToChat(params);
  }

  // Route the pending link only once signed in; otherwise leave it queued for
  // the next stage change. Clear before routing so it's handled exactly once.
  private consumeDeepLink(): void {
    if (this.stage !== AuthStage.Ready || this.pendingDeepLink === '') {
      return;
    }
    const uri = this.pendingDeepLink;
    this.pendingDeepLink = '';
    handleIncomingLink(getContext(this) as common.UIAbilityContext, uri);
  }

  private isAddingAccount(): boolean {
    return this.stage !== AuthStage.Ready && canReturnToPreviousTdAccount();
  }

  private returnToOriginalAccount(): void {
    if (this.tdAccountSwitching || !this.isAddingAccount()) { return; }
    returnToPreviousTdAccount().catch((caught: Error): void => {
      console.error(`Index.returnToOriginalAccount failed: ${caught.message}`);
      promptAction.showToast({ message: '返回原账号失败，请重试', duration: 1800 });
    });
  }

  onBackPress(): boolean {
    if (!this.isAddingAccount()) { return false; }
    this.returnToOriginalAccount();
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.tdAccountSwitching) {
          LoadingProgress().width(48).height(48)
        } else if (this.stage === AuthStage.WaitPhone) {
          PhoneNumberPage()
        } else if (this.stage === AuthStage.WaitQrCode) {
          QrLoginPage()
        } else if (this.stage === AuthStage.WaitCode) {
          CodePage()
        } else if (this.stage === AuthStage.WaitPassword) {
          PasswordPage()
        } else if (this.stage === AuthStage.WaitRegistration) {
          RegisterPage()
        } else if (this.stage === AuthStage.Ready) {
          MainScreen()
        } else if (this.stage === AuthStage.LoggedOut) {
          PhoneNumberPage()
        } else {
          LoadingProgress().width(48).height(48)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);

      if (this.isAddingAccount() && !this.tdAccountSwitching) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(23).fontColor([COLOR_TEXT_PRIMARY]);
          Text('返回原账号')
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        }
        .height(42)
        .padding({ left: 8, right: 12 })
        .margin({ left: 8, top: 4 })
        .borderRadius(21)
        .onClick((): void => this.returnToOriginalAccount());
      }
    }
    .width('100%')
    .height('100%')
    // ChatListPage does its own full-screen top inset; pad only the login stages.
    .padding({ top: this.stage === AuthStage.Ready ? 0 : this.topSafe })
  }
}
