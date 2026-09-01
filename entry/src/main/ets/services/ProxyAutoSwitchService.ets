import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_PROXY_AUTO_SWITCH, KEY_PROXY_SWITCH_DELAY_SEC
} from '../store/AppSettings';
import {
  normalizeProxySwitchDelay, orderedProxyCandidateIds, ProxySwitchCandidate
} from '../util/proxyAutoSwitch';
import { logI, logW } from '../util/log';

export interface ProxyAutoSwitchEntry extends ProxySwitchCandidate {
  isEnabled: boolean;
}

// One instance follows the active TDLib runtime. The timer must not belong to
// ProxyPage: leaving settings must not turn automatic failover off.
class ProxyAutoSwitchService {
  private client: TdClient | null = null;
  private unsubscribe: (() => void) | null = null;
  private timer: number = -1;
  private generation: number = 0;
  private listSequence: number = 0;
  private switching: boolean = false;
  private connectionState: string = '';
  private proxyConnectPending: boolean = false;
  private listKnown: boolean = false;
  private proxyCount: number = 0;
  private activeProxyId: number = 0;

  attach(target: TdClient): void {
    this.detach();
    this.client = target;
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
    this.client = null;
    this.connectionState = '';
    this.proxyConnectPending = false;
    this.listKnown = false;
    this.proxyCount = 0;
    this.activeProxyId = 0;
    this.listSequence++;
  }

  runtimeReady(target: TdClient): void {
    if (this.client === target) { this.refreshProxyList(); }
  }

  settingsChanged(): void {
    this.cancelWork();
    this.armIfNeeded();
  }

  proxyListChanged(entries: ProxyAutoSwitchEntry[]): void {
    this.listSequence++;
    this.applyProxyList(entries, true);
  }

  proxySelectionChanged(proxyId: number): void {
    this.activeProxyId = proxyId;
    this.proxyConnectPending = proxyId > 0;
    this.cancelWork();
    this.armIfNeeded();
  }

  private onConnectionState(state: string): void {
    const previous = this.connectionState;
    this.connectionState = state;
    if (state === 'connectionStateConnectingToProxy') {
      this.proxyConnectPending = true;
      this.armIfNeeded();
      return;
    }
    if (state === 'connectionStateReady' || state === 'connectionStateUpdating' ||
      state === 'connectionStateWaitingForNetwork') {
      this.proxyConnectPending = false;
      this.cancelWork();
      if (state === 'connectionStateReady' && previous !== state) {
        this.refreshProxyList();
      }
    }
    // connectionStateConnecting can follow ConnectingToProxy after the socket
    // opens. Keep the original timer until Ready/Updating confirms recovery.
  }

  private autoSwitchOn(): boolean {
    return AppStorage.get<boolean>(KEY_PROXY_AUTO_SWITCH) ?? false;
  }

  private canArm(): boolean {
    if (!this.autoSwitchOn() || !this.proxyConnectPending || this.client === null) {
      return false;
    }
    return !this.listKnown || (this.activeProxyId > 0 && this.proxyCount >= 2);
  }

  private armIfNeeded(): void {
    if (!this.canArm() || this.timer !== -1 || this.switching) { return; }
    const delaySeconds = normalizeProxySwitchDelay(
      AppStorage.get<number>(KEY_PROXY_SWITCH_DELAY_SEC) ?? 0
    );
    const token = ++this.generation;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.trySwitch(token);
    }, delaySeconds * 1000);
  }

  private cancelWork(): void {
    this.generation++;
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private isCurrent(target: TdClient, token: number): boolean {
    return this.client === target && this.generation === token;
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

  private pingProxy(target: TdClient, proxyId: number): Promise<void> {
    const request: TdRequest = { '@type': 'pingProxy' };
    request['proxy_id'] = proxyId;
    return target.send(request, 12000).then((result: TdObject): void => {
      const seconds = (result['seconds'] as number | undefined) ?? -1;
      if (!Number.isFinite(seconds) || seconds < 0) {
        throw new Error('invalid proxy ping result');
      }
    });
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
    this.listKnown = true;
    this.proxyCount = entries.length;
    this.activeProxyId = nextActive;
    if (nextActive === 0) { this.proxyConnectPending = false; }
    if (manual && activeChanged && nextActive > 0) {
      this.proxyConnectPending = this.connectionState === 'connectionStateConnectingToProxy';
    }
    if (manual || activeChanged || entries.length < 2) { this.cancelWork(); }
    this.armIfNeeded();
  }

  private refreshProxyList(): void {
    const target = this.client;
    if (target === null) { return; }
    const sequence = ++this.listSequence;
    this.listProxies(target).then((entries: ProxyAutoSwitchEntry[]): void => {
      if (this.client !== target || sequence !== this.listSequence) { return; }
      this.applyProxyList(entries, false);
    }).catch((caught: Error): void => {
      if (this.client === target && sequence === this.listSequence) {
        logW(`[proxy] automatic switch list refresh failed: ${caught.message}`);
      }
    });
  }

  private async trySwitch(token: number): Promise<void> {
    const target = this.client;
    if (target === null || !this.isCurrent(target, token) || !this.networkAvailable()) {
      return;
    }
    this.switching = true;
    try {
      const initial = await this.listProxies(target);
      if (!this.isCurrent(target, token) || !this.networkAvailable()) { return; }
      const active = initial.find(
        (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
      );
      if (active === undefined || initial.length < 2) {
        this.applyProxyList(initial, false);
        return;
      }
      this.listKnown = true;
      this.proxyCount = initial.length;
      this.activeProxyId = active.id;
      const candidates = orderedProxyCandidateIds(initial, active.id);
      for (const candidateId of candidates) {
        try {
          await this.pingProxy(target, candidateId);
        } catch (_caught) {
          if (!this.isCurrent(target, token) || !this.networkAvailable()) { return; }
          continue;
        }
        if (!this.isCurrent(target, token) || !this.networkAvailable()) { return; }
        // A manual selection may have landed while pingProxy was in flight.
        // Re-read the enabled id immediately before mutating TDLib.
        const latest = await this.listProxies(target);
        if (!this.isCurrent(target, token)) { return; }
        const latestActive = latest.find(
          (entry: ProxyAutoSwitchEntry): boolean => entry.isEnabled
        )?.id ?? 0;
        if (latestActive !== active.id) { return; }
        await this.enableProxy(target, candidateId);
        if (!this.isCurrent(target, token)) { return; }
        this.activeProxyId = candidateId;
        this.proxyConnectPending = true;
        logI(`[proxy] automatically switched proxy ${active.id} -> ${candidateId}`);
        return;
      }
    } catch (caught) {
      logW(`[proxy] automatic switch attempt failed: ${(caught as Error).message}`);
    } finally {
      this.switching = false;
      // If every candidate was temporarily unavailable, retry after another
      // full delay while TDLib still reports the same unresolved connection.
      this.armIfNeeded();
    }
  }
}

export const proxyAutoSwitchService: ProxyAutoSwitchService = new ProxyAutoSwitchService();
