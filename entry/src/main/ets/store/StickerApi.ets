import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { emojiStatusIdsOf } from '../util/emojiStatus';
import { logW } from '../util/log';

// Sticker library operations beyond the installed-packs list: the 最近/收藏
// sections, pack management (archive/reorder/local search) and emoji-driven
// suggestions. Parsing stays in the picker — these helpers return raw TDLib
// objects so the caller reuses its own sticker mapper.

function stickerTypeObject(stickerType: string): TdObject {
  return {
    '@type': stickerType === 'custom_emoji'
      ? 'stickerTypeCustomEmoji' : 'stickerTypeRegular'
  } as TdObject;
}

export async function getFavoriteStickers(): Promise<TdObject[]> {
  const result = await getTdClient().send({ '@type': 'getFavoriteStickers' } as TdRequest);
  return ((result['stickers'] as TdObject[] | undefined) ?? []).slice();
}

export async function getRecentStickers(attached: boolean = false): Promise<TdObject[]> {
  const request: TdRequest = { '@type': 'getRecentStickers' };
  request['is_attached'] = attached;
  const result = await getTdClient().send(request);
  return ((result['stickers'] as TdObject[] | undefined) ?? []).slice();
}

function stickerFileInput(fileId: number): TdObject {
  const input: TdObject = { '@type': 'inputFileId' };
  input['id'] = fileId;
  return input;
}

export async function addFavoriteSticker(fileId: number): Promise<void> {
  const request: TdRequest = { '@type': 'addFavoriteSticker' };
  request['sticker'] = stickerFileInput(fileId);
  await getTdClient().send(request);
}

export async function removeFavoriteSticker(fileId: number): Promise<void> {
  const request: TdRequest = { '@type': 'removeFavoriteSticker' };
  request['sticker'] = stickerFileInput(fileId);
  await getTdClient().send(request);
}

// Called after sending so the 最近 section reflects real usage.
export function rememberRecentSticker(fileId: number): void {
  const request: TdRequest = { '@type': 'addRecentSticker' };
  request['is_attached'] = false;
  request['sticker'] = stickerFileInput(fileId);
  getTdClient().send(request).catch((): void => {});
}

export async function removeRecentSticker(fileId: number): Promise<void> {
  const request: TdRequest = { '@type': 'removeRecentSticker' };
  request['is_attached'] = false;
  request['sticker'] = stickerFileInput(fileId);
  await getTdClient().send(request);
}

export async function clearRecentStickers(): Promise<void> {
  const request: TdRequest = { '@type': 'clearRecentStickers' };
  request['is_attached'] = false;
  await getTdClient().send(request);
}

// Stickers suggested for an emoji the user typed (official clients show these
// above the composer).
export async function getStickersForEmoji(
  emoji: string, stickerType: string = 'regular', limit: number = 20
): Promise<TdObject[]> {
  const request: TdRequest = { '@type': 'getStickers' };
  request['sticker_type'] = stickerTypeObject(stickerType);
  request['query'] = emoji;
  request['limit'] = limit;
  request['chat_id'] = 0;
  const result = await getTdClient().send(request, 10000);
  return ((result['stickers'] as TdObject[] | undefined) ?? []).slice();
}

export async function getArchivedStickerSets(stickerType: string = 'regular'): Promise<TdObject[]> {
  const request: TdRequest = { '@type': 'getArchivedStickerSets' };
  request['sticker_type'] = stickerTypeObject(stickerType);
  request['offset_sticker_set_id'] = '0';
  request['limit'] = 50;
  const result = await getTdClient().send(request, 12000);
  return ((result['sets'] as TdObject[] | undefined) ?? []).slice();
}

export async function searchInstalledStickerSets(
  query: string, stickerType: string = 'regular'
): Promise<TdObject[]> {
  const request: TdRequest = { '@type': 'searchInstalledStickerSets' };
  request['sticker_type'] = stickerTypeObject(stickerType);
  request['query'] = query;
  request['limit'] = 30;
  const result = await getTdClient().send(request, 12000);
  return ((result['sets'] as TdObject[] | undefined) ?? []).slice();
}

export async function searchStickerSets(
  query: string, stickerType: string = 'regular'
): Promise<TdObject[]> {
  const request: TdRequest = { '@type': 'searchStickerSets' };
  request['sticker_type'] = stickerTypeObject(stickerType);
  request['query'] = query;
  const result = await getTdClient().send(request, 12000);
  return ((result['sets'] as TdObject[] | undefined) ?? []).slice();
}

export async function reorderInstalledStickerSets(
  setIds: string[], stickerType: string = 'regular'
): Promise<void> {
  const request: TdRequest = { '@type': 'reorderInstalledStickerSets' };
  request['sticker_type'] = stickerTypeObject(stickerType);
  request['sticker_set_ids'] = setIds;
  await getTdClient().send(request);
}

// Archive (is_archived) or fully uninstall a pack.
export async function setStickerSetInstalled(
  setId: string, installed: boolean, archived: boolean = false
): Promise<void> {
  const request: TdRequest = { '@type': 'changeStickerSet' };
  request['set_id'] = setId;
  request['is_installed'] = installed;
  request['is_archived'] = archived;
  await getTdClient().send(request);
}

export function markTrendingViewed(setIds: string[]): void {
  if (setIds.length === 0) { return; }
  const request: TdRequest = { '@type': 'viewTrendingStickerSets' };
  request['sticker_set_ids'] = setIds;
  getTdClient().send(request).catch((): void => {});
}

// --- Emoji status (Premium): the animated emoji beside your name ---

// 两个都直接返回 custom_emoji_id 列表，新老 schema 由 emojiStatusIdsOf 兜住。
// 空时把回包的 keys 打出来：下次 schema 再变不用猜（issue #120 就是这么漏的）。
function emojiStatusIds(result: TdObject, what: string): string[] {
  const ids: string[] = emojiStatusIdsOf(result);
  if (ids.length === 0) {
    logW(`StickerApi.${what}: no ids; keys=${Object.keys(result).join(',')}`);
  }
  return ids;
}

export async function getDefaultEmojiStatuses(): Promise<string[]> {
  const result = await getTdClient().send(
    { '@type': 'getDefaultEmojiStatuses' } as TdRequest, 12000);
  return emojiStatusIds(result, 'getDefaultEmojiStatuses');
}

export async function getRecentEmojiStatuses(): Promise<string[]> {
  const result = await getTdClient().send(
    { '@type': 'getRecentEmojiStatuses' } as TdRequest, 12000);
  return emojiStatusIds(result, 'getRecentEmojiStatuses');
}

// customEmojiId '' clears the status.
export async function setEmojiStatus(customEmojiId: string): Promise<void> {
  const request: TdRequest = { '@type': 'setEmojiStatus' };
  if (customEmojiId !== '') {
    const status: TdObject = { '@type': 'emojiStatus' };
    const type: TdObject = { '@type': 'emojiStatusTypeCustomEmoji' };
    type['custom_emoji_id'] = customEmojiId;
    status['type'] = type;
    request['emoji_status'] = status;
  }
  await getTdClient().send(request, 12000);
}

export async function clearRecentEmojiStatuses(): Promise<void> {
  await getTdClient().send({ '@type': 'clearRecentEmojiStatuses' } as TdRequest);
}
