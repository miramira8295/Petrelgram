import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import { InlineBtn, parseInlineKeyboard } from '../main/ets/store/MessageEntry';
import { inlineButtonKey, inlineButtonRowKey } from '../main/ets/util/inlineButtonKey';
import { MiniAppLaunch, MiniAppSession, miniAppOrigin, miniAppRequest, miniAppResult } from '../main/ets/util/miniAppModel';
import { MiniAppBridge, miniAppBridgePermission, miniAppButton, miniAppReceiveScript,
  parseMiniAppEvent } from '../main/ets/util/miniAppBridge';

function launch(kind: string = 'web'): MiniAppLaunch {
  return { kind, chatId: 7, botUserId: 7, title: 'Test', url: 'https://app.example/open',
    shortName: 'shop', startParameter: 'gift_123' };
}

function info(id: string, url: string = 'https://app.example/#tgWebAppData=signed'): TdObject {
  const nested: TdObject = { 'url': url, 'require_same_origin': true };
  return { '@type': 'webAppInfo', 'launch_id': id, 'url': nested };
}

class PendingMiniApp {
  resolve: (value: TdObject) => void = (_value: TdObject): void => {};
  promise: Promise<TdObject> = new Promise<TdObject>((resolve): void => { this.resolve = resolve; });
}

export default function miniAppTest() {
  describe('MiniApp', () => {
    it('消息WebApp保留专用动作，普通链接和回调不变', 0, () => {
      const markup = JSON.parse('{"@type":"replyMarkupInlineKeyboard","rows":[[' +
        '{"text":"Open","type":{"@type":"inlineKeyboardButtonTypeWebApp","url":"https://app.example"}},' +
        '{"text":"Site","type":{"@type":"inlineKeyboardButtonTypeUrl","url":"https://site.example"}},' +
        '{"text":"Next","type":{"@type":"inlineKeyboardButtonTypeCallback","data":"YQ=="}}]]}') as TdObject;
      const row = parseInlineKeyboard(markup)[0];
      expect(row[0].webAppUrl).assertEqual('https://app.example');
      expect(row[0].url).assertEqual('');
      expect(row[0].callbackData).assertEqual('');
      expect(row[1].url).assertEqual('https://site.example');
      expect(row[1].webAppUrl).assertEqual('');
      expect(row[2].callbackData).assertEqual('YQ==');
    });

    it('WebApp地址兼容对象形状，未知动作不会误作链接', 0, () => {
      const markup = JSON.parse('{"@type":"replyMarkupInlineKeyboard","rows":[[' +
        '{"text":"App","type":{"@type":"inlineKeyboardButtonTypeWebApp","url":{"url":"https://app.example"}}},' +
        '{"text":"Other","type":{"@type":"futureType","url":"https://other.example"}}]]}') as TdObject;
      const row = parseInlineKeyboard(markup)[0];
      expect(row[0].webAppUrl).assertEqual('https://app.example');
      expect(row[1].webAppUrl).assertEqual('');
      expect(row[1].url).assertEqual('');
    });

    it('同名WebApp换地址会更新内外层按钮键', 0, () => {
      const first: InlineBtn = { text: 'Open', url: '', webAppUrl: 'https://a.example', callbackData: '', isGame: false, style: '' };
      const second: InlineBtn = { text: 'Open', url: '', webAppUrl: 'https://b.example', callbackData: '', isGame: false, style: '' };
      expect(inlineButtonKey(0, 0, first) === inlineButtonKey(0, 0, second)).assertFalse();
      expect(inlineButtonRowKey(0, [first]) === inlineButtonRowKey(0, [second])).assertFalse();
    });

    it('消息入口请求openWebApp并携带主题', 0, () => {
      const request = miniAppRequest(launch(), true);
      expect(request['@type']).assertEqual('openWebApp');
      expect(request['chat_id']).assertEqual(7);
      expect(request['bot_user_id']).assertEqual(7);
      expect(request['url']).assertEqual('https://app.example/open');
      const parameters = request['parameters'] as TdObject;
      expect(parameters['application_name']).assertEqual('Petrelgram');
      expect((parameters['theme'] as TdObject)['background_color']).assertEqual(0x18222d);
    });

    it('主应用保留start参数', 0, () => {
      const request = miniAppRequest(launch('main'), false);
      expect(request['@type']).assertEqual('getMainWebApp');
      expect(request['start_parameter']).assertEqual('gift_123');
    });

    it('具名应用不隐式授予发送消息权限', 0, () => {
      const request = miniAppRequest(launch('link'), false);
      expect(request['@type']).assertEqual('getWebAppLinkUrl');
      expect(request['web_app_short_name']).assertEqual('shop');
      expect(request['allow_write_access']).assertFalse();
    });

    it('启动结果兼容新旧URL结构且不改签名数据', 0, () => {
      expect(miniAppResult(info('9007199254740993')).launchId).assertEqual('9007199254740993');
      expect(miniAppResult(info('1')).url).assertEqual('https://app.example/#tgWebAppData=signed');
      const old: TdObject = { 'url': 'https://app.example/old' };
      expect(miniAppResult(old).url).assertEqual('https://app.example/old');
    });

    it('HTTPS源规范化并保留非默认端口', 0, () => {
      expect(miniAppOrigin('https://APP.example:443/path?q=1#data')).assertEqual('https://app.example');
      expect(miniAppOrigin('https://app.example:8443/path')).assertEqual('https://app.example:8443');
      expect(miniAppOrigin('https://[::1]:8443/path')).assertEqual('https://[::1]:8443');
    });

    it('桥接拒绝不安全或混淆来源', 0, () => {
      for (const url of ['http://app.example', 'javascript:alert(1)', 'file:///etc/passwd',
        'https://app.example@evil.example/', 'https://app.example\\@evil.example/',
        'https://app.example:0', 'https://app.example:65536', ' https://app.example', 'https://app.example\n']) {
        expect(miniAppOrigin(url)).assertEqual('');
      }
    });

    it('桥接权限只允许启动源的HTTPS和端口', 0, () => {
      const root = JSON.parse(miniAppBridgePermission('https://app.example:8443/private#secret')) as TdObject;
      const permission = root['javascriptProxyPermission'] as TdObject;
      const rule = (permission['urlPermissionList'] as TdObject[])[0];
      expect(rule['host']).assertEqual('app.example');
      expect(rule['port']).assertEqual('8443');
      expect(rule['scheme']).assertEqual('https');
      expect(miniAppBridgePermission('https://app.example/#secret').includes('secret')).assertFalse();
    });

    it('关闭后才返回的启动也会释放且不展示', 0, async (): Promise<void> => {
      const pending = new PendingMiniApp();
      const closed: string[] = [];
      const session = new MiniAppSession((_r: TdRequest) => pending.promise, (id: string): void => { closed.push(id); });
      const opening = session.open(launch(), false);
      session.close();
      pending.resolve(info('123'));
      expect(await opening).assertNull();
      expect(closed.join(',')).assertEqual('123');
    });

    it('反复关闭只释放一次当前会话', 0, async (): Promise<void> => {
      const closed: string[] = [];
      const session = new MiniAppSession((_r: TdRequest) => Promise.resolve(info('123')),
        (id: string): void => { closed.push(id); });
      await session.open(launch(), false);
      session.close(); session.close();
      expect(closed.join(',')).assertEqual('123');
    });

    it('新启动不被旧响应覆盖', 0, async (): Promise<void> => {
      const old = new PendingMiniApp();
      const next = new PendingMiniApp();
      let calls = 0;
      const closed: string[] = [];
      const session = new MiniAppSession((_r: TdRequest) => ++calls === 1 ? old.promise : next.promise,
        (id: string): void => { closed.push(id); });
      const first = session.open(launch(), false);
      const second = session.open(launch(), false);
      next.resolve(info('2'));
      expect((await second)?.launchId).assertEqual('2');
      old.resolve(info('1'));
      expect(await first).assertNull();
      session.close();
      expect(closed.join(',')).assertEqual('1,2');
    });

    it('非法响应地址也会回收已创建会话', 0, async (): Promise<void> => {
      const closed: string[] = [];
      const session = new MiniAppSession((_r: TdRequest) => Promise.resolve(info('3', 'javascript:alert(1)')),
        (id: string): void => { closed.push(id); });
      let rejected = false;
      try { await session.open(launch(), false); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
      expect(closed.join(',')).assertEqual('3');
    });

    it('无launchId的主应用不发送closeWebApp', 0, async (): Promise<void> => {
      const closed: string[] = [];
      const session = new MiniAppSession((_r: TdRequest) => Promise.resolve(info('')),
        (id: string): void => { closed.push(id); });
      await session.open(launch('main'), false); session.close();
      expect(closed.length).assertEqual(0);
    });

    it('桥接容忍空数据并拒绝错误JSON与超长数据', 0, () => {
      expect(parseMiniAppEvent('web_app_ready', '')?.name).assertEqual('web_app_ready');
      expect(parseMiniAppEvent('web_app_ready', '""')?.name).assertEqual('web_app_ready');
      expect(parseMiniAppEvent('web_app_ready', 'null')?.name).assertEqual('web_app_ready');
      expect(parseMiniAppEvent('web_app_ready', '{')).assertNull();
      expect(parseMiniAppEvent('web_app_ready', '[]')).assertNull();
      expect(parseMiniAppEvent('web_app_ready', '"text"')).assertNull();
      expect(parseMiniAppEvent('other', '{}')).assertNull();
      expect(parseMiniAppEvent('web_app_ready', ' '.repeat(32769))).assertNull();
    });

    it('销毁桥接后不再调用页面', 0, () => {
      let received = 0;
      const bridge = new MiniAppBridge((): void => { received++; });
      bridge.postEvent('web_app_ready', '{}'); bridge.dispose(); bridge.postEvent('web_app_close', '{}');
      expect(received).assertEqual(1);
    });

    it('网页不能用错误布尔值显示按钮或注入颜色', 0, () => {
      const hidden = miniAppButton({ 'text': 'Pay', 'is_visible': 'true', 'color': 'url(evil)' });
      expect(hidden.visible).assertFalse();
      expect(hidden.color).assertEqual('#3390ec');
      const button = miniAppButton({ 'text': ' Continue ', 'is_visible': true, 'is_active': false });
      expect(button.text).assertEqual('Continue');
      expect(button.visible).assertTrue();
      expect(button.active).assertFalse();
      expect(miniAppButton({ 'text': ' ', 'is_visible': true }).visible).assertFalse();
    });

    it('回传事件安全编码引号和换行', 0, () => {
      const script = miniAppReceiveScript('popup_closed', { 'button_id': '\");evil();//\n' });
      expect(script.includes('\\"')).assertTrue();
      expect(script.includes('\\n')).assertTrue();
      expect(script.includes('receiveEvent("popup_closed",')).assertTrue();
    });
  });
}
