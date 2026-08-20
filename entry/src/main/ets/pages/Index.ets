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
import { getTdClient } from '../tdkit/Globals';
import { TdObject } from '../tdkit/TdTypes';

// 冷启动时等连接就绪的上限。超过就照常放行——离线时压着链接不处理更糟。
const DEEP_LINK_CONNECT_WAIT_MS: number = 8000;

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
  // 深链要等的是**连接**就绪，不是登录就绪。见 consumeDeepLink 的说明。
  private offConn: (() => void) | null = null;
  private connReady: boolean = false;
  private deepLinkTimer: number = -1;

  aboutToAppear(): void {
    this.bindAuthService();
    this.offConn = getTdClient().onUpdate('updateConnectionState', (u: TdObject): void => {
      const st: TdObject | undefined = u['state'] as TdObject | undefined;
      const name: string = st !== undefined ? ((st['@type'] as string | undefined) ?? '') : '';
      // Updating 也算连上了：那时已经能发请求，只是还在补历史。
      this.connReady = name === 'connectionStateReady' || name === 'connectionStateUpdating';
      if (this.connReady) {
        this.consumeDeepLink();
      }
    });
  }

  aboutToDisappear(): void {
    if (this.offConn !== null) {
      this.offConn();
      this.offConn = null;
    }
    if (this.deepLinkTimer !== -1) {
      clearTimeout(this.deepLinkTimer);
      this.deepLinkTimer = -1;
    }
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

  // 路由待处理的深链。条件是**登录就绪 + 连接就绪**，两个都要。
  //
  // 只等 AuthStage.Ready 是不够的：那对应 TDLib 的 authorizationStateReady，
  // 意思是"你已登录"——它从本地库读出登录态就立刻发出来，比真正连上服务器早
  // 得多，走代理时差得更远。而 t.me/<用户名> 这类链接的解析（searchPublicChat）
  // 必须走一次实时往返，连接没建好就会失败，最后弹一句"无法识别该链接"。
  // 用户看到的现象正是：同一个链接应用内点能跳，从浏览器冷启动进来就说不认识。
  //
  // 兜底超时：真的离线时也不能把链接一直压着不处理，到点照常放行，让它走正常
  // 的失败路径给出提示。
  private consumeDeepLink(): void {
    if (this.pendingDeepLink !== '') {
      console.warn(`[LinkDiag] consume stage=${this.stage} connReady=${this.connReady}` +
        ` uri=${this.pendingDeepLink}`);
    }
    if (this.stage !== AuthStage.Ready || this.pendingDeepLink === '') {
      return;
    }
    if (!this.connReady) {
      if (this.deepLinkTimer === -1) {
        this.deepLinkTimer = setTimeout((): void => {
          this.deepLinkTimer = -1;
          this.connReady = true; // 等够了就按"能发请求"处理，失败自有提示
          this.consumeDeepLink();
        }, DEEP_LINK_CONNECT_WAIT_MS);
      }
      return;
    }
    if (this.deepLinkTimer !== -1) {
      clearTimeout(this.deepLinkTimer);
      this.deepLinkTimer = -1;
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
