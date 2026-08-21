import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from './log';

const THUMB_PRIORITY: number = 1;

// 反应面板里的自定义 emoji 只需要一张静态小图，动画 TGS/WEBM 在 44vp 的格子
// 里既看不清也太吃资源，所以统一取缩略图；只有没有缩略图的静态 WEBP 才直接
// 用贴纸本体。返回 0 表示这枚 emoji 拿不到可显示的位图。
export function customEmojiThumbFileId(sticker: TdObject): number {
  const thumb = sticker['thumbnail'] as TdObject | undefined;
  const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
  const thumbId: number = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
  if (thumbId !== 0) {
    return thumbId;
  }
  const format = sticker['format'] as TdObject | undefined;
  const formatName: string = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
  if (formatName !== 'stickerFormatWebp') {
    return 0;
  }
  const file = sticker['sticker'] as TdObject | undefined;
  return file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
}

function customEmojiIdOf(sticker: TdObject): string {
  const fullType = sticker['full_type'] as TdObject | undefined;
  const raw = (fullType !== undefined ? fullType['custom_emoji_id'] : undefined)
    ?? sticker['custom_emoji_id'];
  return raw !== undefined ? `${raw}` : '';
}

function localPathOf(file: TdObject | undefined): string {
  const local = file !== undefined ? (file['local'] as TdObject | undefined) : undefined;
  if (local === undefined ||
    !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
    return '';
  }
  return (local['path'] as string | undefined) ?? '';
}

// 批量解析自定义 emoji id → 本地位图路径。每解析出一个就回调一次，调用方
// 可以先渲染占位、逐个替换，而不必等整批下载完成。
export function resolveCustomEmojiThumbs(customEmojiIds: string[],
  cb: (customEmojiId: string, path: string) => void): void {
  const ids: string[] = customEmojiIds.filter((id: string): boolean => id !== '' && id !== '0');
  if (ids.length === 0) {
    return;
  }
  const req: TdRequest = { '@type': 'getCustomEmojiStickers' };
  req['custom_emoji_ids'] = ids;
  getTdClient().send(req, 15000).then((res: TdObject): void => {
    const stickers = (res['stickers'] as TdObject[] | undefined) ?? [];
    stickers.forEach((sticker: TdObject, index: number): void => {
      // TDLib 通常在 full_type 里回带 id；万一缺失就按请求顺序兜底对齐。
      const id: string = customEmojiIdOf(sticker) !== '' ? customEmojiIdOf(sticker)
        : (index < ids.length ? ids[index] : '');
      const fileId: number = customEmojiThumbFileId(sticker);
      if (id === '' || fileId === 0) {
        return;
      }
      const cached: string = localPathOf(sticker['thumbnail'] !== undefined
        ? ((sticker['thumbnail'] as TdObject)['file'] as TdObject | undefined)
        : (sticker['sticker'] as TdObject | undefined));
      if (cached !== '') {
        cb(id, cached);
        return;
      }
      const download: TdRequest = { '@type': 'downloadFile' };
      download['file_id'] = fileId;
      download['priority'] = THUMB_PRIORITY;
      download['synchronous'] = true; // emoji 缩略图极小，同步等更简单
      getTdClient().send(download, 20000).then((file: TdObject): void => {
        const path: string = localPathOf(file);
        if (path !== '') {
          cb(id, path);
        }
      }).catch((e: TdError): void => {
        logE(`resolveCustomEmojiThumbs.download(${fileId}) failed: ${e.message}`);
      });
    });
  }).catch((e: TdError): void => {
    logE(`resolveCustomEmojiThumbs.getCustomEmojiStickers failed: ${e.message}`);
  });
}
