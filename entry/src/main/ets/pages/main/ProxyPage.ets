import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import { getConnectionState, getTdClient } from '../../tdkit/Globals';
import {
  ProxyEntry, PROXY_SOCKS5, PROXY_MTPROTO, PROXY_HTTP,
  proxyTypeLabel, listProxies, addProxy, editProxy, enableProxy, disableProxy,
  removeProxy, pingProxy, testProxy, getProxyShareLink
} from '../../store/ProxyApi';
import {
  parseProxyPort, proxyActionErrorText, proxyConnectionText,
  proxyFormError, sameProxyConfiguration, enabledProxyConnected
} from '../../util/proxyLogic';
import { measureProxyConnectMs } from '../../util/proxyReach';
import {
  KEY_PROXY_MIRROR, KEY_PROXY_SYNC_OFF, missingFromAccount, parseProxyMirror, parseSyncOff,
  serializeProxyMirror, serializeSyncOff, syncEnabledFor, syncableOf, toggledSyncOff
} from '../../util/proxyMirror';
import { setString } from '../../store/AppSettings';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';

// 回落的 TCP 握手计时上限。5s 内连不上代理服务器，就按不通处理。
const REACH_TIMEOUT_MS: number = 5000;
const CARD_RADIUS: number = 14;
const TOP_ACTION_SIZE: number = 44;
const DANGER: string = '#E64646';
const OK_GREEN: string = '#34C759';
const WARNING: string = '#FF9500';
const DIRECT_PING_ID: number = 0;
const SKELETON_ROWS: number[] = [0, 1, 2];

interface TypeOption {
  label: string;
  value: string;
}

const TYPES: TypeOption[] = [
  { label: 'SOCKS5', value: PROXY_SOCKS5 },
  { label: 'MTProto', value: PROXY_MTPROTO },
  { label: 'HTTP', value: PROXY_HTTP }
];

// Proxy settings are backed only by TDLib. The UI serializes mutations and
// reconciles uncertain results, while TDLib remains the owner of networking.
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router
// 页和 NavDestination。形状与 PowerUsagePageBuilder 一致。
@Builder
export function ProxyPageBuilder(): void {
  ProxyPage();
}

@Component
export struct ProxyPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State proxies: ProxyEntry[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  @State syncWarning: string = '';
  @State connectionState: string = '';
  @State pings: Map<number, number> = new Map();
  @State pingStates: Map<number, string> = new Map(); // loading | ready | error
  @State actionKey: string = '';
  @State preferredProxyId: number = 0;
  @State skeletonBright: boolean = false;

  @State sheetOpen: boolean = false;
  @State editingId: number = 0;
  @State importedForm: boolean = false;
  @State fType: string = PROXY_SOCKS5;
  @State fServer: string = '';
  @State fPort: string = '';
  @State fUser: string = '';
  @State fPass: string = '';
  @State fSecret: string = '';
  @State fHttpOnly: boolean = false;
  @State fEnableAfterSave: boolean = true;
  @State fRevealCredential: boolean = false;
  @State formError: string = '';
  @State formTestState: string = 'idle'; // idle | loading | ready | error
  @State formTestMs: number = 0;
  @State saving: boolean = false;
  @State formOutcomeUnknown: boolean = false;

  private active: boolean = false;
  // 路由参数。router 时代是 aboutToAppear 里 router.getParams() 现取，现在由
  // 外壳（HdsSubDestination）的 onRouteParams 从 NavDestinationContext.pathInfo
  // 里交过来——**onReady 实测晚于 aboutToAppear**（平板 API 26，ChatPage 里记了
  // 同一条实测），照原位置读会拿到 undefined。
  private navParams: Record<string, Object> | undefined = undefined;
  // applyRouteParams() 的一次性守卫。页面复用时（MOVE_TO_TOP_SINGLETON /
  // onNewParam）onReady 可能触发不止一次，没有它 load(true) 会被重复发起。
  private paramsApplied: boolean = false;
  private paramsConsumed: boolean = false;
  private loadSequence: number = 0;
  private operationSequence: number = 0;
  private formSequence: number = 0;
  private pingGeneration: number = 0;
  private pingTokens: Map<number, number> = new Map();
  private skeletonTimer: number = -1;
  private unsubscribeConnection: (() => void) | null = null;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(COLOR_SURFACE)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .scale({ x: 0.99, y: 0.99 })
  }

  @Styles
  primaryNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  primaryPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.subscribeConnectionState();
    // 后面原本还有 consumeRouteParams() + load(true) 两句，整段平移进了
    // applyRouteParams()，由外壳的 onRouteParams 触发——见那个方法上的注释。
    // 留在这里的两句与路由参数无关：active 是本页自己的存活标志，
    // subscribeConnectionState() 订阅的是全局连接态。
  }

  // 路由参数就绪后的初始化。**这就是迁移前 aboutToAppear 的后半段，两句的顺序
  // 一字未改**，只是改由外壳的 onRouteParams 触发。
  //
  // 【为什么 load(true) 也一起搬过来，而不是留在 aboutToAppear】它本身不读参数，
  // 但它原本排在 consumeRouteParams() **之后**。把 consumeRouteParams() 单独往后
  // 挪就等于把这两句的先后顺序调了个个儿——代理列表的加载和"预填表单/弹出表单"
  // 之间的时序偏差，编译和单测都发现不了，只会在真机上以偶发的形式冒出来。
  // 整段平移则保证前后逐字等价。
  private applyRouteParams(): void {
    if (this.paramsApplied) { return; }
    this.paramsApplied = true;
    this.consumeRouteParams();
    this.load(true);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.operationSequence++;
    this.formSequence++;
    this.pingGeneration++;
    this.stopSkeletonPulse();
    if (this.unsubscribeConnection !== null) {
      this.unsubscribeConnection();
      this.unsubscribeConnection = null;
    }
  }

  // 迁移前是 router 页的 onBackPress()。**方法体一字未改**，只改了名字并由外壳
  // 转发——NavDestination 上对应的是 HdsNavDestination.onBackPressed()，调用页
  // 够不着那一层，所以在 build() 里作为 onBackPressed Prop 传给 HdsSubDestination。
  // 语义也一一对上：返回 true = 本页消化掉这次返回（保存中不许走 / 先关表单），
  // 返回 false = 交回默认处理（router 时代是退页，现在是出 Navigation 栈）。
  onBackPressed(): boolean {
    if (this.saving) { return true; }
    if (this.sheetOpen) {
      this.cancelForm();
      return true;
    }
    return false;
  }

  private animationDuration(fallback: number): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, fallback);
  }

  private startSkeletonPulse(): void {
    if (this.skeletonTimer !== -1 || this.animationDuration(1) === 0) { return; }
    this.skeletonTimer = setInterval((): void => {
      this.skeletonBright = !this.skeletonBright;
    }, 680);
  }

  private stopSkeletonPulse(): void {
    if (this.skeletonTimer !== -1) {
      clearInterval(this.skeletonTimer);
      this.skeletonTimer = -1;
    }
    this.skeletonBright = false;
  }

  private subscribeConnectionState(): void {
    if (this.unsubscribeConnection === null) {
      this.unsubscribeConnection = getTdClient().onUpdate(
        'updateConnectionState', (update: TdObject): void => {
          if (!this.active) { return; }
          const state = update['state'] as TdObject | undefined;
          this.connectionState = state !== undefined
            ? ((state['@type'] as string | undefined) ?? '') : '';
        }
      );
    }
    // 读进程内缓存，不要向 TDLib 现问：这个构建没有 getConnectionState 方法
    // （实测 "Unknown class \"getConnectionState\""，每次进页面必失败，
    // connectionState 停在 '' 于是顶部一直显示"读取代理状态…"）。
    // Globals 在建 client 时就订阅了 updateConnectionState 并缓存，正是为了
    // 解决"订阅晚了就收不到当前值"——页面按需读它即可。
    this.connectionState = getConnectionState();
  }

  private consumeRouteParams(): void {
    if (this.paramsConsumed) { return; }
    this.paramsConsumed = true;
    // 由 applyRouteParams() 调用，那时 navParams 已经由外壳填好。
    const params: Record<string, Object> | undefined = this.navParams;
    if (params === undefined) { return; }
    const server = (params['proxyServer'] as string | undefined) ?? '';
    const portValue = params['proxyPort'] as number | undefined;
    const port = portValue ?? 0;
    if (server === '' || port <= 0) { return; }
    const type = (params['proxyType'] as string | undefined) ?? PROXY_SOCKS5;
    this.resetForm();
    this.importedForm = true;
    this.fType = TYPES.some((item: TypeOption): boolean => item.value === type)
      ? type : PROXY_SOCKS5;
    this.fServer = server;
    this.fPort = `${port}`;
    this.fUser = (params['proxyUsername'] as string | undefined) ?? '';
    this.fPass = (params['proxyPassword'] as string | undefined) ?? '';
    this.fSecret = (params['proxySecret'] as string | undefined) ?? '';
    this.fHttpOnly = (params['proxyHttpOnly'] as boolean | undefined) ?? false;
    this.fEnableAfterSave = true;
    this.sheetOpen = true;
  }

  private sorted(list: ProxyEntry[]): ProxyEntry[] {
    return list.slice().sort((left: ProxyEntry, right: ProxyEntry): number => {
      if (left.isEnabled !== right.isEnabled) { return left.isEnabled ? -1 : 1; }
      if (left.lastUsedDate !== right.lastUsedDate) { return right.lastUsedDate - left.lastUsedDate; }
      return left.id - right.id;
    });
  }

  // 换到一个还没有代理的账号时，把本机镜像里的补回去（代理存在 TDLib 里，
  // 而 TDLib 数据库按账号槽分开——issue #131）。一律加成未启用：切账号那一刻
  // 自动改连接不礼貌，用户自己点启用。补完重新拉一次，拿到 TDLib 给的新 id。
  private syncOff(): string[] {
    return parseSyncOff(AppStorage.get<string>(KEY_PROXY_SYNC_OFF) ?? '');
  }

  // 单条代理是否参与跨账号同步。关掉的立刻从镜像里摘掉，别人的账号不会再补到它。
  private toggleSync(entry: ProxyEntry): void {
    const next: string[] = toggledSyncOff(entry, this.syncOff());
    setString(KEY_PROXY_SYNC_OFF, serializeSyncOff(next));
    setString(KEY_PROXY_MIRROR, serializeProxyMirror(syncableOf(this.proxies, next)));
    promptAction.showToast({
      message: syncEnabledFor(entry, next)
        ? $r('app.string.px_sync_accounts') : $r('app.string.px_sync_accounts_off'),
      duration: 1400
    });
  }

  private async restoreMirrored(list: ProxyEntry[]): Promise<ProxyEntry[]> {
    if (list.length > 0) {
      return list;
    }
    const mirror: ProxyEntry[] = parseProxyMirror(AppStorage.get<string>(KEY_PROXY_MIRROR) ?? '');
    const missing: ProxyEntry[] = missingFromAccount(mirror, list);
    if (missing.length === 0) {
      return list;
    }
    for (const entry of missing) {
      try {
        await addProxy(entry, false);
      } catch (caught) {
        // 单条补不回来不影响其余（凭据过期、协议不支持都可能）。绝不打内容。
        logE('ProxyPage.restoreMirrored: one entry failed');
      }
    }
    return listProxies();
  }

  private load(initial: boolean): void {
    const sequence = ++this.loadSequence;
    if (initial && this.proxies.length === 0) {
      this.loading = true;
      this.loadError = '';
      this.startSkeletonPulse();
    } else {
      this.refreshing = true;
      this.syncWarning = '';
    }
    listProxies().then((list: ProxyEntry[]): Promise<ProxyEntry[]> => this.restoreMirrored(list))
      .then((list: ProxyEntry[]): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      // 镜像跟着当前账号的清单走：加/改/删之后这里都会再跑一遍。
      setString(KEY_PROXY_MIRROR, serializeProxyMirror(syncableOf(list, this.syncOff())));
      const sorted = this.sorted(list);
      this.proxies = sorted;
      this.loading = false;
      this.refreshing = false;
      this.loadError = '';
      this.syncWarning = '';
      this.stopSkeletonPulse();
      const enabled = sorted.find((entry: ProxyEntry): boolean => entry.isEnabled);
      if (enabled !== undefined) { this.preferredProxyId = enabled.id; }
      this.startPingQueue(sorted);
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.loading = false;
      this.refreshing = false;
      this.stopSkeletonPulse();
      if (this.proxies.length === 0) {
        this.loadError = str('px_list_unreadable');
      } else {
        this.syncWarning = str('px_sync_failed');
      }
      logE(`ProxyPage.listProxies failed: ${error.message}`);
    });
  }

  private activeProxy(): ProxyEntry | null {
    return this.proxies.find((entry: ProxyEntry): boolean => entry.isEnabled) ?? null;
  }

  private usingProxy(): boolean {
    return this.activeProxy() !== null;
  }

  private currentProxyDetail(): string {
    const active = this.activeProxy();
    if (active === null) { return str('px_direct_sub'); }
    return `${proxyTypeLabel(active.type)} · ${active.server}:${active.port}`;
  }

  private connectionColor(): string {
    if (this.connectionState === 'connectionStateReady') { return OK_GREEN; }
    if (this.connectionState === 'connectionStateWaitingForNetwork') { return DANGER; }
    return WARNING;
  }

  private connectionLabel(): string {
    return proxyConnectionText(this.connectionState, this.usingProxy());
  }

  private currentPingId(): number {
    const active = this.activeProxy();
    return active !== null ? active.id : DIRECT_PING_ID;
  }

  private pingState(id: number): string {
    return this.pingStates.get(id) ?? 'loading';
  }

  // 启用中的代理以 TDLib 连接状态为准：连着就是连着，ping 报错不算数（issue #31）。
  private rowConnected(id: number): boolean {
    const enabled: ProxyEntry | null = this.activeProxy();
    return enabled !== null && enabled.id === id &&
      enabledProxyConnected(true, this.connectionState);
  }

  private pingLabel(id: number): string {
    const state = this.pingState(id);
    if (state === 'loading') { return str('px_testing'); }
    if (state === 'error') {
      return this.rowConnected(id) ? str('proxy_state_connected') : str('px_unreachable');
    }
    if (state === 'reach') {
      // ≈ = 到代理服务器的 TCP 握手耗时，不是 ping 的整条往返（见 util/proxyReach）。
      const secs = this.pings.get(id) ?? 0;
      return `\u2248${Math.max(1, Math.round(secs * 1000))} ms`;
    }
    const seconds = this.pings.get(id) ?? 0;
    return `${Math.max(1, Math.round(seconds * 1000))} ms`;
  }

  private pingColor(id: number): string {
    const state = this.pingState(id);
    if (state === 'ready' || state === 'reach') { return OK_GREEN; }
    if (state === 'error') { return this.rowConnected(id) ? OK_GREEN : DANGER; }
    return COLOR_TEXT_SECONDARY as string;
  }

  private beginPing(id: number): number {
    const token = (this.pingTokens.get(id) ?? 0) + 1;
    this.pingTokens.set(id, token);
    const states = new Map(this.pingStates);
    states.set(id, 'loading');
    this.pingStates = states;
    return token;
  }

  // ping 报错但代理连着时的回落结果：TCP 握手耗时当延迟（issue #31）。
  private finishReach(id: number, token: number, ms: number): void {
    if (!this.active || this.pingTokens.get(id) !== token) { return; }
    const states = new Map(this.pingStates);
    states.set(id, 'reach');
    this.pingStates = states;
    const pings = new Map(this.pings);
    pings.set(id, ms / 1000);
    this.pings = pings;
  }

  private finishPing(id: number, token: number, seconds: number, success: boolean): void {
    if (!this.active || this.pingTokens.get(id) !== token) { return; }
    const states = new Map(this.pingStates);
    states.set(id, success ? 'ready' : 'error');
    this.pingStates = states;
    if (success) {
      const values = new Map(this.pings);
      values.set(id, seconds);
      this.pings = values;
    }
  }

  private async pingLane(list: ProxyEntry[], start: number, generation: number): Promise<void> {
    let index = start;
    while (index < list.length && this.active && generation === this.pingGeneration) {
      const entry = list[index];
      const token = this.beginPing(entry.id);
      try {
        const seconds = await pingProxy(entry.id);
        if (generation === this.pingGeneration) {
          this.finishPing(entry.id, token, seconds, true);
        }
      } catch (caught) {
        // 原来这里把错误整个吞掉，行上只剩一句"无法连接"，分不清是代理真的
        // 不通还是请求本身没发对——testProxy 就栽在后者上（这个 TDLib 构建
        // 的 proxy 系列 API 收的是 proxy 对象，不是标准的平铺字段）。
        logE(`[proxy] ping ${entry.id} failed, raw: ${(caught as Error).message}`);
        if (generation !== this.pingGeneration) {
          index += 3;
          continue;
        }
        if (!this.rowConnected(entry.id)) {
          this.finishPing(entry.id, token, 0, false);
          index += 3;
          continue;
        }
        // ping 报错但 TDLib 显示这个代理已连接（issue #31）：ping 给不出数字，
        // 量一次到代理服务器的 TCP 握手耗时当延迟，显示成 ≈xx ms。
        try {
          const ms: number = await measureProxyConnectMs(entry.server, entry.port, REACH_TIMEOUT_MS);
          if (generation === this.pingGeneration) {
            this.finishReach(entry.id, token, ms);
          }
        } catch (reachErr) {
          logE(`[proxy] reach ${entry.id} failed: ${(reachErr as Error).message}`);
          if (generation === this.pingGeneration) {
            this.finishPing(entry.id, token, 0, false);
          }
        }
      }
      index += 3;
    }
  }

  private startPingQueue(list: ProxyEntry[]): void {
    const generation = ++this.pingGeneration;
    this.pingDirect(generation);
    for (let lane = 0; lane < Math.min(3, list.length); lane++) {
      this.pingLane(list, lane, generation);
    }
  }

  private pingDirect(generation: number = this.pingGeneration): void {
    const token = this.beginPing(DIRECT_PING_ID);
    pingProxy(0).then((seconds: number): void => {
      if (generation === this.pingGeneration) {
        this.finishPing(DIRECT_PING_ID, token, seconds, true);
      }
    }).catch((): void => {
      if (generation === this.pingGeneration) {
        this.finishPing(DIRECT_PING_ID, token, 0, false);
      }
    });
  }

  private retryPing(entry: ProxyEntry): void {
    const token = this.beginPing(entry.id);
    pingProxy(entry.id).then((seconds: number): void => {
      this.finishPing(entry.id, token, seconds, true);
    }).catch((): void => {
      this.finishPing(entry.id, token, 0, false);
    });
  }

  private retryCurrentPing(): void {
    const active = this.activeProxy();
    if (active === null) { this.pingDirect(); } else { this.retryPing(active); }
  }

  private copyEnabled(entry: ProxyEntry, enabled: boolean): ProxyEntry {
    return {
      id: entry.id, server: entry.server, port: entry.port, type: entry.type,
      username: entry.username, password: entry.password, secret: entry.secret,
      httpOnly: entry.httpOnly, lastUsedDate: entry.lastUsedDate, isEnabled: enabled
    };
  }

  private applyEnabledProxy(proxyId: number): void {
    this.proxies = this.sorted(this.proxies.map((entry: ProxyEntry): ProxyEntry =>
      this.copyEnabled(entry, proxyId > 0 && entry.id === proxyId)
    ));
  }

  private masterChanged(useProxy: boolean): void {
    if (this.actionKey !== '') { return; }
    if (!useProxy) {
      this.setEnabledProxy(null);
      return;
    }
    if (this.proxies.length === 0) {
      this.openAdd();
      return;
    }
    const preferred = this.proxies.find(
      (entry: ProxyEntry): boolean => entry.id === this.preferredProxyId
    ) ?? this.proxies[0];
    this.setEnabledProxy(preferred);
  }

  private async setEnabledProxy(entry: ProxyEntry | null): Promise<void> {
    if (this.actionKey !== '') { return; }
    const targetId = entry !== null ? entry.id : 0;
    if ((entry === null && !this.usingProxy()) ||
      (entry !== null && this.activeProxy()?.id === entry.id)) { return; }
    const snapshot = this.proxies.slice();
    const sequence = ++this.operationSequence;
    this.actionKey = entry !== null ? `enable_${entry.id}` : 'disable';
    this.applyEnabledProxy(targetId);
    this.connectionState = entry !== null
      ? 'connectionStateConnectingToProxy' : 'connectionStateConnecting';
    try {
      if (entry !== null) { await enableProxy(entry.id); } else { await disableProxy(); }
      if (!this.active || sequence !== this.operationSequence) { return; }
      this.actionKey = '';
      if (entry !== null) { this.preferredProxyId = entry.id; }
      promptAction.showToast({
        message: entry !== null ? str('px_enabled_server', entry.server) : $r('app.string.px_switched_direct'), duration: 1400
      });
      this.subscribeConnectionState();
      this.load(false);
    } catch (caught) {
      if (!this.active || sequence !== this.operationSequence) { return; }
      const error = caught as TdError;
      this.actionKey = '';
      this.proxies = snapshot;
      this.syncWarning = str('px_state_resyncing');
      promptAction.showToast({
        message: proxyActionErrorText(error.message, entry !== null ? str('px_enable') : str('px_use_direct')),
        duration: 1900
      });
      logE(`ProxyPage.setEnabledProxy failed: ${error.message}`);
      this.load(false);
    }
  }

  private confirmRemove(entry: ProxyEntry): void {
    if (this.actionKey !== '' || this.saving) { return; }
    promptAction.showDialog({
      title: $r('app.string.px_delete'),
      message: entry.isEnabled
        ? str('px_delete_active_confirm', entry.server, entry.port)
        : str('px_delete_confirm', entry.server, entry.port),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.delete'), color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) { this.performRemove(entry); }
    }).catch((error: Object): void => {
      logE(`ProxyPage.remove dialog failed: ${JSON.stringify(error)}`);
    });
  }

  private async performRemove(entry: ProxyEntry): Promise<void> {
    if (this.actionKey !== '') { return; }
    const before = this.proxies.slice();
    const sequence = ++this.operationSequence;
    this.actionKey = `remove_${entry.id}`;
    animateTo({ duration: this.animationDuration(170), curve: Curve.EaseOut }, (): void => {
      this.proxies = this.proxies.filter((item: ProxyEntry): boolean => item.id !== entry.id);
    });
    try {
      await removeProxy(entry.id);
      if (!this.active || sequence !== this.operationSequence) { return; }
      this.actionKey = '';
      if (this.preferredProxyId === entry.id) { this.preferredProxyId = 0; }
      promptAction.showToast({ message: $r('app.string.px_deleted'), duration: 1300 });
      this.load(false);
    } catch (caught) {
      if (!this.active || sequence !== this.operationSequence) { return; }
      const error = caught as TdError;
      this.actionKey = '';
      this.proxies = before;
      promptAction.showToast({
        message: proxyActionErrorText(error.message, str('px_delete')), duration: 1800
      });
      this.load(false);
    }
  }

  private copyShareLink(entry: ProxyEntry): void {
    if (entry.type === PROXY_HTTP || this.actionKey !== '') { return; }
    this.actionKey = `share_${entry.id}`;
    getProxyShareLink(entry.id).then((url: string): void => {
      if (!this.active) { return; }
      if (url === '') { throw new TdError(-1, 'empty proxy link'); }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data).then((): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.px_link_copied'), duration: 1400 });
      }).catch((error: Error): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        logE(`ProxyPage.copyProxyLink failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.px_copy_failed'), duration: 1600 });
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.actionKey = '';
      logE(`ProxyPage.getProxyLink failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.px_link_failed'), duration: 1600 });
    });
  }

  private resetForm(): void {
    this.editingId = 0;
    this.importedForm = false;
    this.fType = PROXY_SOCKS5;
    this.fServer = '';
    this.fPort = '';
    this.fUser = '';
    this.fPass = '';
    this.fSecret = '';
    this.fHttpOnly = false;
    this.fEnableAfterSave = true;
    this.fRevealCredential = false;
    this.formError = '';
    this.formTestState = 'idle';
    this.formTestMs = 0;
    this.formOutcomeUnknown = false;
  }

  private openAdd(): void {
    if (this.actionKey !== '' || this.saving) { return; }
    this.resetForm();
    this.sheetOpen = true;
  }

  private openEdit(entry: ProxyEntry): void {
    if (this.actionKey !== '' || this.saving) { return; }
    this.resetForm();
    this.editingId = entry.id;
    this.fType = entry.type;
    this.fServer = entry.server;
    this.fPort = `${entry.port}`;
    this.fUser = entry.username;
    this.fPass = entry.password;
    this.fSecret = entry.secret;
    this.fHttpOnly = entry.httpOnly;
    this.fEnableAfterSave = entry.isEnabled;
    this.sheetOpen = true;
  }

  private cancelForm(): void {
    if (this.saving) { return; }
    this.sheetOpen = false;
    this.formSequence++;
    this.resetForm();
  }

  private onFormChanged(): void {
    this.formError = '';
    this.formTestState = 'idle';
    this.formTestMs = 0;
    this.formOutcomeUnknown = false;
    this.formSequence++;
  }

  private formEntry(): ProxyEntry {
    const existing = this.proxies.find(
      (entry: ProxyEntry): boolean => entry.id === this.editingId
    );
    return {
      id: this.editingId,
      server: this.fServer.trim(),
      port: parseProxyPort(this.fPort),
      type: this.fType,
      username: this.fType === PROXY_MTPROTO ? '' : this.fUser.trim(),
      password: this.fType === PROXY_MTPROTO ? '' : this.fPass,
      secret: this.fType === PROXY_MTPROTO ? this.fSecret.trim() : '',
      httpOnly: this.fType === PROXY_HTTP && this.fHttpOnly,
      lastUsedDate: existing !== undefined ? existing.lastUsedDate : 0,
      isEnabled: existing !== undefined ? existing.isEnabled : false
    };
  }

  private upsertProxy(entry: ProxyEntry): void {
    let next = this.proxies.filter((item: ProxyEntry): boolean => item.id !== entry.id);
    if (entry.isEnabled) {
      next = next.map((item: ProxyEntry): ProxyEntry => this.copyEnabled(item, false));
    }
    next.push(entry);
    this.proxies = this.sorted(next);
  }

  private testForm(): void {
    if (this.formTestState === 'loading' || this.saving) { return; }
    const validation = proxyFormError(this.fServer, this.fPort, this.fType, this.fSecret);
    if (validation !== '') {
      this.formError = validation;
      return;
    }
    const sequence = ++this.formSequence;
    this.formError = '';
    this.formTestState = 'loading';
    testProxy(this.formEntry()).then((seconds: number): void => {
      if (!this.active || sequence !== this.formSequence) { return; }
      this.formTestMs = Math.max(1, Math.round(seconds * 1000));
      this.formTestState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.formSequence) { return; }
      this.formTestState = 'error';
      this.formError = proxyActionErrorText(error.message, str('px_test'));
    });
  }

  private saveForm(): void {
    if (this.saving || this.formOutcomeUnknown) { return; }
    const validation = proxyFormError(this.fServer, this.fPort, this.fType, this.fSecret);
    if (validation !== '') {
      this.formError = validation;
      return;
    }
    const draft = this.formEntry();
    const duplicate = this.proxies.find((entry: ProxyEntry): boolean =>
      entry.id !== this.editingId && sameProxyConfiguration(entry, draft)
    );
    if (duplicate !== undefined) {
      if (this.editingId === 0 && this.fEnableAfterSave && !duplicate.isEnabled) {
        this.sheetOpen = false;
        this.resetForm();
        this.setEnabledProxy(duplicate);
      } else {
        this.formError = duplicate.isEnabled ? str('px_duplicate_active') : str('px_duplicate');
      }
      return;
    }
    const sequence = ++this.formSequence;
    this.saving = true;
    this.formError = '';
    if (this.editingId > 0) {
      editProxy(draft, this.fEnableAfterSave).then((saved: ProxyEntry): void => {
        if (!this.active || sequence !== this.formSequence) { return; }
        this.saving = false;
        this.upsertProxy(saved);
        if (saved.isEnabled) { this.preferredProxyId = saved.id; }
        this.sheetOpen = false;
        this.resetForm();
        promptAction.showToast({ message: $r('app.string.px_saved'), duration: 1400 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.finishFormFailure(error, sequence, str('px_save'));
      });
      return;
    }
    addProxy(draft, false).then((saved: ProxyEntry): void => {
      if (!this.active || sequence !== this.formSequence) { return; }
      if (saved.id <= 0) {
        this.finishFormFailure(new TdError(-1, 'invalid added proxy result'), sequence, str('px_add'));
        return;
      }
      this.upsertProxy(saved);
      if (!this.fEnableAfterSave) {
        this.finishFormSuccess(str('px_added'));
        return;
      }
      enableProxy(saved.id).then((): void => {
        if (!this.active || sequence !== this.formSequence) { return; }
        this.applyEnabledProxy(saved.id);
        this.preferredProxyId = saved.id;
        this.finishFormSuccess(str('px_added_enabled'));
      }).catch((error: TdError): void => {
        if (!this.active || sequence !== this.formSequence) { return; }
        this.saving = false;
        this.sheetOpen = false;
        this.resetForm();
        promptAction.showToast({
          message: error.message.toLowerCase().indexOf('timeout') >= 0
            ? $r('app.string.px_saved_pending') : $r('app.string.px_saved_not_enabled'),
          duration: 2100
        });
        this.load(false);
      });
    }).catch((error: TdError): void => {
      this.finishFormFailure(error, sequence, str('px_add'));
    });
  }

  private finishFormSuccess(message: string): void {
    this.saving = false;
    this.sheetOpen = false;
    this.resetForm();
    promptAction.showToast({ message: message, duration: 1500 });
    this.load(false);
  }

  private finishFormFailure(error: TdError, sequence: number, action: string): void {
    if (!this.active || sequence !== this.formSequence) { return; }
    this.saving = false;
    if (error.message.toLowerCase().indexOf('request timeout') >= 0) {
      this.formOutcomeUnknown = true;
      this.formError = str('px_result_unknown', action);
      this.load(false);
    } else {
      this.formError = proxyActionErrorText(error.message, action);
    }
    logE(`ProxyPage.${action} failed: ${error.message}`);
  }

  private typeTint(type: string): string {
    if (type === PROXY_MTPROTO) { return '#9B6BEA'; }
    if (type === PROXY_HTTP) { return '#FF9500'; }
    return '#3478F6';
  }

  private typeIconBackground(type: string): string {
    if (type === PROXY_MTPROTO) { return '#1F9B6BEA'; }
    if (type === PROXY_HTTP) { return '#1FFF9500'; }
    return '#1F3478F6';
  }

  private typeBadgeBackground(type: string): string {
    if (type === PROXY_MTPROTO) { return '#169B6BEA'; }
    if (type === PROXY_HTTP) { return '#16FF9500'; }
    return '#163478F6';
  }

  private typeDetail(entry: ProxyEntry): string {
    if (entry.type === PROXY_HTTP && entry.httpOnly) { return str('px_http_only'); }
    return proxyTypeLabel(entry.type);
  }

  private rowBusy(entry: ProxyEntry): boolean {
    return this.actionKey.indexOf(`_${entry.id}`) >= 0;
  }

  @Builder
  connectionCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 46, height: 46 }).fill('#163478F6');
          SymbolGlyph($r('sys.symbol.link')).fontSize(23).fontColor([COLOR_PRIMARY]);
        }
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Circle({ width: 7, height: 7 }).fill(this.connectionColor());
            Text(this.connectionLabel()).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_PRIMARY);
          }
          Text(this.currentProxyDetail()).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        if (this.actionKey === 'disable' || this.actionKey.indexOf('enable_') === 0) {
          LoadingProgress().width(24).height(24).color(COLOR_PRIMARY);
        } else {
          Toggle({ type: ToggleType.Switch, isOn: this.usingProxy() })
            .selectedColor(COLOR_PRIMARY)
            .enabled(!this.loading && this.actionKey === '')
            .onChange((value: boolean): void => this.masterChanged(value));
        }
      }.width('100%').alignItems(VerticalAlign.Center);

      Divider().strokeWidth(0.5).color(COLOR_DIVIDER);

      Row({ space: 8 }) {
        Text(this.usingProxy() ? $r('app.string.px_current_latency') : $r('app.string.px_direct_latency'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
        if (this.pingState(this.currentPingId()) === 'loading') {
          LoadingProgress().width(15).height(15).color(COLOR_PRIMARY);
        }
        Text(this.pingLabel(this.currentPingId())).fontSize(13)
          .fontWeight(FontWeight.Medium).fontColor(this.pingColor(this.currentPingId()));
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(15)
            .fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(32).height(32).borderRadius(16).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
        .accessibilityText($r('app.string.px_retest')).onClick((): void => this.retryCurrentPing());
      }.width('100%').alignItems(VerticalAlign.Center);
    }
    .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.translate({ y: -6 })
    ).animation({ duration: this.animationDuration(180), curve: Curve.EaseOut }));
  }

  @Builder
  syncWarningCard() {
    if (this.syncWarning !== '') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(16).fontColor([WARNING]);
        Text(this.syncWarning).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1)
          .maxLines(2);
        Text($r('app.string.settings_retry')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
      }
      .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#14FF9500').borderRadius(12)
      .onClick((): void => this.load(false))
      .transition(TransitionEffect.OPACITY.combine(
        TransitionEffect.translate({ y: -5 })
      ).animation({ duration: this.animationDuration(160), curve: Curve.EaseOut }));
    }
  }

  @Builder
  proxyMenu(entry: ProxyEntry) {
    Menu() {
      MenuItem({ content: $r('app.string.px_edit') }).onClick((): void => this.openEdit(entry));
      MenuItem({ content: $r('app.string.px_test') }).onClick((): void => this.retryPing(entry));
      if (entry.type !== PROXY_HTTP) {
        MenuItem({ content: $r('app.string.px_copy_link') }).onClick((): void => this.copyShareLink(entry));
      }
      MenuItem({
        content: syncEnabledFor(entry, this.syncOff())
          ? $r('app.string.px_sync_accounts_off') : $r('app.string.px_sync_accounts')
      }).onClick((): void => this.toggleSync(entry));
      MenuItem({ content: $r('app.string.px_delete') }).onClick((): void => this.confirmRemove(entry));
    }
  }

  @Builder
  proxyRow(entry: ProxyEntry) {
    Row({ space: 8 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 44, height: 44 }).fill(this.typeIconBackground(entry.type));
          SymbolGlyph(entry.type === PROXY_MTPROTO
            ? $r('sys.symbol.lock_fill') : $r('sys.symbol.link'))
            .fontSize(21).fontColor([this.typeTint(entry.type)]);
        }
        Column({ space: 4 }) {
          Text(`${entry.server}:${entry.port}`).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Row({ space: 7 }) {
            Text(this.typeDetail(entry)).fontSize(11).fontColor(this.typeTint(entry.type))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.typeBadgeBackground(entry.type)).borderRadius(6);
            if (this.pingState(entry.id) === 'loading') {
              LoadingProgress().width(13).height(13).color(COLOR_PRIMARY);
            }
            Text(this.pingLabel(entry.id)).fontSize(12).fontColor(this.pingColor(entry.id));
            if (entry.isEnabled) {
              Text($r('app.string.px_in_use')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
            }
          }.alignItems(VerticalAlign.Center);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }
      .layoutWeight(1).padding({ left: 12, top: 9, bottom: 9 })
      .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
      .accessibilityText(str('px_edit_a11y', entry.server, entry.port))
      .onClick((): void => this.openEdit(entry));

      Row() {
        if (this.rowBusy(entry)) {
          LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        } else {
          Row() {
            if (entry.isEnabled) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([Color.White]);
            }
          }
          .width(24).height(24).borderRadius(12).justifyContent(FlexAlign.Center)
          .backgroundColor(entry.isEnabled ? COLOR_PRIMARY : Color.Transparent)
          .border({
            width: entry.isEnabled ? 0 : 1.4,
            color: entry.isEnabled ? Color.Transparent : COLOR_TEXT_SECONDARY
          });
        }
      }
      .width(40).height(40).borderRadius(20).justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Transparent)
      .enabled(this.actionKey === '')
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .accessibilityText(entry.isEnabled ? $r('app.string.px_current') : $r('app.string.px_enable_this'))
      .onClick((): void => { this.setEnabledProxy(entry); });

      Row() {
        SymbolGlyph($r('sys.symbol.more')).fontSize(20).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(40).height(40).borderRadius(20).justifyContent(FlexAlign.Center)
      .margin({ right: 6 }).enabled(this.actionKey === '')
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .accessibilityText($r('app.string.px_more_actions'))
      .bindMenu(this.proxyMenu(entry), { systemMaterial: overlayMaterial('menu') });
    }
    .width('100%').alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.translate({ x: 10 })
    ).animation({ duration: this.animationDuration(170), curve: Curve.EaseOut }));
  }

  @Builder
  proxyListCard() {
    Column() {
      Row() {
        Text($r('app.string.px_servers')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
        Blank();
        Text(plural('px_count', this.proxies.length, this.proxies.length)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%').height(40).padding({ left: 14, right: 14 });
      ForEach(this.proxies, (entry: ProxyEntry, index: number) => {
        if (index > 0) {
          Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 68 });
        }
        this.proxyRow(entry);
      }, (entry: ProxyEntry): string =>
        `proxy_${entry.id}_${entry.server}_${entry.port}_${entry.type}_${entry.httpOnly}_${entry.isEnabled}`
      );
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  skeletonCard() {
    Column() {
      ForEach(SKELETON_ROWS, (index: number) => {
        if (index > 0) {
          Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 68 });
        }
        Row({ space: 12 }) {
          Circle({ width: 44, height: 44 }).fill($r('app.color.surface_alt'));
          Column({ space: 7 }) {
            Row().width(index % 2 === 0 ? '58%' : '46%').height(13)
              .borderRadius(7).backgroundColor($r('app.color.surface_alt'));
            Row().width(index % 2 === 0 ? '38%' : '52%').height(10)
              .borderRadius(5).backgroundColor($r('app.color.surface_alt'));
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Circle({ width: 32, height: 32 }).fill($r('app.color.surface_alt'));
        }.height(64).width('100%').padding({ left: 12, right: 12 });
      }, (index: number): string => `${index}`);
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .opacity(this.skeletonBright ? 0.55 : 0.94)
    .animation({ duration: this.animationDuration(640), curve: Curve.EaseInOut });
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 68, height: 68 }).fill('#163478F6');
        SymbolGlyph($r('sys.symbol.link')).fontSize(32).fontColor([COLOR_PRIMARY]);
      }
      Text($r('app.string.px_empty')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.px_empty_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 290 });
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.plus')).fontSize(15).fontColor([Color.White]);
        Text($r('app.string.px_add')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White);
      }
      .height(42).padding({ left: 18, right: 19 }).borderRadius(21).backgroundColor(COLOR_PRIMARY)
      .margin({ top: 5 }).stateStyles({
        normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle
      }).onClick((): void => this.openAdd());
    }
    .width('100%').padding({ top: 42, bottom: 42 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY.combine(
      TransitionEffect.scale({ x: 0.97, y: 0.97 })
    ).animation({ duration: this.animationDuration(180), curve: Curve.EaseOut }));
  }

  @Builder
  errorState() {
    Column({ space: 9 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 64, height: 64 }).fill('#14E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(30).fontColor([DANGER]);
      }
      Text($r('app.string.px_load_failed')).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text(this.loadError).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
        Text($r('app.string.settings_reload')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White);
      }
      .height(40).padding({ left: 16, right: 17 }).borderRadius(20).backgroundColor(COLOR_PRIMARY)
      .stateStyles({ normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle })
      .onClick((): void => this.load(true));
    }
    .width('100%').padding({ top: 40, bottom: 40, left: 20, right: 20 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  typeSelector() {
    Row({ space: 4 }) {
      ForEach(TYPES, (option: TypeOption) => {
        Text(option.label).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.fType === option.value ? Color.White : COLOR_TEXT_SECONDARY)
          .layoutWeight(1).height(34).textAlign(TextAlign.Center)
          .backgroundColor(this.fType === option.value ? COLOR_PRIMARY : Color.Transparent)
          .borderRadius(17).padding({ top: 7 })
          .animation({ duration: this.animationDuration(150), curve: Curve.EaseOut })
          .onClick((): void => {
            if (!this.saving && this.fType !== option.value) {
              this.fType = option.value;
              this.onFormChanged();
            }
          });
      }, (option: TypeOption): string => option.value);
    }
    .width('100%').padding(3).backgroundColor($r('app.color.surface_alt')).borderRadius(20);
  }

  @Builder
  formField(label: ResourceStr, value: string, placeholder: ResourceStr,
    numberOnly: boolean, onChange: (value: string) => void) {
    Column({ space: 5 }) {
      Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      TextInput({ text: value, placeholder: placeholder })
        .width('100%').height(42).fontSize(16).type(numberOnly ? InputType.Number : InputType.Normal)
        .backgroundColor($r('app.color.page_bg')).borderRadius(10)
        .padding({ left: 12, right: 12 }).caretColor(COLOR_PRIMARY)
        .onChange((next: string): void => {
          onChange(next);
          this.onFormChanged();
        });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  credentialField() {
    Column({ space: 5 }) {
      Text(this.fType === PROXY_MTPROTO ? $r('app.string.px_secret') : $r('app.string.px_password_optional'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      Row({ space: 6 }) {
        TextInput({
          text: this.fType === PROXY_MTPROTO ? this.fSecret : this.fPass,
          placeholder: this.fType === PROXY_MTPROTO ? 'MTProto secret' : $r('app.string.px_password')
        })
          .layoutWeight(1).height(42).fontSize(16)
          .type(this.fRevealCredential ? InputType.Normal : InputType.Password)
          .backgroundColor(Color.Transparent).padding({ left: 12 }).caretColor(COLOR_PRIMARY)
          .onChange((next: string): void => {
            if (this.fType === PROXY_MTPROTO) { this.fSecret = next; } else { this.fPass = next; }
            this.onFormChanged();
          });
        Text(this.fRevealCredential ? $r('app.string.hide') : $r('app.string.show')).fontSize(12).fontColor(COLOR_PRIMARY)
          .width(44).height(38).textAlign(TextAlign.Center).padding({ top: 10 })
          .onClick((): void => { this.fRevealCredential = !this.fRevealCredential; });
      }
      .width('100%').height(42).backgroundColor($r('app.color.page_bg')).borderRadius(10);
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  formTestCard() {
    Row({ space: 9 }) {
      if (this.formTestState === 'loading') {
        LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph(this.formTestState === 'ready'
          ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.arrow_clockwise'))
          .fontSize(20).fontColor([
            this.formTestState === 'ready' ? OK_GREEN : COLOR_PRIMARY
          ]);
      }
      Column({ space: 2 }) {
        Text(this.formTestState === 'loading' ? $r('app.string.px_testing_connection') :
          (this.formTestState === 'ready' ? $r('app.string.px_test_ok') : $r('app.string.px_test_current')))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.formTestState === 'ready' ? `${this.formTestMs} ms` : $r('app.string.px_test_no_save'))
          .fontSize(11).fontColor(this.formTestState === 'ready' ? OK_GREEN : COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Text(this.formTestState === 'ready' ? $r('app.string.px_retest_short') : $r('app.string.px_test_short')).fontSize(13).fontColor(COLOR_PRIMARY);
    }
    .width('100%').padding({ left: 12, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface_alt')).borderRadius(11)
    .enabled(!this.saving && this.formTestState !== 'loading')
    .stateStyles({ normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle })
    .onClick((): void => this.testForm());
  }

  @Builder
  proxyFormSheet() {
    Scroll() {
      Column({ space: 13 }) {
        Column({ space: 3 }) {
          Text(this.editingId > 0 ? $r('app.string.px_edit') : $r('app.string.px_add'))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text(this.importedForm ? $r('app.string.px_from_link') :
            (this.editingId > 0 ? $r('app.string.px_edit_note') : $r('app.string.px_not_active_until_save')))
            .fontSize(12).fontColor(this.importedForm ? WARNING : COLOR_TEXT_SECONDARY)
            .textAlign(TextAlign.Center);
        }.width('100%').padding({ top: 5 });

        this.typeSelector();

        Column({ space: 11 }) {
          this.formField($r('app.string.px_server'), this.fServer, $r('app.string.px_server_hint'), false,
            (value: string): void => { this.fServer = value; });
          this.formField($r('app.string.px_port'), this.fPort, '1–65535', true,
            (value: string): void => { this.fPort = value; });
          if (this.fType !== PROXY_MTPROTO) {
            this.formField($r('app.string.px_username_optional'), this.fUser, $r('app.string.px_username'), false,
              (value: string): void => { this.fUser = value; });
          }
          this.credentialField();
          if (this.fType === PROXY_HTTP) {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text($r('app.string.px_http_only_toggle')).fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
                Text($r('app.string.px_http_only_sub')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.fHttpOnly })
                .selectedColor(COLOR_PRIMARY).enabled(!this.saving)
                .onChange((value: boolean): void => {
                  this.fHttpOnly = value;
                  this.onFormChanged();
                });
            }.width('100%');
          }
        }
        .width('100%').padding(13).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

        this.formTestCard();

        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text($r('app.string.px_enable_on_save')).fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.px_enable_on_save_sub')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Toggle({ type: ToggleType.Switch, isOn: this.fEnableAfterSave })
            .selectedColor(COLOR_PRIMARY).enabled(!this.saving)
            .onChange((value: boolean): void => { this.fEnableAfterSave = value; });
        }
        .width('100%').padding({ left: 13, right: 13, top: 11, bottom: 11 })
        .backgroundColor(COLOR_SURFACE).borderRadius(12);

        if (this.formError !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(16).fontColor([DANGER]);
            Text(this.formError).fontSize(12).fontColor(DANGER).layoutWeight(1).maxLines(3);
          }
          .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor('#14E64646').borderRadius(11)
          .transition(TransitionEffect.OPACITY.combine(
            TransitionEffect.translate({ y: -5 })
          ).animation({ duration: this.animationDuration(150), curve: Curve.EaseOut }));
        }

        Row({ space: 10 }) {
          Text($r('app.string.cancel')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
            .layoutWeight(1).height(44).textAlign(TextAlign.Center).padding({ top: 12 })
            .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
            .enabled(!this.saving)
            .stateStyles({ normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle })
            .onClick((): void => this.cancelForm());
          Row({ space: 6 }) {
            if (this.saving) { LoadingProgress().width(16).height(16).color(Color.White); }
            Text(this.saving ? $r('app.string.saving') : (this.editingId > 0 ? $r('app.string.save_changes') : $r('app.string.px_add')))
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White);
          }
          .layoutWeight(1).height(44).justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_PRIMARY).borderRadius(12)
          .opacity(this.formOutcomeUnknown ? 0.45 : 1)
          .enabled(!this.saving && !this.formOutcomeUnknown)
          .stateStyles({ normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle })
          .onClick((): void => this.saveForm());
        }.width('100%');
      }
      .width('100%').padding({
        left: 14, right: 14, top: 5, bottom: this.bottomSafe + 20
      });
    }
    .align(Alignment.Top)
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
  }

  build() {
    Column() {
      HdsSubDestination({
        title: $r('app.string.px_title'), scroller: this.hdsScroller,
        pageBackground: COLOR_PAGE_BG,
        onBackPressed: (): boolean => { return this.onBackPressed(); },
        onRouteParams: (param: Object | undefined): void => {
          this.navParams = param as Record<string, Object> | undefined;
          // 必须在这里调而不是等 aboutToAppear：实测 onReady 晚于 aboutToAppear。
          this.applyRouteParams();
        }
      }) {
      Scroll(this.hdsScroller) {
        Column({ space: 12 }) {
          if (!this.loading || this.proxies.length > 0) {
            this.connectionCard();
          }
          this.syncWarningCard();
          if (this.loading && this.proxies.length === 0) {
            this.skeletonCard();
          } else if (this.loadError !== '' && this.proxies.length === 0) {
            this.errorState();
          } else if (this.proxies.length === 0) {
            this.emptyState();
          } else {
            this.proxyListCard();
            Text($r('app.string.px_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%')
              .padding({ left: 14, right: 14, top: 1 });
          }
        }
        .width('100%').padding({
          left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24
        });
      }
      .layoutWeight(1).width('100%').align(Alignment.Top)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false);
    }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.sheetOpen, this.proxyFormSheet(), {
      height: '82%', backgroundColor: COLOR_PAGE_BG, dragBar: !this.saving, blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
  }
}
