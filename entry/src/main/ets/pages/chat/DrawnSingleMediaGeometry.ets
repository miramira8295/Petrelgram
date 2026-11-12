import { MessageEntry } from '../../store/MessageEntry';
import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { mediaBoxFor } from '../../util/mediaBox';
import { DrawnAlbumGridPlan } from './DrawnAlbumGridLayout';

// One tile with the SAME mediaBoxFor dimensions as prefetch/legacy rendering.
// No playback/progress/variant inputs: these belong to the local video island.
export class DrawnSingleMediaGeometry {
  private previous: DrawnAlbumGridPlan | null = null;
  private key: string = '';
  private path: string = '';
  private mini: string = '';

  prepare(msg: MessageEntry, chatId: number, contentWidth: number, avatarSpace: number,
    density: number): DrawnAlbumGridPlan {
    const key = `${chatId}:${msg.rowId}:${msg.id}:${msg.contentType}:${msg.photoFileId}:${msg.photoFailed}:` +
      `${msg.photoWidth}:${msg.photoHeight}:${contentWidth}:${avatarSpace}:${density}`;
    if (this.previous !== null && this.key === key && this.path === msg.photoPath && this.mini === msg.photoMini) { return this.previous; }
    const box = mediaBoxFor(contentWidth, msg.photoWidth, msg.photoHeight, msg.contentType === 'video', avatarSpace);
    const cell: AlbumCellRenderData = { idx: 0, width: box.width, height: box.height, chatId, messageId: msg.id,
      thumbPath: msg.photoPath, thumbFileId: msg.photoFileId, mini: msg.photoMini, progress: 0, failed: msg.photoFailed,
      isVideo: msg.contentType === 'video', isLive: false, videoFileId: 0, videoFileSize: 0, videoDuration: 0,
      videoMimeType: '', inlineFileId: 0, inlineFileSize: 0, uploading: false, isPlaySlot: false,
      autoplayMuted: false, playSlotStartMs: 0, selectionActive: false, selected: false };
    const p: DrawnAlbumGridPlan = { width: box.width, height: box.height, density,
      tiles: [{ cell, opaque: false, x: 0, y: 0, width: box.width, height: box.height,
        key: `${chatId}:${msg.rowId}:${msg.id}:${box.width}:${box.height}:${cell.isVideo}` }] };
    this.key = key; this.path = msg.photoPath; this.mini = msg.photoMini; this.previous = p; return p;
  }
}
