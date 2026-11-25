import { setBoolean, setNumber, setString } from '../store/AppSettings';
import { addProxy, PROXY_MTPROTO, ProxyEntry, removeProxy } from '../store/ProxyApi';
import { logE, logI, logW } from '../util/log';
import {
  normalizeWebProxyHost, WebProxyConfig, WebProxyHostListener, webProxyConfigProblem, webProxyHost
} from './WebProxyHost';
import { webProxyTransport } from './WebProxyTransport';

// WEB 代理的编排层：把「用户填的域名 + secret」变成「TDLib 正在用的代理」。
//
// 为什么最终落到 TDLib 的 **MTProto** 代理上（不是加一个假类型）：
//   官方 App 里 tgnet 自己就是 tproxy 客户端；本仓编进包里的 TDLib 1.8.65 还没有
//   proxyTypeWeb。所以侧车在本机 127.0.0.1 起一个「假 MTProxy」，让 tgnet 用
//   proxyTypeMtproto 连过来——obfuscated2 与 AES 由 tgnet 自己做完，侧车只搬
//   变换后的字节，再经 WebView 送到用户的 tproxy-server。与官方 ANDROID.md 同构。

export const KEY_WEB_PROXY_CONFIG: string = 'webProxyConfig';
export const KEY_WEB_PROXY_ENABLED: string = 'webProxyEnabled';
export const KEY_WEB_PROXY_TD_ID: string = 'webProxyTdProxyId';
// 侧车只绑回环地址：外部进程连不进来，TDLib 也只会在本机连。
export const WEB_PROXY_LOOPBACK: string = '127.0.0.1';

export class WebProxyService implements WebProxyHostListener {
  private active: WebProxyConfig | null = null;
  private tdProxyId: number = 0;
  // 已经交给 TDLib 的侧车端口：重连后端口没变就不要 removeProxy + addProxy 折腾一遍。
  private attachedPort: number = 0;
  private enabling: boolean = false;

  isEnabled(): boolean {
    return AppStorage.get<boolean>(KEY_WEB_PROXY_ENABLED) ?? false;
  }

  savedConfig(): WebProxyConfig | null {
    const raw: string = AppStorage.get<string>(KEY_WEB_PROXY_CONFIG) ?? '';
    if (raw.length === 0) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw) as WebProxyConfig;
      if (parsed === null) {
        return null;
      }
      return {
        host: parsed.host ?? '', path: parsed.path ?? '', secret: parsed.secret ?? '',
        allowInvalidCert: parsed.allowInvalidCert === true
      };
    } catch (err) {
      logW('[WebProxy] saved config is not json');
      return null;
    }
  }

  // 登录就绪时调用：上次是启用状态就按保存的配置重建侧车与载体。
  bootstrap(): void {
    if (!this.isEnabled()) {
      return;
    }
    const cfg: WebProxyConfig | null = this.savedConfig();
    if (cfg === null) {
      return;
    }
    this.enable(cfg, true).catch((err: Error): void => {
      logE('[WebProxy] bootstrap failed: ' + err.message);
    });
  }

  // 运行时销毁 / 账号切换：停掉但不改「用户想启用」的持久化状态。
  suspend(): void {
    webProxyHost.stop();
    // 侧车端口即将关闭，必须把 TDLib 里那条 127.0.0.1 代理摘掉；否则下次运行时
    // tgnet 会对着一个已经不听的端口重连，表现为「明明关掉了 WEB 代理却连不上」。
    this.detachTdProxy().catch((err: Error): void => {
      logW('[WebProxy] detach on suspend failed: ' + err.message);
    });
    webProxyTransport.stop().catch((err: Error): void => {
      logW('[WebProxy] sidecar stop failed: ' + err.message);
    });
  }

  async enable(cfg: WebProxyConfig, restoring: boolean): Promise<void> {
    const problem: string = webProxyConfigProblem(cfg);
    if (problem.length > 0) {
      throw new Error(problem);
    }
    if (this.enabling) {
      return;
    }
    this.enabling = true;
    try {
      const normalized: WebProxyConfig = {
        host: normalizeWebProxyHost(cfg.host), path: cfg.path, secret: cfg.secret.trim(),
        allowInvalidCert: cfg.allowInvalidCert
      };
      await this.detachTdProxy();
      this.active = normalized;
      webProxyHost.setListener(this);
      webProxyHost.configure(normalized);
      webProxyTransport.attachSink(webProxyHost);
      const port: number = await webProxyTransport.start();
      logI('[WebProxy] sidecar up on ' + WEB_PROXY_LOOPBACK + ':' + port
        + ' host=' + normalized.host);
      if (!restoring) {
        setString(KEY_WEB_PROXY_CONFIG, JSON.stringify(normalized));
        setBoolean(KEY_WEB_PROXY_ENABLED, true);
      }
      // 载体页起不来的话，侧车端口仍然在听，但没有任何字节能出去；
      // carrierChanged('failed:...') 会按 2s→30s 退避重建，期间 TDLib 报连接错误。
      webProxyHost.begin();
    } finally {
      this.enabling = false;
    }
  }

  async disable(): Promise<void> {
    setBoolean(KEY_WEB_PROXY_ENABLED, false);
    this.active = null;
    await this.detachTdProxy();
    webProxyHost.stop();
    await webProxyTransport.stop();
    logI('[WebProxy] disabled');
  }

  // 传输层 WELCOME 之后才算真的可用：此时才把代理交给 TDLib，避免它对着
  // 一个「还没握上手」的端口发 MTProto 握手，白报一堆连接失败。
  onSessionReady(port: number): void {
    this.attachTdProxy(port).catch((err: Error): void => {
      logE('[WebProxy] attach tdlib proxy failed: ' + err.message);
    });
  }

  onSessionFailed(reason: string): void {
    logW('[WebProxy] carrier session failed: ' + reason);
  }

  private async attachTdProxy(port: number): Promise<void> {
    const cfg: WebProxyConfig | null = this.active;
    if (cfg === null || port <= 0) {
      return;
    }
    if (this.tdProxyId > 0 && this.attachedPort === port) {
      return;
    }
    await this.detachTdProxy();
    const entry: ProxyEntry = {
      id: 0,
      server: WEB_PROXY_LOOPBACK,
      port: port,
      type: PROXY_MTPROTO,
      username: '',
      password: '',
      secret: cfg.secret,
      httpOnly: false,
      lastUsedDate: 0,
      isEnabled: true
    };
    const added: ProxyEntry = await addProxy(entry, true);
    this.tdProxyId = added.id;
    this.attachedPort = port;
    setNumber(KEY_WEB_PROXY_TD_ID, added.id);
    logI('[WebProxy] tdlib now uses ' + PROXY_MTPROTO + ' ' + WEB_PROXY_LOOPBACK + ':' + port);
  }

  private async detachTdProxy(): Promise<void> {
    let id: number = this.tdProxyId;
    if (id === 0) {
      id = AppStorage.get<number>(KEY_WEB_PROXY_TD_ID) ?? 0;
    }
    this.tdProxyId = 0;
    this.attachedPort = 0;
    setNumber(KEY_WEB_PROXY_TD_ID, 0);
    if (id === 0) {
      return;
    }
    try {
      await removeProxy(id);
    } catch (err) {
      logW('[WebProxy] remove tdlib proxy failed: ' + (err as Error).message);
    }
  }
}

export const webProxyService: WebProxyService = new WebProxyService();
