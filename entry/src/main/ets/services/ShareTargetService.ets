import { common } from '@kit.AbilityKit';
import { ChatEntry } from '../store/ChatEntry';
import { getChatStore } from '../tdkit/Globals';
import {
  SHARE_TARGET_LIMIT, ShareTarget, orderShareTargets
} from '../util/shareTargets';
import { onRecentOutgoingChanged, recentOutgoingChats } from '../util/recentOutgoing';
import {
  clearShareTargetSnapshot, initShareSnapshot, writeShareTargetSnapshot
} from './ShareTargetSnapshot';
import { donateShareTargets } from './ShareContactDonation';

// 把「发给谁」的候选名单持续写到磁盘上，供分享面板里的扩展进程读。
//
// 【为什么要持续写】用户在系统分享面板里点我们的图标时，扩展进程是**冷起**的：
// 没有登录态、没有 TDLib、没有 ChatStore。它只有几百毫秒把界面画出来，
// 不可能现场去连服务器。所以名单必须是主应用平时就攒好的。
//
// 【写的频率】会话列表每来一条消息就会重排，跟着写盘是浪费。这里只在两种
// 时机写：会话列表变化（节流到 REFRESH_MIN_INTERVAL_MS 一次）、以及"我主动
// 发过消息"的名单变化（那才是排序真正的依据）。

// 两次写盘的最小间隔。名单本身变化很慢——用户不会在 10 秒内换一批常聊的人。
const REFRESH_MIN_INTERVAL_MS: number = 10000;

let unsubChats: (() => void) | null = null;
let unsubRecent: (() => void) | null = null;
let lastWriteAt: number = 0;
let pending: boolean = false;
let lastPayload: string = '';
// 捐献要 BaseContext。由 startShareTargetService 传进来存着。
let donationContext: common.BaseContext | null = null;

function currentTargets(): ShareTarget[] {
  const chats: ChatEntry[] = getChatStore().getChats('main');
  return orderShareTargets(chats, recentOutgoingChats(), SHARE_TARGET_LIMIT);
}

// 名单内容没变就不写盘。会话列表一天要重排上千次，其中绝大多数不影响前 12 名。
function fingerprintOf(targets: ShareTarget[]): string {
  return targets.map((t: ShareTarget): string => `${t.chatId}:${t.title}:${t.avatarPath}`).join('|');
}

function writeNow(): void {
  const targets: ShareTarget[] = currentTargets();
  const print: string = fingerprintOf(targets);
  lastWriteAt = Date.now();
  pending = false;
  // **空名单绝不写盘。** 冷启动时订阅会立刻回调一次，那一刻 ChatStore 还是空的
  // ——写下去就是把上一次跑攒好的快照抹成空的，分享面板从此没有推荐可显示，
  // 直到用户主动打开一次应用。空名单等于"还不知道"，不是"没有"。
  if (targets.length === 0 || print === lastPayload) {
    return;
  }
  lastPayload = print;
  writeShareTargetSnapshot(targets);
  // 顺带捐献给意图框架，让这几个人出现在系统分享面板的头像那一排。
  // 大概率会因为"应用未注册意图"失败并自动停用，见 ShareContactDonation。
  if (donationContext !== null) {
    donateShareTargets(donationContext, targets);
  }
}

// 节流：间隔没到就挂一个定时器，到点再写一次最新的。
function scheduleRefresh(): void {
  if (pending) {
    return;
  }
  const since: number = Date.now() - lastWriteAt;
  if (since >= REFRESH_MIN_INTERVAL_MS) {
    writeNow();
    return;
  }
  pending = true;
  setTimeout((): void => {
    if (pending) {
      writeNow();
    }
  }, REFRESH_MIN_INTERVAL_MS - since);
}

// 主进程启动时调一次。filesDir 必须是**应用级**目录：扩展进程要读同一个文件。
export function startShareTargetService(filesDir: string,
  context: common.BaseContext | null = null): void {
  initShareSnapshot(filesDir);
  donationContext = context;
  if (unsubChats === null) {
    unsubChats = getChatStore().subscribe((): void => scheduleRefresh(), 'main');
  }
  if (unsubRecent === null) {
    unsubRecent = onRecentOutgoingChanged((): void => scheduleRefresh());
  }
}

export function stopShareTargetService(): void {
  if (unsubChats !== null) {
    unsubChats();
    unsubChats = null;
  }
  if (unsubRecent !== null) {
    unsubRecent();
    unsubRecent = null;
  }
  pending = false;
}

// 退出登录/切账号：快照里是上一个账号的会话标题，必须抹掉。
//
// `force` 是给"确实退登了"用的。不带 force 时只在**本进程真的写过**名单的
// 前提下才删——冷启动时 tdSessionEpoch 也会跳一次，那时候删等于每次开机都
// 把快照清空，分享面板在用户打开应用之前永远是空的。
export function resetShareTargets(force: boolean = false): void {
  const wrote: boolean = lastPayload !== '';
  lastPayload = '';
  lastWriteAt = 0;
  pending = false;
  if (force || wrote) {
    clearShareTargetSnapshot();
  }
}
