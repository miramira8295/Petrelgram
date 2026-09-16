import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { MessageEntry } from '../store/MessageEntry';
import { cacheRecordFromMessage, canBackgroundCache } from '../util/backgroundCacheEligibility';
import { startBackgroundCache } from './BackgroundCache';
import { str } from '../util/strings';
import { logW } from '../util/log';

// 从聊天里发起「后台缓存」（2026-09-15）：消息长按菜单（相册传整组）、多选顶栏共用；ChatPage 只接线。
// 进度在通知栏和气泡上（services/BackgroundCache 同时发到 mediaProgressChannel），完整列表在「设置 › 下载中心」。

export function cacheMessagesInBackground(context: common.UIAbilityContext, messages: MessageEntry[], ids: number[],
  chatId: number): void {
  startAll(context, messages, ids, chatId).then((started: number): void => {
    promptAction.showToast({
      message: started > 0 ? str('cp_background_cache_started', started) : str('cp_nothing_to_cache'),
      duration: 1800
    });
  });
}

async function startAll(context: common.UIAbilityContext, messages: MessageEntry[], ids: number[],
  chatId: number): Promise<number> {
  const picked: Set<number> = new Set<number>(ids);
  let started: number = 0;
  for (const m of messages) {
    if (!picked.has(m.id) || !canBackgroundCache(m)) {
      continue;
    }
    try {
      await startBackgroundCache(context, cacheRecordFromMessage(m, chatId));
      started++;
    } catch (e) {
      logW(`cacheMessagesInBackground(${m.id}) failed: ${JSON.stringify(e)}`);
    }
  }
  return started;
}
