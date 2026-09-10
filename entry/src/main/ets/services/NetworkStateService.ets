import { connection } from '@kit.NetworkKit';
import { radio } from '@kit.TelephonyKit';
import { getTdClient, isReady } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { KEY_CURRENT_NETWORK_TYPE } from '../store/AppSettings';
import { logW } from '../util/log';
import {
  BearerIds, NET_KIND_CELLULAR, NET_KIND_VPN, NET_KIND_WIFI, bearerKindOf, resolveThroughVpn
} from '../util/netBearer';

let monitor: connection.NetConnection | null = null;
let lastPublished: string = '';
let refreshSequence: number = 0;

function tdNetworkTypeOf(network: string): TdObject {
  if (network === 'wifi') { return { '@type': 'networkTypeWiFi' }; }
  if (network === 'roaming') { return { '@type': 'networkTypeMobileRoaming' }; }
  if (network === 'mobile') { return { '@type': 'networkTypeMobile' }; }
  if (network === 'none') { return { '@type': 'networkTypeNone' }; }
  return { '@type': 'networkTypeOther' };
}

function publish(network: string, forceTd: boolean = false): void {
  // 'vpn' = 默认网络是 VPN、且底下的物理承载没找到。留着这个值而不是并进 'other'：
  // 预取策略要区分"未知网络"和"VPN 之下不知是 Wi-Fi 还是蜂窝"（后者放行）。
  const normalized = network === 'wifi' || network === 'mobile' || network === 'roaming' ||
    network === 'none' || network === 'vpn' ? network : 'other';
  const changed = normalized !== lastPublished;
  lastPublished = normalized;
  AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, normalized);
  if ((!changed && !forceTd) || !isReady()) { return; }
  const request: TdRequest = { '@type': 'setNetworkType' };
  request['type'] = tdNetworkTypeOf(normalized);
  getTdClient().send(request).catch((caught: Error): void => {
    logW(`NetworkStateService.setNetworkType(${normalized}) failed: ${caught.message}`);
  });
}

async function cellularType(): Promise<string> {
  try {
    const state = await radio.getNetworkState();
    return state.isRoaming ? 'roaming' : 'mobile';
  } catch (caught) {
    logW(`NetworkStateService.getNetworkState failed: ${caught}`);
    return 'mobile';
  }
}

const BEARER_IDS: BearerIds = {
  wifi: connection.NetBearType.BEARER_WIFI as number,
  cellular: connection.NetBearType.BEARER_CELLULAR as number,
  vpn: connection.NetBearType.BEARER_VPN as number
};

function kindOfCapabilities(capabilities: connection.NetCapabilities): string {
  const bearers: number[] = (capabilities.bearerTypes ?? []).map(
    (b: connection.NetBearType): number => b as number);
  return bearerKindOf(bearers, BEARER_IDS);
}

// 默认网络是 VPN 时，在全部可用网络里找物理承载（判定见 util/netBearer）。
// 用户状态栏常年挂着 VPN，原来这里一律 'other'：视频预取 30/30 被拒、TDLib 也
// 一直被告知 networkTypeOther（2026-09-09 真机日志）。
async function physicalKindUnderVpn(): Promise<string> {
  try {
    const handles: connection.NetHandle[] = await connection.getAllNets();
    const kinds: string[] = [];
    for (const handle of handles) {
      if (handle.netId === 0) { continue; }
      try {
        kinds.push(kindOfCapabilities(await connection.getNetCapabilities(handle)));
      } catch (caught) {
        logW(`NetworkStateService.getNetCapabilities(${handle.netId}) failed: ${caught}`);
      }
    }
    return resolveThroughVpn(NET_KIND_VPN, kinds);
  } catch (caught) {
    logW(`NetworkStateService.getAllNets failed: ${caught}`);
    return NET_KIND_VPN;
  }
}

async function classify(capabilities: connection.NetCapabilities): Promise<string> {
  let kind: string = kindOfCapabilities(capabilities);
  if (kind === NET_KIND_VPN) {
    kind = await physicalKindUnderVpn();
  }
  if (kind === NET_KIND_WIFI) { return 'wifi'; }
  if (kind === NET_KIND_CELLULAR) { return cellularType(); }
  return kind; // 'vpn' | 'other' | 'none'
}

export function refreshNetworkState(forceTd: boolean = false): void {
  const sequence = ++refreshSequence;
  connection.hasDefaultNet().then((available: boolean): Promise<connection.NetHandle | null> => {
    if (!available) { return Promise.resolve(null); }
    return connection.getDefaultNet();
  }).then((handle: connection.NetHandle | null): Promise<connection.NetCapabilities | null> => {
    if (handle === null || handle.netId === 0) { return Promise.resolve(null); }
    return connection.getNetCapabilities(handle);
  }).then((capabilities: connection.NetCapabilities | null): Promise<string> => {
    if (capabilities === null) { return Promise.resolve('none'); }
    return classify(capabilities);
  }).then((network: string): void => {
    if (sequence === refreshSequence) { publish(network, forceTd); }
  }).catch((caught: Error): void => {
    if (sequence === refreshSequence) {
      logW(`NetworkStateService.refresh failed: ${caught.message}`);
      publish('other', forceTd);
    }
  });
}

export function beginNetworkMonitoring(): void {
  if (monitor !== null) {
    refreshNetworkState(true);
    return;
  }
  AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, 'other');
  const next = connection.createNetConnection();
  monitor = next;
  next.on('netAvailable', (): void => refreshNetworkState());
  next.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
    const sequence = ++refreshSequence;
    classify(info.netCap).then((network: string): void => {
      if (sequence === refreshSequence) { publish(network); }
    });
  });
  next.on('netLost', (): void => refreshNetworkState());
  next.on('netUnavailable', (): void => {
    refreshSequence++;
    publish('none');
  });
  next.register((error): void => {
    if (error !== undefined && error !== null && error.code !== 0) {
      logW(`NetworkStateService.register failed: ${error.message}`);
    }
    refreshNetworkState(true);
  });
}
