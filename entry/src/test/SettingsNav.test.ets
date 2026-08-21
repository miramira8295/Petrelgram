import { describe, it, expect } from '@ohos/hypium';
import { settingFrameKey } from '../main/ets/util/settingsNav';

// tg://proxy 深链交给 navigateToSetting 的那组参数的形状。
function proxyParam(server: string, port: number): Object {
  const out: Record<string, Object> = {
    'proxyServer': server,
    'proxyPort': port,
    'proxyType': 'proxyTypeSocks5'
  };
  return out;
}

export default function settingsNavTest(): void {
  describe('settingsNav', (): void => {

    it('无参数的设置子页键恒为空串（单例语义）', 0, (): void => {
      expect(settingFrameKey('PowerUsagePage', undefined)).assertEqual('');
      expect(settingFrameKey('ProxyPage', undefined)).assertEqual('');
    });

    it('带代理参数时按「服务器:端口」区分实例', 0, (): void => {
      expect(settingFrameKey('ProxyPage', proxyParam('1.2.3.4', 443)))
        .assertEqual('1.2.3.4:443');
    });

    it('同一条代理链接两次 → 键相同（decidePush 会判 skip）', 0, (): void => {
      const first: string = settingFrameKey('ProxyPage', proxyParam('a.example', 8080));
      const second: string = settingFrameKey('ProxyPage', proxyParam('a.example', 8080));
      expect(first).assertEqual(second);
    });

    it('另一条代理链接 → 键不同（会 clearAndPush 重建页面吃新参数）', 0, (): void => {
      const first: string = settingFrameKey('ProxyPage', proxyParam('a.example', 8080));
      const second: string = settingFrameKey('ProxyPage', proxyParam('b.example', 8080));
      expect(first === second).assertFalse();
    });

    it('从设置列表进（无参数）和深链进（有参数）不是同一层', 0, (): void => {
      const fromList: string = settingFrameKey('ProxyPage', undefined);
      const fromLink: string = settingFrameKey('ProxyPage', proxyParam('a.example', 8080));
      expect(fromList === fromLink).assertFalse();
    });

    it('参数不成形时退回单例语义，不拿随机键把去重打散', 0, (): void => {
      expect(settingFrameKey('ProxyPage', proxyParam('', 443))).assertEqual('');
      expect(settingFrameKey('ProxyPage', proxyParam('1.2.3.4', 0))).assertEqual('');
      const alien: Record<string, Object> = { 'somethingElse': 1 };
      expect(settingFrameKey('SomeFuturePage', alien)).assertEqual('');
    });
  });
}
