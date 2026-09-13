// getStickerSet 回包 → 可渲染的合集内容。纯解析，没有网络也没有 UI：
// 「点贴纸看合集」（issue 反馈①）要的那张面板，数据形状全在这里。
//
// 【为什么不复用 StickerPicker 的 StickerItem】选择器那一套带着"收藏/最近/
// 标签页/位置"等只有选择器才有的字段，而合集面板是只读的一屏。共用会把选择器
// 的模型拖进一个不需要它的页面，两边都难改。
import { TdObject } from '../tdkit/TdTypes';

export interface StickerSetItem {
  fileId: number;      // 贴纸源文件（发送用的就是它）
  thumbFileId: number; // 面板里真正画出来的那张栅格图（webp 贴纸就是它自己）
  thumbPath: string;   // 已在本地时的路径，'' 表示要下载
  format: string;      // 'webp' | 'tgs' | 'webm'
  emoji: string;
  width: number;
  height: number;
}

export interface StickerSetInfo {
  id: string;
  title: string;
  name: string;       // t.me/addstickers/<name>
  installed: boolean; // 归档的不算已添加
  count: number;
}

// 贴纸所属合集 id。TDLib 对"不属于任何合集"给的是 0（而不是缺字段），
// 所以 '0' 必须和缺字段一样当成"没有合集"，否则会打开一张空面板。
export function stickerSetIdOf(sticker: TdObject | undefined): string {
  if (sticker === undefined) {
    return '';
  }
  const raw = sticker['set_id'];
  if (raw === undefined || raw === null) {
    return '';
  }
  const id: string = `${raw}`;
  return id === '0' || id === '' ? '' : id;
}

function rasterThumb(sticker: TdObject): TdObject | undefined {
  const thumb = sticker['thumbnail'] as TdObject | undefined;
  if (thumb === undefined) {
    return undefined;
  }
  const format = thumb['format'] as TdObject | undefined;
  const name: string = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
  const isRaster: boolean = name === 'thumbnailFormatWebp' || name === 'thumbnailFormatJpeg'
    || name === 'thumbnailFormatPng' || name === 'thumbnailFormatGif';
  return isRaster ? (thumb['file'] as TdObject | undefined) : undefined;
}

function localPathOf(file: TdObject | undefined): string {
  if (file === undefined) {
    return '';
  }
  const local = file['local'] as TdObject | undefined;
  return local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
}

export function parseStickerSetItems(set: TdObject): StickerSetItem[] {
  const raw = (set['stickers'] as TdObject[] | undefined) ?? [];
  const out: StickerSetItem[] = [];
  for (const st of raw) {
    const file = st['sticker'] as TdObject | undefined;
    const fileId: number = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      continue;   // 没有源文件的条目画不出也发不出
    }
    const fmt = st['format'] as TdObject | undefined;
    const fmtName: string = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
    const format: string = fmtName === 'stickerFormatTgs' ? 'tgs'
      : (fmtName === 'stickerFormatWebm' ? 'webm' : 'webp');
    // 静态 webp 自己就是一张能直接画的图，不必再等缩略图；动态的只能靠缩略图
    // （面板里一屏几十个，不在这里起 Lottie/视频）。
    const thumbFile = format === 'webp' ? file : rasterThumb(st);
    out.push({
      fileId,
      thumbFileId: thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0,
      thumbPath: localPathOf(thumbFile),
      format,
      emoji: (st['emoji'] as string | undefined) ?? '',
      width: (st['width'] as number | undefined) ?? 512,
      height: (st['height'] as number | undefined) ?? 512
    });
  }
  return out;
}

export function parseStickerSetInfo(set: TdObject): StickerSetInfo {
  const installed: boolean = ((set['is_installed'] as boolean | undefined) ?? false)
    && !((set['is_archived'] as boolean | undefined) ?? false);
  return {
    id: `${set['id'] ?? ''}`,
    title: (set['title'] as string | undefined) ?? '',
    name: (set['name'] as string | undefined) ?? '',
    installed,
    count: ((set['stickers'] as TdObject[] | undefined) ?? []).length
  };
}

// 一条贴纸消息里"可发送/可收藏"的那个文件 id。
//
// 静态 webp 的源文件就挂在 photoFileId 上（stickerFileId 只在 tgs/webm 时才
// 填，见 formatMsgContent.stickerMsgContent），收藏接口要的是源文件而不是缩略
// 图——喂错了 TDLib 会收下一个不存在的贴纸，收藏夹里出现空格子。
export function stickerSourceFileId(
  contentType: string, stickerFileId: number, photoFileId: number, format: string
): number {
  if (contentType !== 'sticker') {
    return 0;
  }
  if (format === 'tgs' || format === 'webm') {
    return stickerFileId;   // 动态贴纸：photoFileId 是缩略图，不能拿去收藏
  }
  return stickerFileId !== 0 ? stickerFileId : photoFileId;
}
