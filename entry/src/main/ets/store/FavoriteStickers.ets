// 收藏贴纸的单一入口：长按菜单读这里，点击写这里。
//
// 模块级单例而不是挂在 MessageStore 上——收藏表是**账号级**的（换会话不变），
// 挂在会话 store 上等于每进一个会话重拉一次。切账号由 reset() 清空。
import { getTdClient } from '../tdkit/Globals';
import { TdObject } from '../tdkit/TdTypes';
import { FavoriteStickerCache } from '../util/favoriteStickerCache';
import { addFavoriteSticker, getFavoriteStickers, removeFavoriteSticker } from './StickerApi';
import { logE } from '../util/log';

const cache: FavoriteStickerCache = new FavoriteStickerCache();
let loading: boolean = false;

// 拉一次整表。重复调用只发一次请求；失败不抛（菜单照常能开，只是标签可能是
// "添加到收藏"，而添加是幂等的）。
export function primeFavoriteStickers(): void {
  if (cache.loaded() || loading) {
    return;
  }
  loading = true;
  getFavoriteStickers().then((stickers: TdObject[]): void => {
    const ids: number[] = [];
    for (const st of stickers) {
      const file = st['sticker'] as TdObject | undefined;
      const id: number = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      if (id !== 0) {
        ids.push(id);
      }
    }
    cache.replaceAll(ids);
    loading = false;
  }).catch((e: Error): void => {
    loading = false;
    logE(`FavoriteStickers.prime failed: ${e.message}`);
  });
}

export function isFavoriteSticker(fileId: number): boolean {
  return cache.has(fileId);
}

// 本地先翻面再发请求；失败退回原值并把错误交给调用方提示。
export async function setFavoriteSticker(fileId: number, favorite: boolean): Promise<void> {
  if (fileId === 0) {
    return;
  }
  cache.set(fileId, favorite);
  try {
    if (favorite) {
      await addFavoriteSticker(fileId);
    } else {
      await removeFavoriteSticker(fileId);
    }
  } catch (e) {
    cache.set(fileId, !favorite);
    throw new Error((e as Error).message);
  }
}

// 账号切换：上一个账号的收藏表不能带到下一个账号。
export function resetFavoriteStickers(): void {
  cache.replaceAll([]);
}
