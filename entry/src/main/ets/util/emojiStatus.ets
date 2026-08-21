import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from './log';

// Resolve a user's premium emoji status (user.emoji_status) into a local
// sticker file. Handles both TDLib shapes: emoji_status.custom_emoji_id
// (older) and emoji_status.type.custom_emoji_id (newer). The callback fires
// once with the downloaded path and format ('tgs' | 'webm' | 'webp').
export function resolveEmojiStatus(es: TdObject | undefined,
  cb: (path: string, format: string) => void): void {
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
  getTdClient().send(req).then((res: TdObject) => {
    const stickers = (res['stickers'] as TdObject[] | undefined) ?? [];
    if (stickers.length === 0) {
      return;
    }
    const st = stickers[0];
    const fmt = st['format'] as TdObject | undefined;
    const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
    const format = fmtName === 'stickerFormatWebp' ? 'webp'
      : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
    const file = st['sticker'] as TdObject | undefined;
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
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
        cb(path, format);
      }
    }).catch((e: TdError) => {
      logE(`resolveEmojiStatus.download failed: ${e.message}`);
    });
  }).catch((e: TdError) => {
    logE(`resolveEmojiStatus.getCustomEmojiStickers failed: ${e.message}`);
  });
}
