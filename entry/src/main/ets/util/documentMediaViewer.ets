import { DrawnDocumentMedia, documentFileId } from './drawnDocumentMedia';
import { DocumentFileState, documentFileState, watchDocumentFile, requestDocumentFile } from './documentFileChannel';
import { DownloadCenterItem, DC_STATE_COMPLETE, DC_STATE_DOWNLOADING, DC_SOURCE_CACHE } from './downloadCenterModel';
import { MessageEntry, buildMessageEntry } from '../store/MessageEntry';
import { getUserStore } from '../tdkit/Globals';
import { viewerBaseMessage, viewerEntryFor } from './downloadViewerSet';
import { MEDIA_VIEWING_PRIORITY, THUMBNAIL_PRIORITY } from './downloadPriority';

export interface DocumentMediaSession { media: DrawnDocumentMedia[]; chatId: number; messageId: number; date: number; senderName: string; }
// Temporary viewer IDs never enter MessageStore. Only the selected asset is
// subscribed/downloaded; O(M) setup, O(1) file routing, no work on byte updates.
export class DocumentMediaViewer {
  readonly items: DownloadCenterItem[] = [];
  readonly entries: MessageEntry[] = [];
  private base: MessageEntry = buildMessageEntry(viewerBaseMessage(), getUserStore(), false);
  private unsubs: (() => void)[] = [];
  private generation: number = 0;
  private active: number = -1;
  private session: DocumentMediaSession;
  private changed: () => void;
  constructor(session: DocumentMediaSession, changed: () => void) {
    this.session = session; this.changed = changed;
    for (let i = 0; i < session.media.length; i++) { this.refresh(i); }
  }
  private refresh(index: number): void {
    const media = this.session.media[index], full = documentFileState(media.file);
    const thumb = media.thumbnail === undefined ? full : documentFileState(media.thumbnail);
    const item: DownloadCenterItem = { fileId: documentFileId(media.file), path: full.path, name: media.name,
      kind: media.kind === 'photo' ? 'photo' : 'video', size: media.size,
      downloaded: Math.floor(media.size * full.progress / 100), state: full.path !== '' ? DC_STATE_COMPLETE : DC_STATE_DOWNLOADING,
      source: DC_SOURCE_CACHE, mtime: this.session.date * 1000, preview: '', chatId: this.session.chatId,
      messageId: this.session.messageId, mimeType: media.mimeType, session: this.session.senderName, savedLocal: false, speed: 0 };
    const entry = viewerEntryFor(this.base, item, index + 1);
    entry.photoWidth = media.width; entry.photoHeight = media.height;
    if (media.kind === 'photo') {
      entry.photoPath = full.path || thumb.path; entry.photoProgress = full.path !== '' ? 100 : thumb.progress;
      entry.photoFullPath = full.path; entry.photoFullProgress = full.progress; entry.photoFullFailed = full.failed;
    } else {
      entry.photoPath = media.thumbnail !== undefined ? thumb.path : '';
      entry.videoDuration = media.duration ?? 0;
    }
    this.items[index] = item; this.entries[index] = entry;
  }
  activate(index: number, retry: boolean = false): void {
    if (index < 0 || index >= this.session.media.length) { return; }
    if (index !== this.active) {
      this.dispose(); this.active = index;
      const generation = this.generation, media = this.session.media[index];
      const update = (_state: DocumentFileState): void => {
        if (generation !== this.generation) { return; }
        this.refresh(index); this.changed();
      };
      this.unsubs.push(watchDocumentFile(media.file, update));
      if (media.thumbnail !== undefined && documentFileId(media.thumbnail) !== documentFileId(media.file)) {
        this.unsubs.push(watchDocumentFile(media.thumbnail, update));
        requestDocumentFile(media.thumbnail, THUMBNAIL_PRIORITY, retry);
      }
      this.refresh(index); this.changed();
    }
    const media = this.session.media[index];
    if (media.kind === 'photo') { requestDocumentFile(media.file, MEDIA_VIEWING_PRIORITY, retry); }
  }
  dispose(): void { this.generation++; this.unsubs.forEach((off: () => void): void => off()); this.unsubs = []; this.active = -1; }
}
