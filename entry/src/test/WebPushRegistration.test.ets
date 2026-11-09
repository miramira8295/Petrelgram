import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  buildDeregisterRequest, buildRegisterRequest, endpointHost, parseReceiverId,
  parseSubscriptionJson,
  validateWebPushConfig, forgetWebPushConfig, resolvePushChannel, startupPushConfig, WebPushConfig,
  WEBPUSH_CHANNEL_HMS
} from '../main/ets/services/WebPushRegistration';
import { WEBPUSH_MODE_HMS } from '../main/ets/services/HmsRelayRegistration';
import {
  KEY_WEBPUSH_AUTH, KEY_WEBPUSH_ENABLED, KEY_WEBPUSH_ENDPOINT, KEY_WEBPUSH_P256DH, WEBPUSH_MODE_CUSTOM, WEBPUSH_MODE_MEOW
} from '../main/ets/store/AppSettings';

const GOOD_ENDPOINT: string = 'https://push.example.com/webpush/abc123';
const GOOD_KEY: string = 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkQ';
const GOOD_AUTH: string = 'tBHItJI5svbpez7KI4CC';

export default function webPushRegistrationTest() {
  describe('WebPushRegistration', () => {
    it('accepts_a_well_formed_subscription', 0, () => {
      const v = validateWebPushConfig(
        { endpoint: GOOD_ENDPOINT, p256dh: GOOD_KEY, auth: GOOD_AUTH });
      expect(v.valid).assertTrue();
      expect(v.error).assertEqual('');
    });

    // 实测 Telegram 不向 http 地址投递，客户端提前拦下，避免用户在一个
    // 静默失效的配置上耗时间。
    it('rejects_http_endpoint', 0, () => {
      expect(validateWebPushConfig(
        { endpoint: 'http://push.example.com/x', p256dh: GOOD_KEY, auth: GOOD_AUTH }).valid)
        .assertFalse();
      expect(validateWebPushConfig(
        { endpoint: 'push.example.com/x', p256dh: GOOD_KEY, auth: GOOD_AUTH }).valid).assertFalse();
    });

    // 同样实测收不到：IP 形式的 endpoint。
    it('rejects_ip_literal_host', 0, () => {
      expect(validateWebPushConfig(
        { endpoint: 'https://203.0.113.10:8787/webpush/x', p256dh: GOOD_KEY, auth: GOOD_AUTH })
        .valid).assertFalse();
      expect(validateWebPushConfig(
        { endpoint: 'https://[2001:db8::1]/webpush/x', p256dh: GOOD_KEY, auth: GOOD_AUTH })
        .valid).assertFalse();
    });

    // 带端口的域名仍然放行 —— 没有证据表明端口本身有问题。
    it('accepts_domain_with_port', 0, () => {
      expect(validateWebPushConfig(
        { endpoint: 'https://push.example.com:8787/webpush/x', p256dh: GOOD_KEY, auth: GOOD_AUTH })
        .valid).assertTrue();
    });

    it('extracts_host_without_port_or_path', 0, () => {
      expect(endpointHost('https://push.example.com:8787/webpush/x')).assertEqual('push.example.com');
      expect(endpointHost('https://push.example.com')).assertEqual('push.example.com');
      expect(endpointHost('https://[2001:db8::1]:443/x')).assertEqual('2001:db8::1');
    });

    // TDLib 自己就会拒（DeviceTokenManager.cpp:197），提前拦下给中文提示。
    it('rejects_endpoint_containing_comma', 0, () => {
      const v = validateWebPushConfig(
        { endpoint: 'https://a.example.com/x,y', p256dh: GOOD_KEY, auth: GOOD_AUTH });
      expect(v.valid).assertFalse();
    });

    // base64url 不含 '+' '/' '='，标准 base64 直接粘进来是最常见的错法。
    it('rejects_standard_base64_keys', 0, () => {
      const plus = validateWebPushConfig(
        { endpoint: GOOD_ENDPOINT, p256dh: 'abc+def', auth: GOOD_AUTH });
      expect(plus.valid).assertFalse();
      const padded = validateWebPushConfig(
        { endpoint: GOOD_ENDPOINT, p256dh: GOOD_KEY, auth: 'abcd==' });
      expect(padded.valid).assertFalse();
    });

    it('rejects_empty_fields', 0, () => {
      expect(validateWebPushConfig({ endpoint: '', p256dh: GOOD_KEY, auth: GOOD_AUTH }).valid)
        .assertFalse();
      expect(validateWebPushConfig({ endpoint: GOOD_ENDPOINT, p256dh: '', auth: GOOD_AUTH }).valid)
        .assertFalse();
      expect(validateWebPushConfig({ endpoint: GOOD_ENDPOINT, p256dh: GOOD_KEY, auth: '' }).valid)
        .assertFalse();
    });

    it('builds_registerDevice_with_web_push_token', 0, () => {
      const req = buildRegisterRequest(
        { endpoint: ` ${GOOD_ENDPOINT} `, p256dh: GOOD_KEY, auth: GOOD_AUTH });
      expect(req['@type']).assertEqual('registerDevice');
      const token = req['device_token'] as TdObject;
      expect(token['@type']).assertEqual('deviceTokenWebPush');
      // 前后空格必须去掉，否则 endpoint 对不上服务端实际收到的地址。
      expect(token['endpoint']).assertEqual(GOOD_ENDPOINT);
      expect(token['p256dh_base64url']).assertEqual(GOOD_KEY);
      expect(token['auth_base64url']).assertEqual(GOOD_AUTH);
    });

    // 空 endpoint 就是注销，见 td_api.tl 对 deviceTokenWebPush 的说明。
    it('deregisters_with_empty_endpoint', 0, () => {
      const token = buildDeregisterRequest()['device_token'] as TdObject;
      expect(token['@type']).assertEqual('deviceTokenWebPush');
      expect(token['endpoint']).assertEqual('');
    });

    it('parses_standard_subscription_json', 0, () => {
      const r = parseSubscriptionJson(`{
        "endpoint": "${GOOD_ENDPOINT}",
        "keys": { "p256dh": "${GOOD_KEY}", "auth": "${GOOD_AUTH}" }
      }`);
      expect(r.error).assertEqual('');
      expect(r.config.endpoint).assertEqual(GOOD_ENDPOINT);
      expect(r.config.p256dh).assertEqual(GOOD_KEY);
      expect(r.config.auth).assertEqual(GOOD_AUTH);
    });

    // 手写配置的人常把三项平铺，不套 keys。
    it('parses_flat_subscription_json', 0, () => {
      const r = parseSubscriptionJson(
        `{"endpoint":"${GOOD_ENDPOINT}","p256dh":"${GOOD_KEY}","auth":"${GOOD_AUTH}"}`);
      expect(r.error).assertEqual('');
      expect(r.config.p256dh).assertEqual(GOOD_KEY);
    });

    it('reports_missing_fields_by_name', 0, () => {
      const r = parseSubscriptionJson(`{"endpoint":"${GOOD_ENDPOINT}"}`);
      expect(r.error.includes('p256dh')).assertTrue();
      expect(r.error.includes('auth')).assertTrue();
      // 已解析出来的字段仍要回填，方便用户只补缺的那项。
      expect(r.config.endpoint).assertEqual(GOOD_ENDPOINT);
    });

    it('reports_malformed_json_without_throwing', 0, () => {
      const r = parseSubscriptionJson('{ endpoint: 缺引号 }');
      expect(r.error).assertEqual('wp_bad_json');
      expect(r.config.endpoint).assertEqual('');
    });

    it('rejects_empty_input', 0, () => {
      expect(parseSubscriptionJson('   ').error.length > 0).assertTrue();
    });

    // 复制粘贴常把整段带上换行和空格，字段值本身不该带空白。
    it('trims_whitespace_around_values', 0, () => {
      const r = parseSubscriptionJson(
        `{"endpoint":"  ${GOOD_ENDPOINT}  ","keys":{"p256dh":" ${GOOD_KEY} ","auth":"${GOOD_AUTH}"}}`);
      expect(r.config.endpoint).assertEqual(GOOD_ENDPOINT);
      expect(r.config.p256dh).assertEqual(GOOD_KEY);
    });

    it('reads_receiver_id_from_result', 0, () => {
      const res: TdObject = { '@type': 'pushReceiverId' };
      res['id'] = '1234567890';
      expect(parseReceiverId(res)).assertEqual('1234567890');
      expect(parseReceiverId({ '@type': 'pushReceiverId' })).assertEqual('');
    });

    // issue #198：「注销」有意保留三项好换地址重注册，缺一个"我就是不想要了"的出口。
    // forgetWebPushConfig 把三项 + 开关一起抹掉，页面回填时才不会又冒出来。
    it('forgetWebPushConfig clears the three fields and the switch', 0, (): void => {
      AppStorage.setOrCreate(KEY_WEBPUSH_ENDPOINT, 'https://push.example/x');
      AppStorage.setOrCreate(KEY_WEBPUSH_P256DH, 'p256');
      AppStorage.setOrCreate(KEY_WEBPUSH_AUTH, 'auth');
      AppStorage.setOrCreate(KEY_WEBPUSH_ENABLED, true);
      forgetWebPushConfig();
      expect(AppStorage.get<string>(KEY_WEBPUSH_ENDPOINT)).assertEqual('');
      expect(AppStorage.get<string>(KEY_WEBPUSH_P256DH)).assertEqual('');
      expect(AppStorage.get<string>(KEY_WEBPUSH_AUTH)).assertEqual('');
      expect(AppStorage.get<boolean>(KEY_WEBPUSH_ENABLED)).assertFalse();
    });
    // 启动/切账号时拿哪一份配置去向 Telegram 重新注册（2026-09-17，issue #196/#198）。
    // 原来不看通道、只读自定义那三项：先用自托管、后换 MeoW 的人，下次启动就被悄悄
    // 改回自托管地址——界面显示 MeoW 已注册，实际不推送。
    it('startup_reregisters_the_channel_that_was_actually_registered', 0, () => {
      const custom: WebPushConfig = { endpoint: GOOD_ENDPOINT, p256dh: GOOD_KEY, auth: GOOD_AUTH };
      const meow: WebPushConfig = {
        endpoint: 'https://relay.example.com/webpush/sub9', p256dh: GOOD_KEY, auth: GOOD_AUTH
      };
      const empty: WebPushConfig = { endpoint: '', p256dh: '', auth: '' };
      expect(startupPushConfig(WEBPUSH_MODE_MEOW, custom, meow)!.endpoint).assertEqual(meow.endpoint);
      expect(startupPushConfig(WEBPUSH_MODE_CUSTOM, custom, meow)!.endpoint).assertEqual(custom.endpoint);
      // MeoW 的三项没存（老版本注册的）：宁可不动 Telegram 那边，也不能退回自托管那份
      expect(startupPushConfig(WEBPUSH_MODE_MEOW, custom, empty) === null).assertTrue();
      expect(startupPushConfig(WEBPUSH_MODE_CUSTOM, empty, meow) === null).assertTrue();
      expect(startupPushConfig(WEBPUSH_CHANNEL_HMS, custom, meow) === null).assertTrue();
      expect(startupPushConfig('', custom, meow) === null).assertTrue();
    });

    it('resolves_the_registered_channel_including_legacy_installs', 0, () => {
      expect(resolvePushChannel({ enabled: false, channel: WEBPUSH_MODE_MEOW, mode: '', meowNickname: 'cat' }))
        .assertEqual('');
      // 记下的通道优先，与页面上最后停在哪个页签无关
      expect(resolvePushChannel({
        enabled: true, channel: WEBPUSH_MODE_MEOW, mode: WEBPUSH_MODE_CUSTOM, meowNickname: ''
      })).assertEqual(WEBPUSH_MODE_MEOW);
      // 老安装没有通道键：按留下的痕迹推断
      expect(resolvePushChannel({ enabled: true, channel: '', mode: WEBPUSH_CHANNEL_HMS, meowNickname: 'cat' }))
        .assertEqual(WEBPUSH_CHANNEL_HMS);
      expect(resolvePushChannel({ enabled: true, channel: '', mode: WEBPUSH_MODE_CUSTOM, meowNickname: 'cat' }))
        .assertEqual(WEBPUSH_MODE_MEOW);
      expect(resolvePushChannel({ enabled: true, channel: '', mode: WEBPUSH_MODE_CUSTOM, meowNickname: '' }))
        .assertEqual(WEBPUSH_MODE_CUSTOM);
    });

    // 这边为了不成环抄了一份字面量，靠这条钉住。
    it('hms_channel_literal_matches_hms_module', 0, () => {
      expect(WEBPUSH_CHANNEL_HMS).assertEqual(WEBPUSH_MODE_HMS);
    });
  });
}
