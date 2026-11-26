import {
  KEY_WEB_PROXY_CONFIG as CFG_KEY, KEY_WEB_PROXY_ENABLED as ENABLED_KEY,
  KEY_WEB_PROXY_SECRET_BLOB as SECRET_BLOB_KEY, KEY_WEB_PROXY_SECRET_PLAIN as SECRET_PLAIN_KEY,
  setBoolean, setNumber, setString, settingsReady
} from '../store/AppSettings';
import { addProxy, listProxies, PROXY_MTPROTO, ProxyEntry, removeProxy } from '../store/ProxyApi';
import { logE, logI, logW } from '../util/log';
import {
  normalizeWebProxyHost, WebProxyConfig, WebProxyHostListener, webProxyConfigProblem, webProxyHost,
  webProxySecretBytes
} from './WebProxyHost';
import { webProxyTransport } from './WebProxyTransport';
import { sealWebProxySecret } from './WebProxySecretVault';

// WEB 代理的编排层：把「用户填的域名 + secret」变成「TDLib 正在用的代理」。
//
// 为什么最终落到 TDLib 的 **MTProto** 代理上（不是加一个假类型）：
//   官方 App 里 tgnet 自己就是 tproxy 客户端；本仓编进包里的 TDLib 1.8.65 还没有
//   proxyTypeWeb。所以侧车在本机 127.0.0.1 起一个「假 MTProxy」，让 tgnet 用
//   proxyTypeMtproto 连过来——obfuscated2 与 AES 由 tgnet 自己做完，侧车只搬
//   变换后的字节，再经 WebView 送到用户的 tproxy-server。与官方 ANDROID.md 同构。

// 键名的唯一来源在 store/AppSettings（那边负责启动时恢复），这里只是转发，
// 免得两处字面量漂移。
export const KEY_WEB_PROXY_CONFIG: string = CFG_KEY;
export const KEY_WEB_PROXY_ENABLED: string = ENABLED_KEY;
export const KEY_WEB_PROXY_TD_ID: string = 'webProxyTdProxyId';
// 侧车只绑回环地址：外部进程连不进来，TDLib 也只会在本机连。
export const WEB_PROXY_LOOPBACK: string = '127.0.0.1';

// preferences 里的配置形状：secret 为空串，真正的凭据在 HUKS 密文里
// （启动时由 AppSettings.restoreWebProxySecret 解到内存键）。旧版本是明文，迁移后即清空。
interface StoredWebProxyConfig {
  host: string;
  path: string;
  secret: string;
  allowInvalidCert: boolean;
}

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
      const storedSecret: string = parsed.secret ?? '';
      // 落盘的那份 secret 永远是空串，真正的值在内存键里。旧版明文配置
      // （迁移尚未发生/封不起来）仍然从这里读得到，所以两种形态都兼容。
      const secret: string = storedSecret.length > 0
        ? storedSecret
        : (AppStorage.get<string>(SECRET_PLAIN_KEY) ?? '');
      return {
        host: parsed.host ?? '', path: parsed.path ?? '', secret: secret,
        allowInvalidCert: parsed.allowInvalidCert === true
      };
    } catch (err) {
      logW('[WebProxy] saved config is not json');
      return null;
    }
  }

  // 登录就绪时调用：上次是启用状态就按保存的配置重建侧车与载体。
  //
  // 必须等 initSettings 把持久化值灌进 AppStorage 再判断：冷启动时 TDLib 的
  // Ready 常常先到，此时 isEnabled() 还是默认 false，会误判成「用户关掉了」，
  // 于是清掉侧车条目、整个客户端连不上。
  bootstrap(): void {
    this.bootstrapWhenReady().catch((err: Error): void => {
      logE('[WebProxy] bootstrap failed: ' + err.message);
    });
  }

  private async bootstrapWhenReady(): Promise<void> {
    await settingsReady();
    if (!this.isEnabled()) {
      // WEB 代理没开：顺手清掉上次留下的「假 MTProto」条目（127.0.0.1:侧车端口）。
      // 不清的话 TDLib 会一直对着一个没人听的本地端口重连，界面永远「连接中…」，
      // 用户以为整个客户端没网——这正是删掉 WEB 记录之后发生的事。
      this.purgeStaleSidecars().catch((err: Error): void => {
        logW('[WebProxy] purge stale sidecars failed: ' + err.message);
      });
      return;
    }
    const cfg: WebProxyConfig | null = this.savedConfig();
    if (cfg === null) {
      return;
    }
    if (cfg.secret.length === 0) {
      // 密文在、但解不开（换机/清数据/HUKS 密钥被回收）或密文损坏：继续当「已启用」
      // 只会让界面显示连上了、实际永远握不上手。清掉启用标记与残留侧车条目，回直连，
      // 用户到代理页重新填一次 secret 即可恢复。
      logE('[WebProxy] saved secret is unavailable, turning web proxy off');
      setBoolean(ENABLED_KEY, false);
      await this.purgeStaleSidecars();
      return;
    }
    await this.enable(cfg, true);
  }

  // 侧车端口池 127.0.0.1:47810-47879 里属于我们自己的残留代理条目。
  private async purgeStaleSidecars(): Promise<void> {
    try {
      const entries: ProxyEntry[] = await listProxies();
      for (const entry of entries) {
        if (entry.type === PROXY_MTPROTO && entry.server === WEB_PROXY_LOOPBACK
          && entry.port >= 47810 && entry.port <= 47879) {
          await removeProxy(entry.id);
          logI('[WebProxy] removed stale sidecar proxy ' + entry.server + ':' + entry.port);
        }
      }
    } catch (err) {
      logW('[WebProxy] list proxies for purge failed: ' + (err as Error).message);
    }
  }

  // 运行时销毁 / 账号切换：停掉但不改「用户想启用」的持久化状态。
  suspend(): void {
    // 先放载体与端口，再摘 TDLib 条目：摘除要走 TDLib RPC，TDLib 正忙时可能长时间
    // 不返回，不能让它拖住本地资源释放（同 disable() 的教训）。
    webProxyHost.stop();
    webProxyTransport.stop().catch((err: Error): void => {
      logW('[WebProxy] sidecar stop failed: ' + err.message);
    });
    this.detachTdProxyBounded(3000).catch((err: Error): void => {
      logW('[WebProxy] detach on suspend failed: ' + err.message);
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
      await this.detachTdProxyBounded(3000);
      this.active = normalized;
      // 侧车用同一份 secret 校验本机 tgnet 的 obfuscated2 头：只有知道 secret 的
      // 进程（也就是我们自己配给 TDLib 的那条）能连进来，同机其它 App 会被挡掉。
      webProxyTransport.configureSecret(webProxySecretBytes(normalized.secret));
      webProxyHost.setListener(this);
      webProxyHost.configure(normalized);
      webProxyTransport.attachSink(webProxyHost);
      const port: number = await webProxyTransport.start();
      logI('[WebProxy] sidecar up on ' + WEB_PROXY_LOOPBACK + ':' + port
        + ' host=' + normalized.host);
      if (!restoring) {
        // secret 不落 preferences：先封成 HUKS 密文，配置 JSON 里只留 host/path。
        // 封不起来时退回旧行为（明文写配置）——宁可这次不安全，也不要让用户
        // 重启一次就丢凭据、连不上。
        const sealed: string = await sealWebProxySecret(normalized.secret);
        const stored: StoredWebProxyConfig = {
          host: normalized.host, path: normalized.path, secret: '', allowInvalidCert: normalized.allowInvalidCert
        };
        if (sealed.length > 0) {
          AppStorage.setOrCreate(SECRET_PLAIN_KEY, normalized.secret);
          setString(SECRET_BLOB_KEY, sealed);
        } else {
          logE('[WebProxy] keystore unavailable, storing web proxy secret as plaintext');
          stored.secret = normalized.secret;
        }
        setString(KEY_WEB_PROXY_CONFIG, JSON.stringify(stored));
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
    // 顺序很关键：先停载体页与侧车端口（本地资源立刻释放），再摘 TDLib 里那条
    // MTProto 条目。反过来的话，TDLib 的 removeProxy 一旦迟迟不返回（真机实测
    // 会出现：开关已显示关闭，页面与 47810-47879 的监听却继续跑几十秒），
    // host.stop()/transport.stop() 就永远不会执行，等于「关不掉」。
    webProxyHost.stop();
    try {
      await webProxyTransport.stop();
    } catch (err) {
      logW('[WebProxy] sidecar stop failed: ' + (err as Error).message);
    }
    await this.detachTdProxyBounded(3000);
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
    // 会话没了，TDLib 那条 127.0.0.1 代理就成了死端口：继续留着会让 tgnet
    // 一直对着不再有数据的本地连接重试，界面永远停在「连接中…」，直连也回不去。
    // 这里主动摘掉，让 Telegram 至少能走直连（或用户自己配的其它代理）。
    this.detachTdProxy().catch((err: Error): void => {
      logW('[WebProxy] detach after session failure failed: ' + err.message);
    });
  }

  private async attachTdProxy(port: number): Promise<void> {
    const cfg: WebProxyConfig | null = this.active;
    if (cfg === null || port <= 0) {
      return;
    }
    if (this.tdProxyId > 0 && this.attachedPort === port) {
      return;
    }
    await this.detachTdProxyBounded(3000);
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

  // 摘除 TDLib 代理条目，但最多等 limitMs：TDLib 正忙时 removeProxy 的 promise
  // 可能长时间不 settle（send() 的 20000ms 超时不总是生效），调用方不能因此
  // 卡住本地资源释放。超时后 RPC 仍在后台继续，晚到的结果照样会摘掉条目。
  private async detachTdProxyBounded(limitMs: number): Promise<void> {
    let timedOut: boolean = false;
    const task: Promise<void> = this.detachTdProxy();
    task.catch((err: Error): void => {
      logW('[WebProxy] detach tdlib proxy failed: ' + err.message);
    });
    const guard: Promise<void> = new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        timedOut = true;
        resolve();
      }, limitMs);
    });
    await Promise.race([task, guard]);
    if (timedOut) {
      logW('[WebProxy] tdlib proxy detach still pending after ' + limitMs + 'ms, continuing');
    }
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
