import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { mergeMusicTracks, MusicTrack, musicTrackFromMessage } from '../util/musicTrackModel';
import { logE } from '../util/log';

// 音乐中心的曲库（2026-09-18）。**曲库就是所有会话里的音频消息**——这个应用里没有别的
// 「歌」。用 TDLib 的全局搜索按音频类型过滤，分页靠它返回的 next_offset。
//
// 【为什么单独一个 store 而不是复用 GlobalSearchStore】那个是「搜索页」的状态机，按
// 会话/联系人/消息分页签，行是 SearchRow（会话行）。这里要的是曲目，而且空查询时也要
// 有结果（整个曲库），两者的加载时机与缓存都不一样。
//
// 【空查询也搜】TDLib 的 searchMessages 允许空 query + 过滤器，返回的就是全部音频消息，
// 正好当「全部歌曲」用；有查询时同一条路带上关键词。

const PAGE_LIMIT: number = 40;

export type MusicLibraryListener = () => void;

export class MusicLibraryStore {
  private client: TdClient;
  private tracks: MusicTrack[] = [];
  private query: string = '';
  private nextOffset: string = '';
  private loadState: string = 'idle';   // idle | loading | ready | error
  private exhausted: boolean = false;
  private listeners: MusicLibraryListener[] = [];
  // 换查询词时作废在途的那一趟：它回来得晚，会把新词的结果盖掉。
  private seq: number = 0;

  constructor(client: TdClient) {
    this.client = client;
  }

  getTracks(): MusicTrack[] {
    return this.tracks;
  }

  getState(): string {
    return this.loadState;
  }

  getQuery(): string {
    return this.query;
  }

  hasMore(): boolean {
    return !this.exhausted;
  }

  subscribe(listener: MusicLibraryListener): () => void {
    this.listeners.push(listener);
    return (): void => {
      this.listeners = this.listeners.filter((l: MusicLibraryListener): boolean => l !== listener);
    };
  }

  // 换查询词：清空结果重新拉。词没变就什么都不做——搜索框每敲一下都会调到这里。
  search(query: string): void {
    const trimmed: string = query.trim();
    if (trimmed === this.query && this.loadState !== 'idle') {
      return;
    }
    this.seq++;
    this.query = trimmed;
    this.tracks = [];
    this.nextOffset = '';
    this.exhausted = false;
    this.loadState = 'idle';
    this.notify();
    this.loadMore();
  }

  loadMore(): void {
    if (this.loadState === 'loading' || this.exhausted) {
      return;
    }
    this.loadState = 'loading';
    this.notify();
    const seq: number = this.seq;
    const offset: string = this.nextOffset;
    this.client.send(this.buildRequest(offset)).then((found: TdObject): void => {
      if (seq !== this.seq) {
        return;   // 期间换了查询词
      }
      const messages: TdObject[] = (found['messages'] as TdObject[] | undefined) ?? [];
      const page: MusicTrack[] = [];
      messages.forEach((message: TdObject): void => {
        const track: MusicTrack | null = musicTrackFromMessage(message);
        if (track !== null) {
          page.push(track);
        }
      });
      this.tracks = mergeMusicTracks(this.tracks, page);
      this.nextOffset = (found['next_offset'] as string | undefined) ?? '';
      // TDLib 用空 next_offset 表示到底了；一页一条都没解析出来时也别继续翻。
      this.exhausted = this.nextOffset === '' || messages.length === 0;
      this.loadState = 'ready';
      this.notify();
    }).catch((e: TdError): void => {
      if (seq !== this.seq) {
        return;
      }
      this.loadState = 'error';
      this.exhausted = true;
      this.notify();
      logE(`MusicLibraryStore.searchMessages failed: ${e.message}`);
    });
  }

  close(): void {
    this.seq++;
    this.listeners = [];
  }

  private buildRequest(offset: string): TdRequest {
    const filter: TdObject = { '@type': 'searchMessagesFilterAudio' };
    const req: TdRequest = { '@type': 'searchMessages' };
    // chat_list 不传 = 全部会话（主列表与归档）。
    req['query'] = this.query;
    req['offset'] = offset;
    req['limit'] = PAGE_LIMIT;
    req['filter'] = filter;
    req['min_date'] = 0;
    req['max_date'] = 0;
    return req;
  }

  private notify(): void {
    this.listeners.forEach((listener: MusicLibraryListener): void => listener());
  }
}
