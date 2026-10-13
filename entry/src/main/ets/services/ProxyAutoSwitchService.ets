import { TdClient, TimerFns } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_PROXY_AUTO_SWITCH, KEY_PROXY_SWITCH_DELAY_SEC
} from '../store/AppSettings';
import {
  normalizeProxySwitchDelay, orderedProxyCandidateIds, ProxySwitchCandidate
} from '../util/proxyAutoSwitch';
import { logI, logW } from '../util/log';
import { subscribeNetworkType } from './NetworkStateService';

export type ProxyNetworkSubscription = (listener: (network: string) => void) => () => void;

export interface ProxyAutoSwitchEntry extends ProxySwitchCandidate {
  isEnabled: boolean;
}

// One instance follows the active TDLib runtime. The timer must not belong to
// ProxyPage: leaving settings must not turn automatic failover off.
export class ProxyAutoSwitchService {
  private clock: TimerFns;
  private subscribeNetwork: ProxyNetworkSubscription;
  private client: TdClient | null = null;
  private unsubscribe: (() => void) | null = null;
  private unsubscribeNetwork: (() => void) | null = null;
  private hadNetwork: boolean = true;
  private timer: number = -1;
  private generation: number = 0;
  private listSequence: number = 0;
  private switchingToken: number = -1;
  private connectionState: string = '';
  private proxyConnectPending: boolean = false;
  private listKnown: boolean = false;
  private proxyCount: number = 0;
  private activeProxyId: number = 0;
  private lastAttemptedProxyId: number = 0;
  // Selection ownership is independent of the failover timer: Ready may cancel
  // a timer before enableProxy's acknowledgement arrives.
  private selectionIntent: number = 0;
  private selectionRevision: number = 0;
  private confirmedProxyId: number = -1;
  private selectionListeners: Set<(proxyId: number) => void> = new Set();

  constructor(clock?: TimerFns, subscribeNetwork?: ProxyNetworkSubscription) {
    this.clock = clock ?? {
      setTimeout: (callback: () => void, ms: number): number => setTimeout(callback, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
    this.subscribeNetwork = subscribeNetwork ?? subscribeNetworkType;
  }

  attach(target: TdClient): void {
    this.detach();
    this.client = target;
    this.hadNetwork = this.networkAvailable();
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
    this.lastAttemptedProxyId = 0;
    this.listSequence++;
    this.invalidateSelection();
    this.selectionListeners.clear();
  }

  runtimeReady(target: TdClient): void {
    if (this.client === target) { this.refreshProxyList(); }
  }

  settingsChanged(): void {
    if (!this.autoSwitchOn()) { this.lastAttemptedProxyId = 0; }
    this.cancelWork();
    this.armIfNeeded();
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
    this.lastAttemptedProxyId = 0;
    // Selection is intent, not proof that TDLib is still connecting. Add/edit
    // acknowledgements can arrive after Ready/Updating; canArm checks the
    // actual connection state before starting another failover timer.
    this.proxyConnectPending = proxyId > 0;
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
      if (state !== 'connectionStateWaitingForNetwork') { this.lastAttemptedProxyId = 0; }
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
    this.proxyConnectPending = this.isConnecting() && (!this.listKnown || this.activeProxyId > 0);
    this.armIfNeeded();
  }

  private onNetworkState(network: string): void {
    const available = network !== 'none';
    const recovered = !this.hadNetwork && available;
    this.hadNetwork = available;
    if (!available) {
      // Invalidate old list reads too: their replies must not switch proxies after
      // the network comes back. Recovery starts a fresh, full delay.
      this.cancelWork();
    } else if (recovered) {
      this.resumeConnecting();
    }
  }

  private autoSwitchOn(): boolean {
    return AppStorage.get<boolean>(KEY_PROXY_AUTO_SWITCH) ?? false;
  }

  private canArm(): boolean {
    if (!this.isConnecting() || !this.networkAvailable()) { return false; }
    if (!this.autoSwitchOn() || !this.proxyConnectPending || this.client === null) {
      return false;
    }
    return !this.listKnown || (this.activeProxyId > 0 && this.proxyCount >= 2);
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
    const result = await target.send({ '@type': 'getProxies' } as TdRequest);
    const raw = (result['proxies'] as TdObject[] | undefined) ?? [];
    return raw.map((entry: TdObject): ProxyAutoSwitchEntry => ({
      id: (entry['id'] as number | undefined) ?? 0,
      isEnabled: (entry['is_enabled'] as boolean | undefined) ?? false
    }));
  }

  private enableProxy(target: TdClient, proxyId: number): Promise<void> {
    const request: TdRequest = { '@type': 'enableProxy' };
    request['proxy_id'] = proxyId;
    return target.send(request, 20000).then((): void => {});
  }

  private applyProxyList(entries: ProxyAutoSwitchEntry[], manual: boolean): void {
    const nextActive = entries.find(
      (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
    )?.id ?? 0;
    const activeChanged = this.listKnown && nextActive !== this.activeProxyId;
    if (manual || activeChanged) { this.lastAttemptedProxyId = 0; }
    this.listKnown = true;
    this.proxyCount = entries.length;
    this.activeProxyId = nextActive;
    this.proxyConnectPending = this.isConnecting() && nextActive > 0;
    if (manual || activeChanged || entries.length < 2) { this.cancelWork(); }
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
      const active = initial.find(
        (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
      );
      if (active === undefined || initial.length < 2 ||
        (this.listKnown && active.id !== this.activeProxyId)) {
        this.applyProxyList(initial, false);
        this.publishSelection(this.activeProxyId);
        return;
      }
      this.listKnown = true;
      this.proxyCount = initial.length;
      this.activeProxyId = active.id;
      this.publishSelection(active.id);
      // Re-read immediately before mutation. Select from the latest list so a
      // removed candidate cannot monopolize future attempts.
      const latest = await this.listProxies(target);
      if (!this.canContinueSwitch(target, token)) { return; }
      const latestActive = latest.find(
        (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
      )?.id ?? 0;
      if (latestActive !== active.id || latest.length < 2) {
        this.applyProxyList(latest, false);
        this.publishSelection(this.activeProxyId);
        return;
      }
      const candidates = orderedProxyCandidateIds(latest, latestActive,
        this.lastAttemptedProxyId > 0 ? this.lastAttemptedProxyId : latestActive);
      if (candidates.length === 0) { return; }
      const candidateId = candidates[0];
      // Advance even if enableProxy is rejected; no second enable in this round.
      this.lastAttemptedProxyId = candidateId;
      this.listSequence++;
      this.invalidateSelection();
      const intent = this.selectionIntent;
      try {
        await this.enableProxy(target, candidateId);
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
      logI(`[proxy] automatically switched proxy ${active.id} -> ${candidateId}`);
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
