import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { navigateToSetting, settingFrameKey } from '../main/ets/util/settingsNav';
import { clearPendingNavs, takePendingNavs, PendingNav } from '../main/ets/util/pendingNav';
import { NavPathInfoLike, NavStackLike, registerStack, resetStacksForTest } from '../main/ets/util/navStacks';

// 设置栈的最小替身：只记名字，够 navigateToSetting 判定与落栈用。
class FakeSettingsStack implements NavStackLike {
  names: string[] = [];
  cleared: number = 0;
  clear(_animated?: boolean): void { this.cleared++; this.names = []; }
  pushPath(info: NavPathInfoLike): void { this.names.push(info.name); }
  pop(_animated?: boolean): void { this.names.pop(); }
  size(): number { return this.names.length; }
  getAllPathName(): string[] { return this.names.slice(); }
  getParamByIndex(_index: number): Object | undefined { return undefined; }
}

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
    beforeEach((): void => { resetStacksForTest(); });

    // issue #203：隐私与安全 → 活跃设备。ActiveSessionsPage 第 4 批迁成
    // NavDestination 后已不在 main_pages.json，隐私页里那行 router.pushUrl 必失败
    // （toast「页面打开失败」）。改走设置栈，且是**叠在隐私页之上**——返回要回到
    // 隐私页，不能像列表/深链那样把栈清掉。
    it('子页里再进一层（origin=content）：叠在当前页上、不清栈', 0, (): void => {
      const stack: FakeSettingsStack = new FakeSettingsStack();
      stack.names = ['PrivacySecurityPage'];
      registerStack('settings', stack);
      expect(navigateToSetting('ActiveSessionsPage', undefined, 'content')).assertTrue();
      expect(stack.cleared).assertEqual(0);
      expect(stack.names.join('>')).assertEqual('PrivacySecurityPage>ActiveSessionsPage');
    });

    it('省略 origin 仍是列表/深链语义：先清栈再推（行为不变）', 0, (): void => {
      const stack: FakeSettingsStack = new FakeSettingsStack();
      stack.names = ['PrivacySecurityPage'];
      registerStack('settings', stack);
      expect(navigateToSetting('ActiveSessionsPage')).assertTrue();
      expect(stack.cleared).assertEqual(1);
      expect(stack.names.join('>')).assertEqual('ActiveSessionsPage');
    });

    it('栈顶已是目标页时 skip，不重复入栈', 0, (): void => {
      const stack: FakeSettingsStack = new FakeSettingsStack();
      stack.names = ['PrivacySecurityPage', 'ActiveSessionsPage'];
      registerStack('settings', stack);
      expect(navigateToSetting('ActiveSessionsPage', undefined, 'content')).assertTrue();
      expect(stack.names.length).assertEqual(2);
    });

    // 2026-09-14 契约变更：栈没注册不再算失败。目标页早就不在 main_pages.json
    // 里，回退 router 必然失败（系统弹"无法识别的链接"）；现在挂起 + 切页签，
    // SettingsPage 一挂树就重放，所以返回 true 并且队列里多一条。
    it('设置栈未注册时挂起而不是失败', 0, (): void => {
      clearPendingNavs();
      expect(navigateToSetting('ActiveSessionsPage', undefined, 'content')).assertTrue();
      const queued: PendingNav[] = takePendingNavs('settings');
      expect(queued.length).assertEqual(1);
      expect(queued[0].dest).assertEqual('ActiveSessionsPage');
      expect(queued[0].origin).assertEqual('content');
    });

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
