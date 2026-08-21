import { connection } from '@kit.NetworkKit';
import { radio } from '@kit.TelephonyKit';
import { getTdClient, isReady } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { KEY_CURRENT_NETWORK_TYPE } from '../store/AppSettings';
import { logW } from '../util/log';

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
  const normalized = network === 'wifi' || network === 'mobile' || network === 'roaming' ||
    network === 'none' ? network : 'other';
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

async function classify(capabilities: connection.NetCapabilities): Promise<string> {
  const bearers: connection.NetBearType[] = capabilities.bearerTypes ?? [];
  if (bearers.indexOf(connection.NetBearType.BEARER_WIFI) >= 0) { return 'wifi'; }
  if (bearers.indexOf(connection.NetBearType.BEARER_CELLULAR) >= 0) {
    return cellularType();
  }
  return bearers.length > 0 ? 'other' : 'none';
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
