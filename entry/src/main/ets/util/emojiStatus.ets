import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from './log';
import { remoteUniqueIdOf } from './stickerSetItems';
import { emojiStatusFramesCached } from '../services/emojiStatusFrames';

// Resolve a user's premium emoji status (user.emoji_status) into a local
// sticker file. Handles both TDLib shapes: emoji_status.custom_emoji_id
// (older) and emoji_status.type.custom_emoji_id (newer). The callback fires
// once with the downloaded path and format ('tgs' | 'webm' | 'webp'), plus the
// file's remote.unique_id. webm 状态的帧缓存已在盘上时不下载，path 给 ''、只给 ID
// （2026-10-10，见 emojiStatusSkipsDownload）。
// 一个 emojiStatus 对象里的 custom_emoji_id，两种 schema 都认：
//   新：emojiStatus.type(emojiStatusTypeCustomEmoji).custom_emoji_id
//   老：emojiStatus.custom_emoji_id
// 捆绑的 TDLib 是"半新"的（poll / 媒体包装都是混合形状），getRecent /
// getDefaultEmojiStatuses 回的仍是老形状——表情状态页原来只认新的，于是
// 会员打开页面只有一个「清除当前状态」（issue #120 的后半）。认不出返回 ''。
export function customEmojiIdOfStatus(es: TdObject | undefined): string {
  if (es === undefined || es === null) {
    return '';
  }
  const nested = es['type'] as TdObject | undefined;
  const raw: Object | undefined = (nested !== undefined && nested !== null)
    ? nested['custom_emoji_id'] : es['custom_emoji_id'];
  const id: string = raw === undefined || raw === null ? '' : `${raw}`;
  return id === 'undefined' || id === '0' ? '' : id;
}

// getRecentEmojiStatuses / getDefaultEmojiStatuses 回包里的 custom_emoji_id 列表，
// 两种 schema 都认：
//   新：emojiStatuses { emoji_statuses: [emojiStatus…] }
//   老：emojiStatuses { custom_emoji_ids: [int64…] }   ← 捆绑的 TDLib 回的是这个
// 表情状态页原来只读 emoji_statuses，老形状下拿到空数组，页面只剩「清除当前状态」
// （issue #120，会员打开也一样）。
// The bundled libtdjson reads `emojiStatus.custom_emoji_id` flat (pre-emojiStatusType
// schema) while current TDLib reads `emojiStatus.type.custom_emoji_id`. Each parser
// ignores the field it does not know, so carrying both makes setEmojiStatus work on
// either — sending only the nested form set an id of 0, i.e. silently cleared the status.
export function buildEmojiStatusValue(customEmojiId: string): TdObject | undefined {
  if (customEmojiId === '') {
    return undefined;
  }
  const type: TdObject = { '@type': 'emojiStatusTypeCustomEmoji' };
  type['custom_emoji_id'] = customEmojiId;
  const status: TdObject = { '@type': 'emojiStatus' };
  status['custom_emoji_id'] = customEmojiId;
  status['type'] = type;
  return status;
}

export function emojiStatusIdsOf(result: TdObject | undefined): string[] {
  const ids: string[] = [];
  if (result === undefined || result === null) {
    return ids;
  }
  const push = (id: string): void => {
    if (id !== '' && ids.indexOf(id) < 0) {
      ids.push(id);
    }
  };
  const statuses = result['emoji_statuses'] as TdObject[] | undefined;
  if (statuses !== undefined && statuses !== null) {
    for (const es of statuses) {
      push(customEmojiIdOfStatus(es));
    }
  }
  const rawIds = result['custom_emoji_ids'] as Object[] | undefined;
  if (rawIds !== undefined && rawIds !== null) {
    for (const raw of rawIds) {
      const id: string = raw === undefined || raw === null ? '' : `${raw}`;
      push(id === '0' ? '' : id);
    }
  }
  return ids;
}

// sticker.format → 'tgs' | 'webp' | 'webm'（认不出按 webm，与各处原来的写法一致）。
export function stickerFormatOf(st: TdObject): string {
  const fmt = st['format'] as TdObject | undefined;
  const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
  return fmtName === 'stickerFormatWebp' ? 'webp' : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
}

// 表情状态能不能不下载源文件、直接从帧缓存播。只有 webm 有按唯一 ID 的帧缓存
// （TGS 的帧缓存按源文件命名，要先有文件）。framesCached 由调用方查
// （services/emojiStatusFrames），这里只管规则，可单测。
export function emojiStatusSkipsDownload(format: string, uid: string, framesCached: boolean): boolean {
  return format === 'webm' && uid !== '' && framesCached;
}

// 表情状态要不要画：有本地文件，或者靠帧缓存播（没路径但有 ID）。
export function emojiStatusVisible(path: string, uid: string): boolean {
  return path !== '' || uid !== '';
}

export function resolveEmojiStatus(es: TdObject | undefined,
  cb: (path: string, format: string, uid: string) => void): void {
  if (es === undefined) {
    return;
  }
  const nestedType = es['type'] as TdObject | undefined;
  const rawId = (nestedType !== undefined ? nestedType['custom_emoji_id'] : undefined)
    ?? es['custom_emoji_id'];
  const ceId = rawId !== undefined ? `${rawId}` : '';
  if (ceId === '' || ceId === '0') {
    return;
  }
  const req: TdRequest = { '@type': 'getCustomEmojiStickers' };
  req['custom_emoji_ids'] = [ceId];
  getTdClient().send(req).then(async (res: TdObject): Promise<void> => {
    const stickers = (res['stickers'] as TdObject[] | undefined) ?? [];
    if (stickers.length === 0) {
      return;
    }
    const st = stickers[0];
    const format = stickerFormatOf(st);
    const file = st['sticker'] as TdObject | undefined;
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      return;
    }
    const uid: string = format === 'webm' ? remoteUniqueIdOf(file) : '';
    if (emojiStatusSkipsDownload(format, uid, await emojiStatusFramesCached(uid))) {
      cb('', format, uid);
      return;
    }
    const dl: TdRequest = { '@type': 'downloadFile' };
    dl['file_id'] = fileId;
    dl['priority'] = 1;
    dl['synchronous'] = true; // emoji stickers are tiny
    getTdClient().send(dl).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path !== '') {
        cb(path, format, uid);
      }
    }).catch((e: TdError) => {
      logE(`resolveEmojiStatus.download failed: ${e.message}`);
    });
  }).catch((e: TdError) => {
    logE(`resolveEmojiStatus.getCustomEmojiStickers failed: ${e.message}`);
  });
}
