import { TdClient } from './TdClient';
import { TdObject, TdRequest } from './TdTypes';
import { clientRev, clientSig } from './ApiCredentials';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { str } from '../util/strings';
import { logE, logW } from '../util/log';

export enum AuthStage {
  Init = 'Init',
  WaitPhone = 'WaitPhone',
  WaitQrCode = 'WaitQrCode',
  WaitCode = 'WaitCode',
  WaitPassword = 'WaitPassword',
  WaitRegistration = 'WaitRegistration',
  Ready = 'Ready',
  LoggedOut = 'LoggedOut'
}

const QR_CONFIRMATION_STATE: string = 'authorizationStateWaitOtherDeviceConfirmation';

// Set true to connect to Telegram's test datacenter, which validates the login
// flow end-to-end without SMS or production flood limits. Test phone numbers are
// 99966<dc><4 digits> (e.g. 9996627777 for DC 2); the login code is the dc id
// repeated to the code length (DC 2 -> "22222"). Keep false for real accounts.
const USE_TEST_DC: boolean = false;

const STATE_TO_STAGE: Map<string, AuthStage> = new Map([
  ['authorizationStateWaitPhoneNumber', AuthStage.WaitPhone],
  [QR_CONFIRMATION_STATE, AuthStage.WaitQrCode],
  ['authorizationStateWaitCode', AuthStage.WaitCode],
  ['authorizationStateWaitPassword', AuthStage.WaitPassword],
  ['authorizationStateWaitRegistration', AuthStage.WaitRegistration],
  ['authorizationStateReady', AuthStage.Ready],
  ['authorizationStateClosed', AuthStage.LoggedOut],
  ['authorizationStateLoggingOut', AuthStage.LoggedOut],
]);

export class AuthService {
  private client: TdClient;
  private databaseDirectory: string;
  private filesDirectory: string;
  private callbacks: Array<(stage: AuthStage) => void> = [];
  private closedCallbacks: Array<() => void> = [];
  private currentStage: AuthStage = AuthStage.Init;
  private currentAuthType: string = '';
  private authenticationPhoneNumber: string = '';
  private authenticationCodeLength: number = 5;
  private authenticationCodeType: string = '';
  // codeInfo.timeout：还要等多少秒才允许重发。0 表示没有等待限制。
  private authenticationCodeTimeout: number = 0;
  // authorizationStateWaitRegistration 携带的服务条款：注册流程要求展示并同意。
  private termsOfServiceText: string = '';
  private termsMinUserAge: number = 0;
  private authenticationCodeDestination: string = '';
  private nextAuthenticationCodeType: string = '';
  private qrLoginLink: string = '';
  private qrLinkCallbacks: Array<(link: string) => void> = [];
  // 用户在扫码页选择「改用手机号登录」后置位。TDLib 仍会周期性推送新的
  // WaitOtherDeviceConfirmation（token 刷新），若不记住这个选择，用户会被反复
  // 拽回扫码页。setAuthenticationPhoneNumber 在该状态下依然可用，所以本地
  // 直接把阶段回退到 WaitPhone 即可，无需先取消服务端的扫码会话。
  private phoneLoginPreferred: boolean = false;
  private offAuthorizationState: (() => void) | null = null;

  constructor(client: TdClient, databaseDirectory: string, filesDirectory: string) {
    this.client = client;
    this.databaseDirectory = databaseDirectory;
    this.filesDirectory = filesDirectory;
    this.offAuthorizationState =
      client.onUpdate('updateAuthorizationState', (u: TdObject) => this.onAuthState(u));
  }

  // Registers a listener and immediately replays the current stage, so a
  // subscriber that mounts after the auth state has already arrived is not
  // left waiting for the next transition.
  onStageChange(cb: (stage: AuthStage) => void): () => void {
    this.callbacks = [...this.callbacks, cb];
    cb(this.currentStage);
    return (): void => {
      this.callbacks = this.callbacks.filter(
        (current: (stage: AuthStage) => void): boolean => current !== cb
      );
    };
  }

  // 注册二维码链接监听并立即回放当前链接：扫码页可能在链接到达之后才挂载，
  // 没有回放就会一直空白等待下一次 token 刷新。
  onQrLinkChange(cb: (link: string) => void): () => void {
    this.qrLinkCallbacks = [...this.qrLinkCallbacks, cb];
    cb(this.qrLoginLink);
    return (): void => {
      this.qrLinkCallbacks = this.qrLinkCallbacks.filter(
        (current: (link: string) => void): boolean => current !== cb
      );
    };
  }

  getQrLoginLink(): string {
    return this.qrLoginLink;
  }

  // 请求扫码登录：TDLib 随后进入 WaitOtherDeviceConfirmation 并给出 tg://login 链接。
  // other_user_ids 仅用于「同一设备上的已登录账号免确认」，本机是新会话故传空。
  async requestQrLogin(): Promise<void> {
    this.phoneLoginPreferred = false;
    const request: TdRequest = { '@type': 'requestQrCodeAuthentication' };
    request['other_user_ids'] = [];
    await this.client.send(request);
  }

  // 从扫码页退回手机号登录。不向 TDLib 发请求，避免打断仍然有效的授权会话；
  // 用户输入手机号后 setAuthenticationPhoneNumber 会自然覆盖扫码状态。
  switchToPhoneLogin(): void {
    if (this.currentStage !== AuthStage.WaitQrCode) {
      return;
    }
    this.phoneLoginPreferred = true;
    this.setQrLoginLink('');
    this.emitStage(AuthStage.WaitPhone);
  }

  async submitPhone(phone: string): Promise<void> {
    const request: TdRequest = { '@type': 'setAuthenticationPhoneNumber' };
    request['phone_number'] = phone;
    // 从扫码态切回手机号时，TDLib 要求"没有在途的鉴权请求"才接受这次提交；
    // 而扫码 token 每 30 秒刷新一次，慢链路（代理）下刷新请求经常正好在途，
    // 撞上就报 "Call to setAuthenticationPhoneNumber unexpected"。这是纯时机
    // 问题，等一拍重试即可，不该把错误甩给用户（模拟器实测复现）。
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await this.client.send(request);
        return;
      } catch (e) {
        lastError = e as Error;
        if (`${lastError.message}`.indexOf('unexpected') < 0) {
          throw lastError; // 真错误（号码格式等）不重试
        }
        await new Promise<void>((resolve: (v: void) => void): void => {
          setTimeout((): void => resolve(), 1500);
        });
      }
    }
    throw lastError ?? new Error('setAuthenticationPhoneNumber failed');
  }

  async submitCode(code: string): Promise<void> {
    const request: TdRequest = { '@type': 'checkAuthenticationCode' };
    request['code'] = code;
    await this.client.send(request);
  }

  async submitPassword(pw: string): Promise<void> {
    const request: TdRequest = { '@type': 'checkAuthenticationPassword' };
    request['password'] = pw;
    await this.client.send(request);
  }

  async logOut(): Promise<void> {
    const request: TdRequest = { '@type': 'logOut' };
    await this.client.send(request);
    if (this.currentAuthType === 'authorizationStateClosed') {
      return;
    }
    await new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      let finished: boolean = false;
      let timer: number = -1;
      const complete = (): void => {
        if (finished) { return; }
        finished = true;
        if (timer !== -1) { clearTimeout(timer); }
        this.closedCallbacks = this.closedCallbacks.filter(
          (callback: () => void): boolean => callback !== complete
        );
        resolve();
      };
      this.closedCallbacks = [...this.closedCallbacks, complete];
      timer = setTimeout((): void => {
        if (finished) { return; }
        finished = true;
        this.closedCallbacks = this.closedCallbacks.filter(
          (callback: () => void): boolean => callback !== complete
        );
        reject(new Error(str('auth_logout_timeout')));
      }, 15000);
    });
  }

  async resendCode(): Promise<void> {
    const request: TdRequest = { '@type': 'resendAuthenticationCode' };
    await this.client.send(request);
  }

  getPhoneNumber(): string {
    return this.authenticationPhoneNumber;
  }

  getCodeLength(): number {
    return this.authenticationCodeLength;
  }

  getCodeType(): string {
    return this.authenticationCodeType;
  }

  getCodeDestination(): string {
    return this.authenticationCodeDestination;
  }

  getNextCodeType(): string {
    return this.nextAuthenticationCodeType;
  }

  getTermsOfServiceText(): string {
    return this.termsOfServiceText;
  }

  getTermsMinUserAge(): number {
    return this.termsMinUserAge;
  }

  // 号码尚未注册时 TDLib 会停在 authorizationStateWaitRegistration，必须
  // 提交姓名才能继续。first_name 必填，last_name 可空。
  async registerUser(firstName: string, lastName: string): Promise<void> {
    const request: TdRequest = { '@type': 'registerUser' };
    request['first_name'] = firstName;
    request['last_name'] = lastName;
    request['disable_notification'] = false;
    await this.client.send(request);
  }

  getCodeTimeout(): number {
    return this.authenticationCodeTimeout;
  }

  // next_type 为空表示这次登录**没有**下一种可用通道，重发一定会被服务端
  // 拒为 "Code can't be resent"。按钮该直接禁用，而不是让用户点出个报错。
  canResendCode(): boolean {
    return this.nextAuthenticationCodeType !== '';
  }

  closeDatabase(): Promise<void> {
    if (this.currentAuthType === 'authorizationStateClosed') {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      let finished: boolean = false;
      let timer: number = -1;
      const complete = (): void => {
        if (finished) { return; }
        finished = true;
        if (timer !== -1) { clearTimeout(timer); }
        this.closedCallbacks = this.closedCallbacks.filter(
          (callback: () => void): boolean => callback !== complete
        );
        resolve();
      };
      this.closedCallbacks = [...this.closedCallbacks, complete];
      timer = setTimeout((): void => {
        logW('AuthService.closeDatabase timed out; recreating TDLib client');
        complete();
      }, 5000);
      const request: TdRequest = { '@type': 'close' };
      this.client.send(request, 5000).catch((caught: Error): void => {
        logE(`AuthService.closeDatabase failed: ${caught.message}`);
        complete();
      });
    });
  }

  dispose(): void {
    if (this.offAuthorizationState !== null) {
      this.offAuthorizationState();
      this.offAuthorizationState = null;
    }
    this.callbacks = [];
    this.qrLinkCallbacks = [];
    const closed = this.closedCallbacks;
    this.closedCallbacks = [];
    for (const callback of closed) { callback(); }
  }

  private onAuthState(update: TdObject): void {
    const state = update['authorization_state'] as TdObject;
    const type = state['@type'] as string;
    this.currentAuthType = type;
    hilog.info(0x0000, 'TDLib', '[TDLib] auth state -> %{public}s', type);
    if (type === 'authorizationStateWaitTdlibParameters') {
      this.sendTdlibParameters();
      return;
    }
    if (type === QR_CONFIRMATION_STATE && !this.phoneLoginPreferred) {
      // token 会被服务端周期性刷新，每次刷新都是一条新的同类型更新。
      this.setQrLoginLink((state['link'] as string | undefined) ?? '');
    } else if (this.qrLoginLink !== '') {
      this.setQrLoginLink('');
    }
    if (type === 'authorizationStateWaitPhoneNumber') {
      // 服务端确实回到了手机号阶段，此前的「改用手机号」偏好已无意义。
      this.phoneLoginPreferred = false;
    }
    if (type === 'authorizationStateWaitCode') {
      const codeInfo = state['code_info'] as TdObject | undefined;
      this.authenticationPhoneNumber =
        (codeInfo?.['phone_number'] as string | undefined) ?? '';
      const codeType = codeInfo?.['type'] as TdObject | undefined;
      this.authenticationCodeType =
        (codeType?.['@type'] as string | undefined) ?? '';
      this.authenticationCodeDestination =
        (codeType?.['email_address_pattern'] as string | undefined) ??
        (codeType?.['phone_number_prefix'] as string | undefined) ??
        (codeType?.['url'] as string | undefined) ?? '';
      const nextCodeType = codeInfo?.['next_type'] as TdObject | undefined;
      this.nextAuthenticationCodeType =
        (nextCodeType?.['@type'] as string | undefined) ?? '';
      this.authenticationCodeTimeout =
        Math.max(0, (codeInfo?.['timeout'] as number | undefined) ?? 0);
      const length = (codeType?.['length'] as number | undefined) ?? 5;
      this.authenticationCodeLength = Math.max(4, Math.min(8, length));
      hilog.info(
        0x0000,
        'TDLib',
        '[TDLib] authentication code delivery -> %{public}s, next -> %{public}s, timeout -> %{public}d',
        this.authenticationCodeType,
        this.nextAuthenticationCodeType,
        this.authenticationCodeTimeout
      );
    }
    if (type === 'authorizationStateWaitRegistration') {
      const terms = state['terms_of_service'] as TdObject | undefined;
      const formatted = terms !== undefined
        ? (terms['text'] as TdObject | undefined) : undefined;
      this.termsOfServiceText = (formatted?.['text'] as string | undefined) ?? '';
      this.termsMinUserAge = Math.max(0,
        (terms?.['min_user_age'] as number | undefined) ?? 0);
      hilog.info(
        0x0000,
        'TDLib',
        '[TDLib] registration required, terms length -> %{public}d, min age -> %{public}d',
        this.termsOfServiceText.length,
        this.termsMinUserAge
      );
    }
    const mapped = STATE_TO_STAGE.get(type);
    if (mapped !== undefined) {
      const stage: AuthStage =
        mapped === AuthStage.WaitQrCode && this.phoneLoginPreferred ? AuthStage.WaitPhone : mapped;
      this.emitStage(stage);
    }
    if (type === 'authorizationStateClosed') {
      const closed = this.closedCallbacks;
      this.closedCallbacks = [];
      for (const callback of closed) { callback(); }
    }
  }

  private emitStage(stage: AuthStage): void {
    this.currentStage = stage;
    for (const cb of this.callbacks) {
      cb(stage);
    }
  }

  private setQrLoginLink(link: string): void {
    if (this.qrLoginLink === link) {
      return;
    }
    this.qrLoginLink = link;
    for (const cb of this.qrLinkCallbacks) {
      cb(link);
    }
  }

  private sendTdlibParameters(): void {
    const request: TdRequest = { '@type': 'setTdlibParameters' };
    request['use_test_dc'] = USE_TEST_DC;
    request['database_directory'] = this.databaseDirectory;
    request['files_directory'] = this.filesDirectory;
    request['use_message_database'] = true;
    request['use_secret_chats'] = false;
    request['api_id'] = clientRev;
    request['api_hash'] = clientSig;
    request['system_language_code'] = 'zh-Hans';
    request['device_model'] = 'HarmonyOS Device';
    // 会显示在 Telegram 的"活跃会话"列表里，跟 AppScope/app.json5 的
    // versionName 保持一致（发版时一起改）。之前一直停在 0.1.0。
    request['application_version'] = '1.3.1';
    this.client.send(request).catch((e: Error) => {
      logE(`setTdlibParameters failed: ${e.message}`);
    });
  }
}
