import { TdObject, TdRequest } from '../../tdkit/TdTypes';

export interface StickerPreviewData {
  fileId: number;
  format: string;
  emoji: string;
  thumbPath: string;
  width: number;
  height: number;
  canFavorite: boolean;
}
export interface StickerPreviewSnapshot {
  path: string;
  uid: string;
  loading: boolean;
  failed: boolean;
  favorite: boolean;
  favoriteReady: boolean;
  favoriteBusy: boolean;
  favoriteFailed: boolean;
}
export function emptyStickerPreview(): StickerPreviewSnapshot {
  return { path: '', uid: '', loading: true, failed: false, favorite: false,
    favoriteReady: false, favoriteBusy: false, favoriteFailed: false };
}
export interface StickerPreviewClient {
  send: (request: TdRequest, timeout: number) => Promise<TdObject>;
}

// Each dialog owns one session. Never cancel the shared TDLib file download on close.
export class StickerPreviewSession {
  private view: StickerPreviewSnapshot = emptyStickerPreview();
  private closed: boolean = false;
  private fileRevision: number = 0;
  private favoriteRevision: number = 0;
  private client: StickerPreviewClient;
  private data: StickerPreviewData;
  private current: () => boolean;
  private publish: (view: StickerPreviewSnapshot) => void;
  private favoriteChanged: (favorite: boolean) => void;
  constructor(client: StickerPreviewClient, data: StickerPreviewData,
    current: () => boolean, publish: (view: StickerPreviewSnapshot) => void,
    favoriteChanged: (favorite: boolean) => void) {
    this.client = client; this.data = data; this.current = current;
    this.publish = publish; this.favoriteChanged = favoriteChanged;
  }

  private active(): boolean { return !this.closed && this.current(); }
  private emit(): void {
    if (!this.active()) { return; }
    this.publish({ path: this.view.path, uid: this.view.uid, loading: this.view.loading, failed: this.view.failed,
      favorite: this.view.favorite, favoriteReady: this.view.favoriteReady, favoriteBusy: this.view.favoriteBusy,
      favoriteFailed: this.view.favoriteFailed });
  }

  async loadFile(): Promise<void> {
    if (!this.active()) { return; }
    const revision = ++this.fileRevision;
    this.view.loading = true; this.view.failed = false; this.emit();
    try {
      const request: TdRequest = { '@type': 'getFile' }; request['file_id'] = this.data.fileId;
      let file = await this.client.send(request, 15000);
      if (!this.active() || revision !== this.fileRevision) { return; }
      let local = file['local'] as TdObject | undefined;
      if (local?.['is_downloading_completed'] !== true || !local['path']) {
        const download: TdRequest = { '@type': 'downloadFile' };
        download['file_id'] = this.data.fileId; download['priority'] = 16; download['synchronous'] = true;
        file = await this.client.send(download, 15000);
        if (!this.active() || revision !== this.fileRevision) { return; }
        local = file['local'] as TdObject | undefined;
      }
      const path = (local?.['path'] as string | undefined) ?? '';
      if (local?.['is_downloading_completed'] !== true || path === '') { throw new Error('sticker not ready'); }
      const remote = file['remote'] as TdObject | undefined;
      this.view.path = path; this.view.uid = (remote?.['unique_id'] as string | undefined) ?? '';
      this.view.loading = false; this.emit();
    } catch (_) {
      if (this.active() && revision === this.fileRevision) {
        this.view.loading = false; this.view.failed = true; this.emit();
      }
    }
  }

  async loadFavorite(): Promise<void> {
    if (!this.active() || !this.data.canFavorite || this.view.favoriteBusy) { return; }
    const revision = ++this.favoriteRevision;
    this.view.favoriteReady = false; this.view.favoriteFailed = false; this.emit();
    try {
      const result = await this.client.send({ '@type': 'getFavoriteStickers' }, 15000);
      if (!this.active() || revision !== this.favoriteRevision) { return; }
      if (result['@type'] !== 'stickers') { throw new Error('invalid favorites'); }
      const stickers = (result['stickers'] as TdObject[] | undefined) ?? [];
      this.view.favorite = stickers.some((sticker: TdObject): boolean => {
        const file = sticker['sticker'] as TdObject | undefined;
        return file?.['id'] === this.data.fileId;
      });
      this.view.favoriteReady = true; this.emit();
    } catch (_) {
      if (this.active() && revision === this.favoriteRevision) {
        this.view.favoriteFailed = true; this.emit();
      }
    }
  }

  async toggleFavorite(): Promise<void> {
    if (!this.active() || !this.data.canFavorite || !this.view.favoriteReady || this.view.favoriteBusy) { return; }
    const revision = ++this.favoriteRevision;
    const next = !this.view.favorite;
    this.view.favoriteBusy = true; this.view.favoriteFailed = false; this.emit();
    try {
      const request: TdRequest = { '@type': next ? 'addFavoriteSticker' : 'removeFavoriteSticker' };
      const input: TdObject = { '@type': 'inputFileId' }; input['id'] = this.data.fileId; request['sticker'] = input;
      const result = await this.client.send(request, 15000);
      if (!this.active() || revision !== this.favoriteRevision) { return; }
      if (result['@type'] !== 'ok') { throw new Error('favorite mutation failed'); }
      this.view.favorite = next; this.view.favoriteBusy = false; this.emit(); this.favoriteChanged(next);
    } catch (_) {
      if (this.active() && revision === this.favoriteRevision) {
        // A timed-out write may have succeeded. Re-read before allowing another toggle.
        this.view.favoriteBusy = false; this.view.favoriteReady = false; this.view.favoriteFailed = true; this.emit();
      }
    }
  }

  close(): void { this.closed = true; this.fileRevision++; this.favoriteRevision++; }
}
