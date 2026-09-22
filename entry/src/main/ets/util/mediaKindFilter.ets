// 共享媒体页的「全部 / 图片 / 视频」子筛选（issue #214 第 1 条）。
//
// 媒体页原来固定用 searchMessagesFilterPhotoAndVideo，图和视频混在一格网格里。
// TDLib 本来就有分开的两个过滤器，随包的 libtdjson.so 里三个都在（验过），
// 所以这件事只是"把哪一个送出去"的选择，不需要客户端再过滤一遍——客户端过滤
// 会让分页彻底失真（一页 50 条里可能一张图都没有，翻页看起来就是卡住）。
export const MEDIA_KIND_ALL: string = 'all';
export const MEDIA_KIND_PHOTO: string = 'photo';
export const MEDIA_KIND_VIDEO: string = 'video';

export const MEDIA_KINDS: string[] = [MEDIA_KIND_ALL, MEDIA_KIND_PHOTO, MEDIA_KIND_VIDEO];

// 不认识的值一律回落到"全部"：这个值将来可能从设置/路由参数进来，
// 脏值不该让媒体页变成空白。
export function mediaKindFilterOf(kind: string): string {
  if (kind === MEDIA_KIND_PHOTO) {
    return 'searchMessagesFilterPhoto';
  }
  if (kind === MEDIA_KIND_VIDEO) {
    return 'searchMessagesFilterVideo';
  }
  return 'searchMessagesFilterPhotoAndVideo';
}

export function normalizeMediaKind(kind: string): string {
  return MEDIA_KINDS.indexOf(kind) >= 0 ? kind : MEDIA_KIND_ALL;
}
