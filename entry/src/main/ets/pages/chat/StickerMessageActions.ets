// 贴纸消息上的两个动作（看合集、收藏切换）的逻辑落点。ChatPage 只留接线：
// 取到消息、调这里、按返回值弹提示。
import { MessageEntry } from '../../store/MessageEntry';
import { isFavoriteSticker, setFavoriteSticker } from '../../store/FavoriteStickers';
import { stickerSourceFileId } from '../../util/stickerSetItems';

// 这条消息能打开的合集 id（'' = 不是贴纸，或它不属于任何合集）。
export function stickerSetIdForMessage(entry: MessageEntry | null): string {
  return entry === null || entry.contentType !== 'sticker' ? '' : entry.stickerSetId;
}

// 这条消息里可收藏的贴纸源文件（0 = 收藏不了：不是贴纸，或动态贴纸的源文件
// 还没下载出来）。
export function favoriteFileIdForMessage(entry: MessageEntry | null): number {
  if (entry === null) {
    return 0;
  }
  return stickerSourceFileId(
    entry.contentType, entry.stickerFileId, entry.photoFileId, entry.stickerFormat);
}

// 翻面。resolve 出来的是**新的**收藏状态，调用方据此选提示语；
// 收藏不了或请求失败都走 reject。
export function toggleFavoriteForMessage(entry: MessageEntry | null): Promise<boolean> {
  const fileId: number = favoriteFileIdForMessage(entry);
  if (fileId === 0) {
    return Promise.reject(new Error('sticker source file unavailable'));
  }
  const next: boolean = !isFavoriteSticker(fileId);
  return setFavoriteSticker(fileId, next).then((): boolean => next);
}
