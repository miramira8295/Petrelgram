import { TdClient } from '../../tdkit/TdClient';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';

const PAGE_SIZE: number = 20;

@Observed
export class AvatarPhoto {
  key: string;
  index: number;
  imageId: number = 0;
  videoId: number = 0;
  thumbId: number = 0;
  thumbPath: string = '';
  thumbFailed: boolean = false;
  imagePath: string = '';
  videoPath: string = '';
  downloadFailed: boolean = false;
  constructor(key: string, index: number) { this.key = key; this.index = index; }
}

function completedPath(file: TdObject | undefined): string {
  const local = file?.['local'] as TdObject | undefined;
  return local?.['is_downloading_completed'] === true ? (local['path'] as string ?? '') : '';
}

// Append-only lazy pager. Metadata costs O(page size); dedup/file completion
// use keyed lookups, and selection warms at most three stills plus one video.
// Personal/public avatars stay at index zero: getUserProfilePhotos excludes them.
export class AvatarGallerySession implements IDataSource {
  private photos: AvatarPhoto[] = [];
  private byPhoto: Map<string, AvatarPhoto> = new Map();
  private byImage: Map<number, AvatarPhoto> = new Map();
  private pending: Map<number, Set<AvatarPhoto>> = new Map();
  private listeners: Set<DataChangeListener> = new Set();
  private client: TdClient;
  private userId: number;
  private chatId: number;
  private notify: () => void;
  private active: boolean = false;
  private generation: number = 0;
  private unsub: (() => void) | null = null;
  private offset: number = 0;
  private cursor: number = 0;
  index: number = 0;
  loading: boolean = false;
  hasMore: boolean = true;
  error: boolean = false;

  constructor(client: TdClient, userId: number, chatId: number, imageId: number,
    imagePath: string, videoPath: string, notify: () => void) {
    this.client = client; this.userId = userId; this.chatId = chatId; this.notify = notify;
    const seed = new AvatarPhoto('current', 0);
    seed.imageId = imageId; seed.imagePath = imagePath; seed.videoPath = videoPath;
    this.photos.push(seed);
    if (imageId > 0) { this.byImage.set(imageId, seed); }
  }

  totalCount(): number { return this.photos.length; }
  getData(index: number): AvatarPhoto { return this.photos[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.add(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners.delete(listener); }

  open(): void {
    if (this.active) { return; }
    this.active = true;
    this.unsub = this.client.onUpdate('updateFile', (update: TdObject): void => {
      const file = update['file'] as TdObject | undefined;
      if (file !== undefined && this.active) { this.applyFile(file); }
    });
    this.loadMore();
  }

  close(): void {
    this.active = false; this.generation++;
    this.unsub?.(); this.unsub = null; this.pending.clear(); this.listeners.clear();
  }

  updateSeedVideo(path: string): void {
    if (this.active && path !== '' && this.photos[0].videoPath !== path) {
      this.photos[0].videoPath = path;
    }
  }

  select(index: number): void {
    if (!this.active || index < 0 || index >= this.photos.length) { return; }
    this.index = index; this.warmWindow();
    if (index >= this.photos.length - 3 && !this.error) { this.loadMore(); }
    this.notify();
  }

  // Called only by mounted filmstrip cells or the bounded large-page window.
  ensureThumbnail(index: number): void {
    if (!this.active || index < 0 || index >= this.photos.length) { return; }
    const photo = this.photos[index];
    if (photo.thumbPath === '' && photo.imagePath === '' && !photo.thumbFailed) {
      this.download(photo.thumbId, photo);
    }
  }

  retry(): void {
    const current = this.photos[this.index];
    current.downloadFailed = false; current.thumbFailed = false; this.warmWindow();
    if (this.error || this.index >= this.photos.length - 1) { this.loadMore(); }
  }

  loadMore(): void {
    if (!this.active || this.loading || !this.hasMore) { return; }
    if (this.userId <= 0 && this.chatId === 0) { this.hasMore = false; this.notify(); return; }
    this.loading = true; this.error = false; this.notify();
    const generation = this.generation;
    const req: TdRequest = { '@type': this.userId > 0 ? 'getUserProfilePhotos' : 'searchChatMessages' };
    req['limit'] = PAGE_SIZE;
    if (this.userId > 0) {
      req['user_id'] = this.userId; req['offset'] = this.offset;
    } else {
      const filter: TdObject = { '@type': 'searchMessagesFilterChatPhoto' };
      req['chat_id'] = this.chatId; req['query'] = ''; req['from_message_id'] = this.cursor;
      req['offset'] = 0; req['filter'] = filter;
    }
    this.client.send(req).then((result: TdObject): void => {
      if (!this.active || generation !== this.generation) { return; }
      const oldCount = this.photos.length;
      if (this.userId > 0) {
        const photos = (result['photos'] as TdObject[] | undefined) ?? [];
        for (const photo of photos) { this.append(photo); }
        this.offset += photos.length;
        const total = (result['total_count'] as number | undefined) ?? -1;
        this.hasMore = photos.length > 0 && (total < 0 || this.offset < total);
      } else {
        const messages = (result['messages'] as TdObject[] | undefined) ?? [];
        for (const message of messages) {
          const content = message['content'] as TdObject | undefined;
          if (content?.['@type'] === 'messageChatChangePhoto') {
            const photo = content['photo'] as TdObject | undefined;
            if (photo !== undefined) { this.append(photo); }
          }
        }
        const next = (result['next_from_message_id'] as number | undefined) ?? 0;
        this.hasMore = next !== 0 && next !== this.cursor;
        this.cursor = next;
      }
      this.loading = false;
      if (this.photos.length > oldCount) {
        const keys = this.photos.slice(oldCount).map((photo: AvatarPhoto): string => photo.key);
        const operations: DataOperation[] = [{ type: DataOperationType.ADD, index: oldCount,
          count: keys.length, key: keys } as DataAddOperation];
        this.listeners.forEach((listener: DataChangeListener): void => { listener.onDatasetChange(operations); });
      }
      this.warmWindow(); this.notify();
    }).catch((): void => {
      if (!this.active || generation !== this.generation) { return; }
      this.loading = false; this.error = true; this.notify();
    });
  }

  private append(raw: TdObject): void {
    const sizes = (raw['sizes'] as TdObject[] | undefined) ?? [];
    let file: TdObject | undefined = undefined;
    let area: number = -1;
    let thumb: TdObject | undefined = undefined;
    let thumbArea: number = Number.MAX_VALUE;
    for (const size of sizes) {
      const candidate = size['photo'] as TdObject | undefined;
      const pixels = ((size['width'] as number | undefined) ?? 0) * ((size['height'] as number | undefined) ?? 0);
      if (candidate !== undefined && pixels > 0 && pixels < thumbArea) { thumbArea = pixels; thumb = candidate; }
      if (candidate !== undefined && pixels > area) { area = pixels; file = candidate; }
    }
    const imageId = (file?.['id'] as number | undefined) ?? 0;
    if (imageId <= 0) { return; }
    const photoId = raw['id'];
    const key = photoId !== undefined ? `photo:${String(photoId)}` : `file:${imageId}`;
    let photo = this.byPhoto.get(key) ?? this.byImage.get(imageId);
    if (photo === undefined) {
      photo = new AvatarPhoto(key, this.photos.length); this.photos.push(photo);
    }
    this.byPhoto.set(key, photo); this.byImage.set(imageId, photo);
    photo.imageId = imageId;
    photo.thumbId = (thumb?.['id'] as number | undefined) ?? imageId;
    const thumbPath = completedPath(thumb); if (thumbPath !== '') { photo.thumbPath = thumbPath; }
    const path = completedPath(file); if (path !== '') { photo.imagePath = path; }
    const animation = (raw['animation'] as TdObject | undefined) ?? (raw['small_animation'] as TdObject | undefined);
    const video = animation?.['file'] as TdObject | undefined;
    photo.videoId = (video?.['id'] as number | undefined) ?? 0;
    const videoPath = completedPath(video); if (videoPath !== '') { photo.videoPath = videoPath; }
  }

  private warmWindow(): void {
    for (let i = Math.max(0, this.index - 1); i <= Math.min(this.photos.length - 1, this.index + 1); i++) {
      const photo = this.photos[i];
      this.ensureThumbnail(i);
      if (photo.imagePath === '') { this.download(photo.imageId, photo); }
      if (i === this.index && photo.videoPath === '') { this.download(photo.videoId, photo); }
    }
  }

  private download(id: number, photo: AvatarPhoto): void {
    if (id <= 0) { return; }
    const existing = this.pending.get(id);
    if (existing !== undefined) { existing.add(photo); return; }
    const waiting: Set<AvatarPhoto> = new Set([photo]);
    this.pending.set(id, waiting);
    const generation = this.generation;
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = id; req['priority'] = 16; req['synchronous'] = false;
    this.client.send(req)
      .then((file: TdObject): void => {
        if (this.active && generation === this.generation) { this.applyFile(file); }
      }).catch((): void => {
        if (!this.active || generation !== this.generation || this.pending.get(id) !== waiting) { return; }
        this.pending.delete(id);
        waiting.forEach((owner: AvatarPhoto): void => {
          if (owner.thumbId === id) { owner.thumbFailed = true; }
          if (owner.imageId === id || owner.videoId === id) { owner.downloadFailed = true; }
        });
      });
  }

  private applyFile(file: TdObject): void {
    const id = (file['id'] as number | undefined) ?? 0;
    const waiting = this.pending.get(id);
    if (waiting === undefined) { return; }
    const path = completedPath(file); if (path === '') { return; }
    this.pending.delete(id);
    waiting.forEach((photo: AvatarPhoto): void => {
      if (photo.thumbId === id) { photo.thumbPath = path; photo.thumbFailed = false; }
      if (photo.imageId === id) { photo.imagePath = path; }
      if (photo.videoId === id) { photo.videoPath = path; }
      if (photo.imageId === id || photo.videoId === id) { photo.downloadFailed = false; }
    });
  }
}
