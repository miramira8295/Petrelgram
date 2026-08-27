import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { AuthService, AuthStage } from '../main/ets/tdkit/AuthService';
import { TdDeviceParams } from '../main/ets/util/tdDeviceParams';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void;
  sent: string[];

  constructor() {
    this.sent = [];
    this.onReceive = (json: string): void => {};
  }

  init(cb: (json: string) => void): void {
    this.onReceive = cb;
  }

  send(json: string): void {
    this.sent.push(json);
  }
}

// 前 failures 次请求回 "Call to <method> unexpected"，之后放行。用来复现 TDLib
// 的时机冲突：鉴权类请求同一时刻只接受一个在途、且授权态必须正好对得上，
// 不满足时它不排队、直接拒——冷启动点扫码就是踩这个（手机模拟器实测）。
class UnexpectedThenOkBridge implements TdBridge {
  onReceive: (json: string) => void;
  sent: string[];
  private remaining: number;

  constructor(failures: number) {
    this.sent = [];
    this.remaining = failures;
    this.onReceive = (json: string): void => {};
  }

  init(cb: (json: string) => void): void {
    this.onReceive = cb;
  }

  send(json: string): void {
    this.sent.push(json);
    const req = JSON.parse(json) as TdObject;
    const extra = req['@extra'] as string;
    const method = req['@type'] as string;
    if (this.remaining > 0) {
      this.remaining--;
      this.reply({ '@type': 'error', 'code': 400, 'message': `Call to ${method} unexpected`, '@extra': extra });
      return;
    }
    this.reply({ '@type': 'ok', '@extra': extra });
  }

  private reply(obj: TdObject): void {
    this.onReceive(JSON.stringify(obj));
  }
}

// 硬错误（号码格式非法之类）——不含 "unexpected"，一次就该抛出去。
class HardErrorBridge implements TdBridge {
  onReceive: (json: string) => void;
  sent: string[];

  constructor() {
    this.sent = [];
    this.onReceive = (json: string): void => {};
  }

  init(cb: (json: string) => void): void {
    this.onReceive = cb;
  }

  send(json: string): void {
    this.sent.push(json);
    const req = JSON.parse(json) as TdObject;
    const err: TdObject = {
      '@type': 'error', 'code': 400,
      'message': 'PHONE_NUMBER_INVALID', '@extra': req['@extra'] as string
    };
    this.onReceive(JSON.stringify(err));
  }
}

function pushAuthState(bridge: FakeBridge, stateType: string): void {
  const authState: TdObject = { '@type': stateType };
  const update: TdObject = {
    '@type': 'updateAuthorizationState',
    'authorization_state': authState
  };
  bridge.onReceive(JSON.stringify(update));
}

function pushQrState(bridge: FakeBridge, link: string): void {
  const authState: TdObject = {
    '@type': 'authorizationStateWaitOtherDeviceConfirmation',
    'link': link
  };
  const update: TdObject = {
    '@type': 'updateAuthorizationState',
    'authorization_state': authState
  };
  bridge.onReceive(JSON.stringify(update));
}

function parseJson(json: string): TdObject {
  return JSON.parse(json) as TdObject;
}

function lastSent(sent: string[]): TdObject {
  return parseJson(sent[sent.length - 1]);
}

export default function authServiceTest() {
  describe('AuthService', () => {
    it('sends_parameters_on_wait_tdlib_parameters', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitTdlibParameters');
      const sent: TdObject = lastSent(bridge.sent);
      expect(sent['@type']).assertEqual('setTdlibParameters');
      expect(sent['database_directory']).assertEqual('/data/test/files/tdlib');
    });

    it('sends_device_params_in_tdlib_parameters', 0, () => {
      // issue #147：活跃会话里显示的机型/系统/应用版本来自构造时传入的读数，
      // 不再是写死的字符串。
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const params: TdDeviceParams = {
        deviceModel: 'HUAWEI Mate 70 Pro+',
        systemVersion: 'HarmonyOS 6.0.0 (API 26)',
        applicationVersion: '1.4.3'
      };
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files', params);
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitTdlibParameters');
      const sent: TdObject = lastSent(bridge.sent);
      expect(sent['device_model']).assertEqual('HUAWEI Mate 70 Pro+');
      expect(sent['system_version']).assertEqual('HarmonyOS 6.0.0 (API 26)');
      expect(sent['application_version']).assertEqual('1.4.3');
    });

    it('device_params_default_is_non_empty', 0, () => {
      // TDLib 拒绝空的 device_model / application_version，兜底也得是非空串。
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitTdlibParameters');
      const sent: TdObject = lastSent(bridge.sent);
      expect((sent['device_model'] as string).length > 0).assertTrue();
      expect((sent['system_version'] as string).length > 0).assertTrue();
      expect((sent['application_version'] as string).length > 0).assertTrue();
    });

    it('maps_states_to_stages', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      const stages: AuthStage[] = [];
      // onStageChange replays the current stage (Init) on registration.
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitPhoneNumber');
      pushAuthState(bridge, 'authorizationStateWaitCode');
      pushAuthState(bridge, 'authorizationStateWaitPassword');
      pushAuthState(bridge, 'authorizationStateReady');
      expect(stages.join(',')).assertEqual(
        [AuthStage.Init, AuthStage.WaitPhone, AuthStage.WaitCode, AuthStage.WaitPassword, AuthStage.Ready].join(','));
    });

    it('submitPhone_sends_setAuthenticationPhoneNumber', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      auth.submitPhone('+8613800138000');
      const sent: TdObject = lastSent(bridge.sent);
      expect(sent['@type']).assertEqual('setAuthenticationPhoneNumber');
      expect(sent['phone_number']).assertEqual('+8613800138000');
    });

    it('requestQrLogin_sends_requestQrCodeAuthentication', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      auth.requestQrLogin();
      const sent: TdObject = lastSent(bridge.sent);
      expect(sent['@type']).assertEqual('requestQrCodeAuthentication');
      const otherUserIds = sent['other_user_ids'] as number[];
      expect(otherUserIds.length).assertEqual(0);
    });

    // 冷启动进扫码页的回归：TDLib 还在 WaitTdlibParameters -> WaitPhoneNumber
    // 之间过渡时会拒掉 requestQrCodeAuthentication。此前这一向没有重试，用户
    // 冷启动点一次扫码就被弹回手机号页并看到原始英文错误串。
    it('requestQrLogin_retries_when_tdlib_says_unexpected', 0, async () => {
      const bridge = new UnexpectedThenOkBridge(1);
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      await auth.requestQrLogin();
      const qrSends = bridge.sent.filter((j: string): boolean =>
        (JSON.parse(j) as TdObject)['@type'] === 'requestQrCodeAuthentication');
      expect(qrSends.length).assertEqual(2); // 第一次被拒，第二次成功
    });

    it('submitPhone_retries_when_tdlib_says_unexpected', 0, async () => {
      const bridge = new UnexpectedThenOkBridge(1);
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      await auth.submitPhone('+8613800138000');
      const phoneSends = bridge.sent.filter((j: string): boolean =>
        (JSON.parse(j) as TdObject)['@type'] === 'setAuthenticationPhoneNumber');
      expect(phoneSends.length).assertEqual(2);
    });

    // 重试只针对时机冲突。真错误重试三次只是把用户多晾 4.5 秒，错误依旧。
    it('submitPhone_does_not_retry_a_real_error', 0, async () => {
      const bridge = new HardErrorBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      let message: string = '';
      try {
        await auth.submitPhone('bogus');
      } catch (e) {
        message = `${(e as Error).message}`;
      }
      expect(message).assertEqual('PHONE_NUMBER_INVALID');
      const phoneSends = bridge.sent.filter((j: string): boolean =>
        (JSON.parse(j) as TdObject)['@type'] === 'setAuthenticationPhoneNumber');
      expect(phoneSends.length).assertEqual(1);
    });

    it('qr_confirmation_state_maps_to_wait_qr_and_exposes_link', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      const links: string[] = [];
      const stages: AuthStage[] = [];
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      auth.onQrLinkChange((link: string) => { links.push(link); });
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitPhoneNumber');
      auth.requestQrLogin(); // 扫码态要"本次会话主动点过扫码"才展示（冷启动恢复默认回手机页）
      pushQrState(bridge, 'tg://login?token=first');
      pushQrState(bridge, 'tg://login?token=second');
      expect(auth.getQrLoginLink()).assertEqual('tg://login?token=second');
      // 首个回调是注册时的空链接回放。
      expect(links.join(',')).assertEqual(',tg://login?token=first,tg://login?token=second');
      expect(stages.join(',')).assertEqual([
        AuthStage.Init, AuthStage.WaitPhone, AuthStage.WaitQrCode, AuthStage.WaitQrCode
      ].join(','));
    });

    it('qr_login_continues_into_password_stage', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      const stages: AuthStage[] = [];
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      client.start();
      auth.requestQrLogin();
      pushQrState(bridge, 'tg://login?token=abc');
      pushAuthState(bridge, 'authorizationStateWaitPassword');
      pushAuthState(bridge, 'authorizationStateReady');
      expect(stages.join(',')).assertEqual([
        AuthStage.Init, AuthStage.WaitQrCode, AuthStage.WaitPassword, AuthStage.Ready
      ].join(','));
      // 离开扫码阶段后链接必须清空，避免过期二维码被重新渲染。
      expect(auth.getQrLoginLink()).assertEqual('');
    });

    it('switchToPhoneLogin_returns_to_phone_and_ignores_token_refresh', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      const stages: AuthStage[] = [];
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      client.start();
      auth.requestQrLogin();
      pushQrState(bridge, 'tg://login?token=abc');
      auth.switchToPhoneLogin();
      // token 刷新不得把用户拽回扫码页。
      pushQrState(bridge, 'tg://login?token=def');
      expect(stages.join(',')).assertEqual([
        AuthStage.Init, AuthStage.WaitQrCode, AuthStage.WaitPhone, AuthStage.WaitPhone
      ].join(','));
      expect(auth.getQrLoginLink()).assertEqual('');
    });

    it('switchToPhoneLogin_preference_resets_on_wait_phone_number', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      client.start();
      auth.requestQrLogin();
      pushQrState(bridge, 'tg://login?token=abc');
      auth.switchToPhoneLogin();
      pushAuthState(bridge, 'authorizationStateWaitPhoneNumber');
      const stages: AuthStage[] = [];
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      pushQrState(bridge, 'tg://login?token=ghi');
      expect(stages.join(',')).assertEqual(
        [AuthStage.WaitPhone, AuthStage.WaitQrCode].join(','));
    });

    // 冷启动恢复出来的扫码态（本次会话没点过扫码）默认转回手机号页，
    // 且不暴露二维码链接——登录的默认入口是手机号（用户点名的契约）。
    it('restored_qr_state_defaults_back_to_phone', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files/tdlib', '/data/test/files');
      const stages: AuthStage[] = [];
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      client.start();
      pushQrState(bridge, 'tg://login?token=restored');
      expect(stages.join(',')).assertEqual(
        [AuthStage.Init, AuthStage.WaitPhone].join(','));
      expect(auth.getQrLoginLink()).assertEqual('');
    });
  });
}
