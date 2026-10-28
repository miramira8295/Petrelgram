import { AlbumGroup } from './collapseAlbums';
import { AlbumCell, packAlbumRows } from './packAlbumRows';
import { slotKey } from '../pages/chat/playSlot';

export interface AlbumCellRenderContext {
  chatId: number;
  selectionActive: boolean;
  selectedMemberIds: number[];
  playSlotKey: string;
  autoplayMuted: boolean;
  playSlotStartMs: number;
}

// Immutable input for one album tile. No group/page snapshots or subscriptions
// cross this boundary; live thumbnail/progress channels remain owned by the tile.
export interface AlbumCellRenderData {
  idx: number;
  width: number;
  height: number;
  chatId: number;
  messageId: number;
  thumbPath: string;
  thumbFileId: number;
  mini: string;
  progress: number;
  failed: boolean;
  isVideo: boolean;
  isLive: boolean;
  videoFileId: number;
  videoFileSize: number;
  videoDuration: number;
  videoMimeType: string;
  inlineFileId: number;
  inlineFileSize: number;
  uploading: boolean;
  isPlaySlot: boolean;
  autoplayMuted: boolean;
  playSlotStartMs: number;
  selectionActive: boolean;
  selected: boolean;
}

const EMPTY_RENDER_ROW: AlbumCellRenderData[] = [];

export function albumRenderRowAt(rows: AlbumCellRenderData[][], index: number): AlbumCellRenderData[] {
  return Number.isInteger(index) && index >= 0 && index < rows.length ? rows[index] : EMPTY_RENDER_ROW;
}

function sameCells(a: AlbumCellRenderData[], b: AlbumCellRenderData[]): boolean {
  return a.length === b.length && a.every((cell: AlbumCellRenderData, i: number): boolean => cell === b[i]);
}

function prepareCell(previous: AlbumCellRenderData | undefined, cell: AlbumCell,
  group: AlbumGroup, data: AlbumCellRenderContext): AlbumCellRenderData {
  const i = cell.idx;
  const messageId = group.memberIds[i] ?? 0;
  const thumbPath = group.photoPaths[i] ?? '';
  const thumbFileId = group.photoFileIds[i] ?? 0;
  const mini = group.photoMinis[i] ?? '';
  const progress = group.photoProgress[i] ?? 0;
  const failed = group.photoFailed[i] ?? false;
  const isVideo = group.photoIsVideo[i] ?? false;
  const isLive = group.photoIsLive[i] ?? false;
  const videoFileId = group.videoFileIds[i] ?? 0;
  const videoFileSize = group.videoFileSizes[i] ?? 0;
  const videoDuration = group.videoDurations[i] ?? 0;
  const videoMimeType = group.videoMimeTypes[i] ?? '';
  const inlineFileId = group.inlineFileIds[i] ?? 0;
  const inlineFileSize = group.inlineFileSizes[i] ?? 0;
  const uploading = group.head.sendState === 'sending';
  const isPlaySlot = data.playSlotKey !== '' && !group.head.isAnimation &&
    data.playSlotKey === slotKey(messageId, i);
  // Position and mute only affect the tile that actually hosts the player.
  const autoplayMuted = isPlaySlot ? data.autoplayMuted : false;
  const playSlotStartMs = isPlaySlot ? data.playSlotStartMs : 0;
  const selectionActive = data.selectionActive;
  const selected = data.selectedMemberIds.indexOf(messageId) >= 0;
  if (previous !== undefined && previous.idx === i && previous.width === cell.width &&
    previous.height === cell.height && previous.chatId === data.chatId && previous.messageId === messageId &&
    previous.thumbPath === thumbPath && previous.thumbFileId === thumbFileId && previous.mini === mini &&
    previous.progress === progress && previous.failed === failed && previous.isVideo === isVideo &&
    previous.isLive === isLive && previous.videoFileId === videoFileId && previous.videoFileSize === videoFileSize &&
    previous.videoDuration === videoDuration && previous.videoMimeType === videoMimeType &&
    previous.inlineFileId === inlineFileId && previous.inlineFileSize === inlineFileSize &&
    previous.uploading === uploading && previous.isPlaySlot === isPlaySlot &&
    previous.autoplayMuted === autoplayMuted && previous.playSlotStartMs === playSlotStartMs &&
    previous.selectionActive === selectionActive && previous.selected === selected) {
    return previous;
  }
  return {
    idx: i, width: cell.width, height: cell.height, chatId: data.chatId, messageId,
    thumbPath, thumbFileId, mini, progress, failed, isVideo, isLive,
    videoFileId, videoFileSize, videoDuration, videoMimeType, inlineFileId, inlineFileSize,
    uploading, isPlaySlot, autoplayMuted, playSlotStartMs, selectionActive, selected
  };
}

// One bounded cache per album view. Geometry is keyed by actual ratios/width,
// so caption/translation/reaction updates cannot repack or replace unchanged rows.
export class AlbumCellRenderCache {
  private ratios: number[] = [];
  private width: number = -1;
  private geometry: AlbumCell[][] = [];
  private cells: Map<number, AlbumCellRenderData> = new Map();
  private rows: AlbumCellRenderData[][] = [];

  prepare(group: AlbumGroup, data: AlbumCellRenderContext, width: number): AlbumCellRenderData[][] {
    if (Math.abs(this.width - width) > 0.01 || this.ratios.length !== group.photoRatios.length ||
      this.ratios.some((ratio: number, i: number): boolean => ratio !== group.photoRatios[i])) {
      this.width = width;
      this.ratios = group.photoRatios.slice();
      this.geometry = packAlbumRows(this.ratios, width);
    }
    const cells = new Map<number, AlbumCellRenderData>();
    const rows: AlbumCellRenderData[][] = this.geometry.map((row: AlbumCell[], index: number): AlbumCellRenderData[] => {
      const next = row.map((cell: AlbumCell): AlbumCellRenderData => {
        const prepared = prepareCell(this.cells.get(cell.idx), cell, group, data);
        cells.set(cell.idx, prepared);
        return prepared;
      });
      const previous = this.rows[index];
      return previous !== undefined && sameCells(previous, next) ? previous : next;
    });
    this.cells = cells;
    if (this.rows.length !== rows.length || this.rows.some(
      (row: AlbumCellRenderData[], i: number): boolean => row !== rows[i])) {
      this.rows = rows;
    }
    return this.rows;
  }
}
