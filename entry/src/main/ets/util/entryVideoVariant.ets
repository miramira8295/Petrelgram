import { MessageEntry } from '../store/MessageEntry';
import {
  QUALITY_AUTO, VideoVariant, networkIsMetered, pickInlineSource, pickVideoVariant, playableVariants, variantsOwnFile
} from './videoVariants';

// 消息条目上的多清晰度（2026-10-10）。查看器、列表的头部预取共用这几个入口——
// 两边各算各的，预取下的就不一定是点开要播的那档（流量网络下原片预取 20MB 白下）。

export function entryVideoVariants(e: MessageEntry): VideoVariant[] {
  if (e.videoFileId === 0) {
    return [];
  }
  const original: VideoVariant = {
    fileId: e.videoFileId, width: e.photoWidth, height: e.photoHeight, size: e.videoFileSize, codec: ''
  };
  return playableVariants(original, e.videoVariants);
}

// 这一条按 quality 该播哪一档；原片已在本地的话「自动」直接用原片。没有视频返回 null。
export function entryPlaybackVariant(e: MessageEntry, quality: number, network: string): VideoVariant | null {
  const list: VideoVariant[] = entryVideoVariants(e);
  if (list.length === 0) {
    return null;
  }
  return pickVideoVariant(list, quality, networkIsMetered(network), e.videoPath !== '');
}

export interface EntryVideoFileRef {
  fileId: number;
  fileSize: number;
  // 这一档已经整份在本地（只有原片知道；别的档按「不在」算，TDLib 对已下好的会立刻应答）。
  local: boolean;
}

// 列表头部预取该预取哪一档：与查看器「自动」档一致。
export function entryPrefetchFile(e: MessageEntry, network: string): EntryVideoFileRef | null {
  const v: VideoVariant | null = entryPlaybackVariant(e, QUALITY_AUTO, network);
  if (v === null || v.fileId === 0) {
    return null;
  }
  const isOriginal: boolean = v.fileId === e.videoFileId;
  return {
    fileId: v.fileId,
    fileSize: v.size > 0 ? v.size : (isOriginal ? e.videoFileSize : 0),
    local: isOriginal && e.videoPath !== ''
  };
}

// 这个文件是不是这条视频的某一档（查看器正在播的那条，哪一档都算「已认领」）。
export function entryOwnsVideoFile(e: MessageEntry, fileId: number): boolean {
  return variantsOwnFile(e.videoFileId, e.videoVariants, fileId);
}

// 会话里自动播放小窗（VideoBubbleSurface，气泡与相册格）播哪一档；自动播放大小上限（#226）
// 也按这一档的大小判。
export function entryInlineFile(e: MessageEntry): EntryVideoFileRef | null {
  if (e.videoFileId === 0) { return null; }
  const v = pickInlineSource({ fileId: e.videoFileId, width: e.photoWidth, height: e.photoHeight,
    size: e.videoFileSize, codec: '' }, e.videoVariants, e.videoPath !== '');
  const isOriginal: boolean = v.fileId === e.videoFileId;
  return {
    fileId: v.fileId,
    fileSize: v.size > 0 ? v.size : (isOriginal ? e.videoFileSize : 0),
    local: isOriginal && e.videoPath !== ''
  };
}

// 自动播放大小上限（#226）按小窗实际要下的那一档判。没有这条消息返回 0。
export function entryInlineSize(e: MessageEntry | null): number {
  if (e === null) {
    return 0;
  }
  const f: EntryVideoFileRef | null = entryInlineFile(e);
  return f !== null ? f.fileSize : e.videoFileSize;
}
