import { AlbumGroup } from './collapseAlbums';
import { mediaBoxFor, mediaThumbWidth } from './mediaBox';
import { AlbumCell, packAlbumRows } from './packAlbumRows';

export const INITIAL_EAGER_MESSAGE_ROWS: number = 1;
const PLACEHOLDER_HEIGHT_CACHE_LIMIT: number = 2048;
const placeholderHeightCache: Map<string, number> = new Map<string, number>();

// Admit exactly one real row per release. The 17:04 device trace showed that a
// pair containing a sticker can still take 26-28 ms, while a short initial page
// followed by its automatic backfill bypassed the old 1 -> 3 -> +2 policy and
// put six rows into one 65 ms layout. One-row growth gives every content shape
// the same hard per-VSync ceiling. Keeping the policy here makes it testable
// without ArkUI.
export function nextInitialMessageRevealCount(current: number, available: number): number {
  if (available <= 0 || current >= available) {
    return available;
  }
  return Math.min(current + 1, available);
}

function deferredCopy(group: AlbumGroup): AlbumGroup {
  return {
    // The placeholder is the same LazyForEach item as the real row. Keep the
    // identity/content key stable and let AlbumGroupDataSource emit a keyless
    // CHANGE for initialDeferred; renaming the item here forced List to delete
    // and insert it, which remeasured the surrounding chat window.
    key: group.key,
    head: group.head,
    memberIds: group.memberIds,
    rowMemberIds: group.rowMemberIds,
    photoPaths: group.photoPaths,
    photoFileIds: group.photoFileIds,
    photoRatios: group.photoRatios,
    photoIsVideo: group.photoIsVideo,
    photoIsLive: group.photoIsLive,
    photoProgress: group.photoProgress,
    photoFailed: group.photoFailed,
    videoFileIds: group.videoFileIds,
    videoFileSizes: group.videoFileSizes,
    videoDurations: group.videoDurations,
    videoMimeTypes: group.videoMimeTypes,
    caption: group.caption,
    captionEntities: group.captionEntities,
    dateLabel: group.dateLabel,
    showAvatar: group.showAvatar,
    showSenderName: group.showSenderName,
    initialDeferred: true
  };
}

// Keep only the requested rows real and turn every other row into a cheap
// height placeholder. Bottom-anchored chats reveal backwards from the newest
// row; unread-anchored chats reveal forwards from the unread row because
// ScrollAlign.START makes that row the top of the viewport.
export function stageInitialMessageGroups(
  groups: AlbumGroup[],
  anchorIndex: number,
  alignFromStart: boolean,
  eagerCount: number = INITIAL_EAGER_MESSAGE_ROWS
): AlbumGroup[] {
  if (groups.length <= eagerCount || anchorIndex < 0 || anchorIndex >= groups.length) {
    return groups;
  }
  const eagerStart: number = alignFromStart
    ? anchorIndex : Math.max(0, anchorIndex - eagerCount + 1);
  const eagerEnd: number = alignFromStart
    ? Math.min(groups.length - 1, anchorIndex + eagerCount - 1) : anchorIndex;
  if (eagerStart === 0 && eagerEnd === groups.length - 1) {
    return groups;
  }
  const staged: AlbumGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    staged.push(i >= eagerStart && i <= eagerEnd ? groups[i] : deferredCopy(groups[i]));
  }
  return staged;
}

// 文本行的「每行能装多少字」启发式（估计器与 caption 共用）。真实排版由
// record 事后校正；这里只求别差出一个行数量级。
function estimatedTextLines(textLength: number, screenWidth: number): number {
  const charsPerLine: number = Math.max(12, Math.floor(screenWidth * 0.62 / 9));
  return Math.max(1, Math.min(8, Math.ceil(textLength / charsPerLine)));
}

// 绘制面批 1：媒体行确定性几何。媒体框与真实布局共用同一批「布局前可算」的
// 纯函数（mediaBoxFor 是预取器同款、packAlbumRows 是相册网格本体），不再是
// 拍的 210。chrome（气泡 padding 16 + 行外边距）与 caption/名字行仍是常量
// 近似，残差由 rowH.* 探针读数校准（survey 批 0）。
const MEDIA_BUBBLE_CHROME: number = 20;
const ALBUM_CELL_GAP: number = 2;

function mediaRowBodyHeight(group: AlbumGroup, screenWidth: number): number {
  const msg = group.head;
  let media: number = 0;
  if (group.photoRatios.length > 1) {
    // albumW() 与 mediaThumbWidth 同式：min(280, inlineMaxWidth)。
    const rows: AlbumCell[][] = packAlbumRows(
      group.photoRatios, mediaThumbWidth(screenWidth));
    for (const row of rows) {
      media += row.length > 0 ? row[0].height : 0;
    }
    media += Math.max(0, rows.length - 1) * ALBUM_CELL_GAP;
  } else {
    media = mediaBoxFor(screenWidth, msg.photoWidth, msg.photoHeight,
      msg.contentType === 'video').height;
  }
  let body: number = media + MEDIA_BUBBLE_CHROME;
  const caption: string = group.photoRatios.length > 1 ? group.caption : msg.text;
  if (caption !== '') {
    body += 4 + estimatedTextLines(caption.length, screenWidth) * 22;
  }
  if (msg.replyToMessageId !== 0) { body += 40; }
  if (group.showSenderName && !msg.isOutgoing) { body += 22; }
  return body;
}

// Fixed-height placeholders are deliberately approximate. stackFromEnd or the
// unread START anchor keeps the meaningful edge stable when the real row is
// swapped in one frame later; the estimate only determines how many cheap rows
// List asks for during the first measure pass.
export function initialMessagePlaceholderHeight(
  group: AlbumGroup,
  screenWidth: number,
  showUnreadDivider: boolean
): number {
  const msg = group.head;
  // Initial staging republishes the same rows over several VSyncs. Height only
  // depends on the fields below, so do not repeat the text/shape estimate for
  // every placeholder CHANGE. rowId keeps equal-looking neighbouring rows
  // independent without retaining the potentially kilobyte-sized group key.
  // 媒体分量进键：单媒体的源尺寸、相册的比例序列、相册 caption 长度都影响
  // 确定性几何的结果，漏了会串高（同 rowId 不同媒体只在编辑/替换时出现，
  // 但屏宽档位间的比例夹取路径不同，键上必须完整）。
  const cacheKey: string = `${msg.rowId}|${Math.round(screenWidth)}|${msg.contentType}` +
    `|${msg.text.length}|${msg.replyToMessageId !== 0 ? 1 : 0}` +
    `|${group.photoPaths.length}|${group.showAvatar ? 1 : 0}` +
    `|${group.showSenderName ? 1 : 0}|${group.dateLabel !== '' ? 1 : 0}` +
    `|${showUnreadDivider ? 1 : 0}|${msg.photoWidth}x${msg.photoHeight}` +
    `|${group.photoRatios.map((r: number): string => r.toFixed(2)).join(',')}` +
    `|${group.caption.length}`;
  const cached: number | undefined = placeholderHeightCache.get(cacheKey);
  if (cached !== undefined) {
    return cached;
  }
  let body: number = 52;
  if (msg.contentType === 'system') {
    body = 34;
  } else if (msg.contentType === 'sticker') {
    body = 172;
  } else if (msg.contentType === 'emoji' || msg.contentType === 'customEmoji') {
    body = 76;
  } else if (msg.contentType === 'photo' || msg.contentType === 'video' ||
    group.photoPaths.length > 1) {
    body = mediaRowBodyHeight(group, screenWidth);
  } else if (msg.contentType === 'text') {
    const lines: number = estimatedTextLines(msg.text.length, screenWidth);
    body = Math.max(group.showAvatar ? 44 : 0, 22 + lines * 22);
    if (msg.replyToMessageId !== 0) { body += 40; }
    if (group.showSenderName && !msg.isOutgoing) { body += 20; }
  } else if (msg.contentType === 'voice' || msg.contentType === 'audio' ||
    msg.contentType === 'file' || msg.contentType === 'poll') {
    body = 104;
  }
  if (group.dateLabel !== '') { body += 30; }
  if (showUnreadDivider) { body += 26; }
  if (placeholderHeightCache.size >= PLACEHOLDER_HEIGHT_CACHE_LIMIT) {
    placeholderHeightCache.clear();
  }
  placeholderHeightCache.set(cacheKey, body);
  return body;
}

// Count only the rows whose estimated heights are needed to cover the actual
// message viewport. A fixed row count made media-heavy chats wait needlessly,
// while very short service rows could still leave deferred placeholders on
// screen. The caller keeps the one-row-per-frame admission policy unchanged.
export function initialMessageViewportRows(
  groups: AlbumGroup[],
  anchorIndex: number,
  alignFromStart: boolean,
  screenWidth: number,
  viewportHeight: number,
  firstUnreadId: number,
  rowHeight: (
    group: AlbumGroup, screenWidth: number, showUnreadDivider: boolean
  ) => number = initialMessagePlaceholderHeight
): number {
  if (groups.length === 0 || anchorIndex < 0 || anchorIndex >= groups.length) {
    return 0;
  }
  const step: number = alignFromStart ? 1 : -1;
  let index: number = anchorIndex;
  let coveredHeight: number = 0;
  let count: number = 0;
  while (index >= 0 && index < groups.length && coveredHeight < viewportHeight) {
    const group: AlbumGroup = groups[index];
    coveredHeight += rowHeight(
      group,
      screenWidth,
      firstUnreadId > 0 && group.memberIds.indexOf(firstUnreadId) >= 0
    );
    count++;
    index += step;
  }
  return count;
}
