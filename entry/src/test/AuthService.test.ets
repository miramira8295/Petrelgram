import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { AuthService, AuthStage } from '../main/ets/tdkit/AuthService';

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
