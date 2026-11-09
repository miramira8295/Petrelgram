import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { accountRegistry } from '../tdkit/AccountRegistry';
import {
  findMusicBotSent, forgetMusicBotSent, MusicBotSentEntry, parseMusicBotSent,
  rememberMusicBotSent, serializeMusicBotSent
} from '../util/musicBotSentModel';
import { logE } from '../util/log';

// 「机器人搜来的歌已经发过哪些」的存取（2026-09-20）。判断全在
// util/musicBotSentModel，这里只管按账号读写 preferences、写入去抖。
//
// 结构与 MusicCollectionStore 一模一样（模块级单例、按槽位分键、400ms 去抖），
// 理由也一样：这是账号级的东西，换页面不能丢，多账号不能串。

const STORE_NAME: string = 'petrel_music_bot_sent';
const PERSIST_DEBOUNCE_MS: number = 400;

let entries: MusicBotSentEntry[] = [];
let loadedSlot: string = '';
let prefs: preferences.Preferences | null = null;
let loading: Promise<void> | null = null;
let persistTimer: number = -1;

function slotKey(slot: string): string {
  return `botSent@${slot}`;
}

function readSlot(p: preferences.Preferences, slot: string): MusicBotSentEntry[] {
  return parseMusicBotSent(p.getSync(slotKey(slot), '') as string);
}

function schedulePersist(): void {
  const p: preferences.Preferences | null = prefs;
  if (p === null) {
    return;
  }
  if (persistTimer !== -1) {
    clearTimeout(persistTimer);
  }
  const slot: string = loadedSlot;
  persistTimer = setTimeout((): void => {
    persistTimer = -1;
    p.putSync(slotKey(slot), serializeMusicBotSent(entries));
    p.flush().catch((e: Object): void => {
      logE(`MusicBotSentStore flush failed: ${JSON.stringify(e)}`);
    });
  }, PERSIST_DEBOUNCE_MS);
}

// 账号变了换一份。先把手上这份落盘，否则切账号会吞掉去抖窗口里的最后一次改动。
function syncSlot(): void {
  const p: preferences.Preferences | null = prefs;
  const slot: string = accountRegistry.activeSlotId();
  if (p === null || slot === loadedSlot) {
    return;
  }
  if (persistTimer !== -1) {
    clearTimeout(persistTimer);
    persistTimer = -1;
    p.putSync(slotKey(loadedSlot), serializeMusicBotSent(entries));
  }
  loadedSlot = slot;
  entries = readSlot(p, slot);
}

export function ensureMusicBotSent(context: common.Context): Promise<void> {
  if (prefs !== null) {
    syncSlot();
    return Promise.resolve();
  }
  if (loading !== null) {
    return loading;
  }
  loading = preferences.getPreferences(context, STORE_NAME).then(
    (p: preferences.Preferences): void => {
      prefs = p;
      loadedSlot = accountRegistry.activeSlotId();
      entries = readSlot(p, loadedSlot);
    }).catch((e: Object): void => {
      logE(`MusicBotSentStore init failed: ${JSON.stringify(e)}`);
    });
  return loading;
}

// 这个结果发过没有。'' = 没发过（或者记录已被清掉）。
export function musicBotSentKey(resultId: string): string {
  syncSlot();
  return findMusicBotSent(entries, resultId);
}

export function rememberBotSent(resultId: string, trackKey: string, now: number): void {
  syncSlot();
  entries = rememberMusicBotSent(entries, resultId, trackKey, now);
  schedulePersist();
}

// 那条消息取不回来了（用户删了）：忘掉，下次重发。
export function forgetBotSent(resultId: string): void {
  syncSlot();
  entries = forgetMusicBotSent(entries, resultId);
  schedulePersist();
}
