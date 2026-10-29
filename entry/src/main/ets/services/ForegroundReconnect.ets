import { getConnectionState, getTdClient, isReady } from '../tdkit/Globals';
import { dropRelayTunnelsBefore } from './HttpsProxyTransport';
import { logI, logW } from '../util/log';

// 回前台之后，TDLib 手上那些连接多半已经半死了：进程被冻结期间，代理那头
// 早把隧道掐了，而 TDLib 还觉得自己在线，要等心跳超时才肯重拨 —— 默认
// ping_interval 60 秒、ping_disconnect_delay 75 秒，最坏两分多钟。用户看到
// 的就是"一直连接中"。
//
// 我们能从这一侧直接掐：把旧隧道关掉，原生那边立刻读到 EOF，马上重拨，不必
// 等心跳超时。
//
// 两个边界必须守住：
//   1. 只掐"回前台那一刻之前就存在的"隧道。之后新建的是 TDLib 正在拨的，
//      掐掉等于把它刚接上的又拆了。
//   2. 只在 TDLib 确实卡在连接中时才掐。正常回前台它也短暂处于 Connecting，
//      这时候动刀只会凭空多一次重连。

const FIRST_CHECK_MS: number = 3000;
const SECOND_CHECK_MS: number = 9000;
const CONNECTING_STATES: string[] = [
  'connectionStateConnecting',
  'connectionStateConnectingToProxy'
];

let generation: number = 0;
let firstTimer: number = -1;
let secondTimer: number = -1;

function stuckConnecting(): boolean {
  return CONNECTING_STATES.indexOf(getConnectionState()) >= 0;
}

function dropStale(mark: number, attempt: number): void {
  if (!isReady() || !stuckConnecting()) { return; }
  const state: string = getConnectionState();
  const dropped: number = dropRelayTunnelsBefore(getTdClient(), mark);
  if (dropped > 0) {
    logW(`[Reconnect] attempt=${attempt} state=${state} dropped=${dropped} stale tunnel(s)`);
  }
}

// 每次回前台调用一次。mark 取调用时刻：比它早建的隧道才算"旧的"。
export function armForegroundReconnect(): void {
  cancelForegroundReconnect();
  const mark: number = Date.now();
  const current: number = generation;
  logI(`[Reconnect] armed grace=${FIRST_CHECK_MS}ms`);
  firstTimer = setTimeout((): void => {
    firstTimer = -1;
    if (current !== generation) { return; }
    dropStale(mark, 1);
  }, FIRST_CHECK_MS);
  secondTimer = setTimeout((): void => {
    secondTimer = -1;
    if (current !== generation) { return; }
    dropStale(mark, 2);
  }, SECOND_CHECK_MS);
}

// 切后台就取消：这段时间里 TDLib 的连接状态没有参考价值，而且进程随时会被
// 冻住，定时器本来也跑不完。
export function cancelForegroundReconnect(): void {
  generation++;
  if (firstTimer !== -1) { clearTimeout(firstTimer); firstTimer = -1; }
  if (secondTimer !== -1) { clearTimeout(secondTimer); secondTimer = -1; }
}
