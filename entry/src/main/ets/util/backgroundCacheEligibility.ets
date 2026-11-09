import { MessageEntry } from '../store/MessageEntry';
import { CacheRecord } from './cacheRegistryModel';
import { DC_KIND_VIDEO } from './downloadCenterModel';
import { mediaEntryIsVideo } from './mediaEntryKind';

// 聊天里哪些消息能「后台缓存」、怎么拼缓存记录（2026-09-15：消息长按菜单、多选顶栏）。纯函数，不碰 TDLib。
// 只收视频（含已解锁的付费视频）：图片小、点开就下完了；动图走自动播放。已经下完的不再出这一项。

export function canBackgroundCache(entry: MessageEntry): boolean {
  return mediaEntryIsVideo(entry) && !entry.isAnimation && entry.videoFileId !== 0 && entry.videoPath === '';
}

export function selectionHasCacheableVideo(messages: MessageEntry[], ids: number[]): boolean {
  if (ids.length === 0) {
    return false;
  }
  const picked: Set<number> = new Set<number>(ids);
  return messages.some((m: MessageEntry): boolean => picked.has(m.id) && canBackgroundCache(m));
}

export function cacheRecordFromMessage(entry: MessageEntry, chatId: number): CacheRecord {
  return {
    fileId: entry.videoFileId, chatId: chatId, messageId: entry.id, kind: DC_KIND_VIDEO,
    name: entry.videoFileName, size: entry.videoFileSize, mimeType: entry.videoMimeType, preview: entry.text,
    background: true, addedAt: Date.now()
  };
}
