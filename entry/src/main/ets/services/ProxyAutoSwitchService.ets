import { ProxyCandidateRace, ProxyCandidateProbe } from './ProxyCandidateRace';
import { ProxyProbeCancellation } from '../util/ProxyProbeCancellation';
import { TdClient, TimerFns } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_PROXY_AUTO_SWITCH, KEY_PROXY_SWITCH_DELAY_SEC
} from '../store/AppSettings';
import {
  normalizeProxySwitchDelay, orderedProxyCandidateIds, PROXY_AUTO_SWITCH_AVAILABLE, ProxySwitchCandidate
} from '../util/proxyAutoSwitch';
import { ProxyHealthSource } from '../util/proxyHealth';
import { logI, logW } from '../util/log';
import { subscribeNetworkType } from './NetworkStateService';
import { proxyHealthMonitor } from './ProxyHealthMonitor';

export type ProxyNetworkSubscription = (listener: (network: string) => void) => () => void;

export interface ProxyAutoSwitchEntry extends ProxySwitchCandidate {
  isEnabled: boolean;
}

// 中继层删掉之后，代理请求就是普通的 TDLib 请求。取消不再需要撤销临时隧道，
// 由 ProxyProbeCancellation 本身把 promise 拒掉即可。
function send(target: TdClient, request: TdRequest, timeoutMs: number,
  cancellation?: ProxyProbeCancellation): Promise<TdObject> {
  const run = (): Promise<TdObject> => target.send(request, timeoutMs);
  return cancellation === undefined ? run() : cancellation.run(run);
}

// One instance follows the active TDLib runtime. The timer must not belong to
// ProxyPage: leaving settings must not turn automatic failover off.
export class ProxyAutoSwitchService {
  private clock: TimerFns;
  private probe: ProxyCandidateProbe;
  private probeRace: ProxyCandidateRace | undefined = undefined;
  private subscribeNetwork: ProxyNetworkSubscription;
  private client: TdClient | null = null;
  private unsubscribe: (() => void) | null = null;
  private unsubscribeNetwork: (() => void) | null = null;
  private hadNetwork: boolean = true;
  private networkType: string = '';
  private timer: number = -1;
  private generation: number = 0;
  private listSequence: number = 0;
  private switchingToken: number = -1;
  private connectionState: string = '';
  private proxyConnectPending: boolean = false;
  private listKnown: boolean = false;
  private proxyCount: number = 0;
  private activeProxyId: number = 0;
  private lastAttemptedProxyId: number = -1;
  // 本轮（自上次连上/换网/手动选择以来）已经切过几次。绕完一圈还连不上就停手：
  // 每 10 秒重连一次代理，用户看到的就是"一直连接中"，那正是这个功能当初被关掉
  // 的原因。停下来等 Ready 或换网再重新开始，比无休止重拨强。
  private switchAttempts: number = 0;
  // Selection ownership is independent of the failover timer: Ready may cancel
  // a timer before enableProxy's acknowledgement arrives.
  private selectionIntent: number = 0;
  private selectionRevision: number = 0;
  private confirmedProxyId: number = -1;
  private selectionListeners: Set<(proxyId: number) => void> = new Set();
  // 注入式的"这个功能开没开"。生产走 PROXY_AUTO_SWITCH_AVAILABLE，单测注入
  // true/false 覆盖开关两端的状态机。
  private available: () => boolean;
  // 候选的顺序和"值不值得试"都来自这里。单测注入假表，生产是 tcping 巡检。
  private health: ProxyHealthSource;
  private foreground: boolean = true;

  constructor(clock?: TimerFns, subscribeNetwork?: ProxyNetworkSubscription, probe?: ProxyCandidateProbe,
    available: () => boolean = (): boolean => PROXY_AUTO_SWITCH_AVAILABLE,
    health?: ProxyHealthSource) {
    this.clock = clock ?? {
      setTimeout: (callback: () => void, ms: number): number => setTimeout(callback, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
    this.available = available;
    this.health = health ?? proxyHealthMonitor;
    this.subscribeNetwork = subscribeNetwork ?? subscribeNetworkType;
    // 候选的判据换成本机 tcping 的结果，不再发 pingProxy。
    //
    // pingProxy 验的是"经这个代理到 Telegram DC"的端到端路径，比 tcping 真，但
    // 两个硬伤：假阴性常见（issue #31：代理能用、pingProxy 报错），以及它要占着
    // TDLib 客户端、一次好几秒——而这时候 TDLib 正卡在连接中，本来就发不出请求。
    // 代价是 tcping 绿只代表端口开着（认证失败、出不了网它看不出来），所以它只
    // 用来**排序和排除**，真正的结论由"切过去之后 TDLib 连不连得上"给。
    this.probe = probe ?? (async (id: number): Promise<boolean> => this.health.usable(id));
  }

  attach(target: TdClient): void {
    this.detach();
    this.client = target;
    this.foreground = AppStorage.get<boolean>('appIsForeground') ?? true;
    this.syncHealthMonitor();
    this.hadNetwork = this.networkAvailable();
    this.networkType = AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other';
    this.unsubscribeNetwork = this.subscribeNetwork((network: string): void => {
      if (this.client === target) { this.onNetworkState(network); }
    });
    this.unsubscribe = target.onUpdate('updateConnectionState', (update: TdObject): void => {
      const state = update['state'] as TdObject | undefined;
      this.onConnectionState((state?.['@type'] as string | undefined) ?? '');
    });
  }

  detach(target?: TdClient): void {
    if (target !== undefined && this.client !== target) { return; }
    this.cancelWork();
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.unsubscribeNetwork !== null) {
      this.unsubscribeNetwork();
      this.unsubscribeNetwork = null;
    }
    this.client = null;
    this.connectionState = '';
    this.proxyConnectPending = false;
    this.listKnown = false;
    this.proxyCount = 0;
    this.activeProxyId = 0;
    this.lastAttemptedProxyId = -1;
    this.switchAttempts = 0;
    this.listSequence++;
    this.invalidateSelection();
    this.selectionListeners.clear();
    this.syncHealthMonitor();
  }

  runtimeReady(target: TdClient): void {
    if (this.client === target) { this.refreshProxyList(); }
  }

  settingsChanged(): void {
    if (!this.autoSwitchOn()) {
      this.lastAttemptedProxyId = -1;
      this.switchAttempts = 0;
    }
    this.syncHealthMonitor();
    this.cancelWork();
    this.armIfNeeded();
  }

  // 巡检只在"勾了自动切换 + 有客户端"时开。start/stop 自己幂等，这里不做判断，
  // 免得两处判据（这里和 monitor 内部）走岔。
  private syncHealthMonitor(): void {
    if (this.foreground && this.autoSwitchOn() && this.client !== null) {
      this.health.start();
    } else {
      this.health.stop();
    }
  }

  proxyListChanged(entries: ProxyAutoSwitchEntry[]): void {
    this.listSequence++;
    this.invalidateSelection();
    this.applyProxyList(entries, true);
  }

  getSelectionRevision(): number { return this.selectionRevision; }

  selectionIsCurrent(target: TdClient, revision: number): boolean {
    return this.client === target && this.selectionRevision === revision;
  }

  subscribeSelection(target: TdClient, listener: (proxyId: number) => void): () => void {
    if (this.client !== target) { return (): void => {}; }
    this.selectionListeners.add(listener);
    if (this.confirmedProxyId >= 0) { listener(this.confirmedProxyId); }
    return (): void => { this.selectionListeners.delete(listener); };
  }

  // A read is not a user selection and must not restart an existing deadline.
  proxyListLoaded(target: TdClient, revision: number, entries: ProxyAutoSwitchEntry[]): boolean {
    if (!this.selectionIsCurrent(target, revision)) { return false; }
    this.listSequence++;
    this.applyProxyList(entries, false);
    this.publishSelection(this.activeProxyId);
    return true;
  }

  private invalidateSelection(): void {
    this.selectionIntent++;
    this.selectionRevision++;
    this.confirmedProxyId = -1;
  }

  private publishSelection(proxyId: number): void {
    if (this.confirmedProxyId === proxyId) { return; }
    this.confirmedProxyId = proxyId;
    this.selectionRevision++;
    this.selectionListeners.forEach((listener: (id: number) => void): void => listener(proxyId));
  }

  proxySelectionChanged(proxyId: number): void {
    // A list requested before this user action must not restore the old id.
    this.listSequence++;
    this.invalidateSelection();
    this.activeProxyId = proxyId;
    this.lastAttemptedProxyId = -1;
    this.switchAttempts = 0;
    // Selection is intent, not proof that TDLib is still connecting. Add/edit
    // acknowledgements can arrive after Ready/Updating; canArm checks the
    // actual connection state before starting another failover timer.
    this.proxyConnectPending = this.isConnecting();
    this.cancelWork();
    this.armIfNeeded();
  }

  private onConnectionState(state: string): void {
    const previous = this.connectionState;
    this.connectionState = state;
    if (this.isConnecting()) {
      this.resumeConnecting();
      return;
    }
    if (state === 'connectionStateReady' || state === 'connectionStateUpdating' ||
      state === 'connectionStateWaitingForNetwork') {
      this.proxyConnectPending = false;
      if (state !== 'connectionStateWaitingForNetwork') {
        this.lastAttemptedProxyId = -1;
        this.switchAttempts = 0;
      }
      this.cancelWork();
      if (state === 'connectionStateReady' && previous !== state) {
        this.refreshProxyList();
      }
    }
  }

  private isConnecting(): boolean {
    return this.connectionState === 'connectionStateConnectingToProxy' ||
      this.connectionState === 'connectionStateConnecting';
  }

  private resumeConnecting(): void {
    // Reconnects need no new manual selection. Unknown lists are checked by
    // trySwitch before enabling anything, including a direct session.
    this.proxyConnectPending = this.isConnecting();
    this.armIfNeeded();
  }

  private onNetworkState(network: string): void {
    const available = network !== 'none';
    const recovered = !this.hadNetwork && available;
    const changed = this.networkType !== network;
    this.networkType = network;
    this.hadNetwork = available;
    if (!available) {
      // Invalidate old list reads too: their replies must not switch proxies after
      // the network comes back. Recovery starts a fresh, full delay.
      this.cancelWork();
    } else if (recovered || (changed && this.switchingToken !== -1)) {
      // 换了网络就是换了一批"哪条通"的事实，上一轮试过的那些不算数了。
      this.switchAttempts = 0;
      this.cancelWork();
      this.resumeConnecting();
    }
  }

  private autoSwitchOn(): boolean {
    // PROXY_AUTO_SWITCH_AVAILABLE 是总闸：关掉时存量的 proxyAutoSwitch=true
    // 也一概不认——这个开关按"能整体撤回"设计，撤的时候不许有残留生效。
    return this.available() && (AppStorage.get<boolean>(KEY_PROXY_AUTO_SWITCH) ?? false);
  }

  // 前后台切换。巡检是常驻的 30 秒定时器，后台必须整条停掉——只靠 pollOnce 里
  // 那个 foreground() 判断的话，定时器照样每 30 秒醒一次，白耗电。
  foregroundChanged(value: boolean): void {
    this.foreground = value;
    this.syncHealthMonitor();
  }

  private canArm(): boolean {
    if (!this.isConnecting() || !this.networkAvailable()) { return false; }
    if (!this.autoSwitchOn() || !this.proxyConnectPending || this.client === null) {
      return false;
    }
    if (!this.listKnown) { return true; }
    if (this.proxyCount < 1) { return false; }
    // 一圈 = 所有代理 + 直链。绕完了还连不上就不再加压，等 Ready/换网。
    return this.switchAttempts < Math.max(2, this.proxyCount + 1);
  }

  private armIfNeeded(): void {
    if (!this.canArm() || this.timer !== -1 || this.switchingToken !== -1) { return; }
    const delaySeconds = normalizeProxySwitchDelay(
      AppStorage.get<number>(KEY_PROXY_SWITCH_DELAY_SEC) ?? 0
    );
    const token = ++this.generation;
    this.timer = this.clock.setTimeout((): void => {
      if (this.generation !== token) { return; }
      this.timer = -1;
      this.trySwitch(token);
    }, delaySeconds * 1000);
  }

  private cancelWork(): void {
    this.probeRace?.cancel();
    this.probeRace = undefined;
    this.generation++;
    this.switchingToken = -1;
    if (this.timer !== -1) {
      this.clock.clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private isCurrent(target: TdClient, token: number): boolean {
    return this.client === target && this.generation === token;
  }

  private canContinueSwitch(target: TdClient, token: number): boolean {
    return this.isCurrent(target, token) && this.canArm() && this.networkAvailable();
  }

  private networkAvailable(): boolean {
    return (AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other') !== 'none';
  }

  private async listProxies(target: TdClient): Promise<ProxyAutoSwitchEntry[]> {
    const result = await send(target, { '@type': 'getProxies' } as TdRequest, 20000);
    const raw = (result['proxies'] as TdObject[] | undefined) ?? [];
    return raw.map((entry: TdObject): ProxyAutoSwitchEntry => ({
      id: (entry['id'] as number | undefined) ?? 0,
      isEnabled: (entry['is_enabled'] as boolean | undefined) ?? false
    }));
  }

  private selectRoute(target: TdClient, proxyId: number): Promise<void> {
    const request: TdRequest = { '@type': proxyId === 0 ? 'disableProxy' : 'enableProxy' };
    if (proxyId > 0) { request['proxy_id'] = proxyId; }
    return send(target, request, 20000).then((): void => {});
  }

  private applyProxyList(entries: ProxyAutoSwitchEntry[], manual: boolean): void {
    const nextActive = entries.find(
      (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
    )?.id ?? 0;
    const activeChanged = this.listKnown && nextActive !== this.activeProxyId;
    if (manual || activeChanged) { this.lastAttemptedProxyId = -1; }
    this.listKnown = true;
    this.proxyCount = entries.length;
    this.activeProxyId = nextActive;
    this.proxyConnectPending = this.isConnecting();
    if (manual || activeChanged || entries.length < 1) { this.cancelWork(); }
    this.armIfNeeded();
  }

  private async refreshProxyList(): Promise<void> {
    const target = this.client;
    if (target === null) { return; }
    const sequence = ++this.listSequence;
    try {
      const entries = await this.listProxies(target);
      if (this.client !== target || sequence !== this.listSequence) { return; }
      this.applyProxyList(entries, false);
      this.publishSelection(this.activeProxyId);
    } catch (caught) {
      if (this.client === target && sequence === this.listSequence) {
        logW(`[proxy] automatic switch list refresh failed: ${(caught as Error).message}`);
      }
    }
  }

  private async trySwitch(token: number): Promise<void> {
    const target = this.client;
    if (target === null || !this.canContinueSwitch(target, token)) {
      return;
    }
    this.switchingToken = token;
    try {
      const initial = await this.listProxies(target);
      if (!this.canContinueSwitch(target, token)) { return; }
      const activeId = initial.find(
        (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
      )?.id ?? 0;
      if (initial.length < 1 ||
        (this.listKnown && activeId !== this.activeProxyId)) {
        this.applyProxyList(initial, false);
        this.publishSelection(this.activeProxyId);
        return;
      }
      this.listKnown = true;
      this.proxyCount = initial.length;
      this.activeProxyId = activeId;
      this.publishSelection(activeId);
      // 顺序由 tcping 决定（快的在前、正在失败的沉底），轮转规则仍归
      // orderedProxyCandidateIds：从上次那项的下一项开始、绕一圈、跳过在用的那个。
      const candidates = orderedProxyCandidateIds(this.health.sortedForSwitch(initial), activeId,
        this.lastAttemptedProxyId >= 0 ? this.lastAttemptedProxyId : activeId);
      if (candidates.length === 0) { return; }
      const race = new ProxyCandidateRace(this.clock);
      this.probeRace = race;
      const candidateId = await race.run(candidates, this.probe);
      if (this.probeRace === race) { this.probeRace = undefined; }
      if (candidateId === undefined || !this.canContinueSwitch(target, token)) { return; }
      // A successful probe is not ownership of the route. Recheck selection and
      // deletion after probing, before enabling the winning candidate once.
      const latest = await this.listProxies(target);
      if (!this.canContinueSwitch(target, token)) { return; }
      const latestActive = latest.find(
        (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
      )?.id ?? 0;
      if (latestActive !== activeId || latest.length < 1) {
        this.applyProxyList(latest, false);
        this.publishSelection(this.activeProxyId);
        return;
      }
      if (candidateId !== 0 && !latest.some((entry: ProxyAutoSwitchEntry): boolean => entry.id === candidateId)) {
        return;
      }
      this.lastAttemptedProxyId = candidateId;
      this.switchAttempts++;
      this.listSequence++;
      this.invalidateSelection();
      const intent = this.selectionIntent;
      try {
        await this.selectRoute(target, candidateId);
      } catch (caught) {
        // A timeout does not prove TDLib rejected the change. Finish confirming
        // the actual selection before starting another full waiting window.
        if (this.client === target && this.selectionIntent === intent) { await this.refreshProxyList(); }
        throw caught as Error;
      }
      if (this.client !== target || this.selectionIntent !== intent) { return; }
      // Ready/Updating may have cancelled the timer before this reply arrived.
      this.listSequence++;
      this.activeProxyId = candidateId;
      this.proxyConnectPending = this.isConnecting();
      this.publishSelection(candidateId);
      logI(`[proxy] automatically switched proxy ${activeId} -> ${candidateId}`);
    } catch (caught) {
      logW(`[proxy] automatic switch attempt failed: ${(caught as Error).message}`);
    } finally {
      // A cancelled attempt can finish after another network/account has
      // started switching. It must not release that attempt's lock or timer.
      if (this.switchingToken === token) {
        this.switchingToken = -1;
        this.armIfNeeded();
      }
    }
  }
}

export const proxyAutoSwitchService: ProxyAutoSwitchService = new ProxyAutoSwitchService();
