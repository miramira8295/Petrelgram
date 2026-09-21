import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { getTdClient } from '../../tdkit/Globals';
import { MusicLibraryStore } from '../../store/MusicLibraryStore';
import { MusicPlaybackSnapshot, MusicPlayerController } from '../../store/MusicPlayerController';
import {
  addTrackToCollectionById, createCollection, deleteCollection, ensureMusicCollections,
  musicCollections, removeTrackFromCollectionById, subscribeMusicCollections,
  toggleTrackInCollectionById, trackInAnyCollection
} from '../../store/MusicCollectionStore';
import { KEY_MUSIC_CENTER_ON, setBoolean } from '../../store/AppSettings';
import { probeMusicSource } from '../../services/AudioMetadataProbe';
import { cachedMusicCover, ensureMusicCover } from '../../services/MusicCoverCache';
import { audioOutputDevices } from '../../services/AudioOutputDevices';
import { rememberMusicTracks, resolveMusicTracks } from '../../services/MusicTrackResolver';
import { AudioSourceInfo } from '../../util/audioHeaderProbe';
import { MusicCollection } from '../../util/musicCollectionModel';
import { MusicTrack, musicTrackKey, trackKeyOf } from '../../util/musicTrackModel';
import { musicGlowColors } from '../../util/musicCenterStyle';
import { AudioOutputDevice, buildCastRows, MusicCastRow, castChipName } from '../../util/musicCastDevices';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { currentNowPlaying, NowPlaying } from '../../util/nowPlayingChannel';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { MusicPlayerView } from './MusicPlayerView';
import { MusicCollectionsView } from './MusicCollectionsView';
import { MusicCollectionDetailView } from './MusicCollectionDetailView';
import { MusicAddToSheet, MusicCreateDialog, MusicPlaylistSheet } from './MusicSheets';
import { MusicCastSheet } from './MusicCastSheet';
import { MusicSearchOverlay } from './MusicSearchOverlay';
import {
  materializeBotTrack, MUSIC_BOT_USERNAME, MusicBotSearchResult, searchMusicBot
} from '../../store/MusicBotSearchApi';
import { ensureMusicBotSent } from '../../store/MusicBotSentStore';
import {
  CHAT_BOT_ERR_OFFLINE, CHAT_BOT_ERR_TIMEOUT, CHAT_BOT_ERR_UNREADABLE, ChatBotSearchOutcome,
  chatBotFetch, chatBotSearch, MUSIC_CHAT_BOT_USERNAME
} from '../../store/MusicChatBotApi';
import { ChatBotHit } from '../../util/musicChatBotParse';
import { MusicCenterTopBar } from './MusicCenterTopBar';

// 音乐中心（2026-09-18，照 Claude Design「Music Player」稿）。
//
// 一页两个页签：
//   播放  当前这首歌的封面/信息/进度/控制（MusicPlayerView）
//   我的  合集网格（MusicCollectionsView）→ 点进去是合集详情（MusicCollectionDetailView）
// 四张浮层：播放列表、添加到合集、新建合集、音频流转；再加一层盖满页面的搜索。
//
// 【曲库是什么】全部会话里的音频消息，由 MusicLibraryStore 走 TDLib 全局搜索拿
// （空查询 = 全部歌曲）。这个应用里不存在别的「歌」。
//
// 【这一页为什么是状态的家】播放器控制器、曲库、探测、合集订阅都挂在这里，
// 子组件一律只收数据 + 回调（仓库规矩：逻辑不进页面组件的 build）。
//
// 【入口】底栏迷你条点信息区、设置 → 音乐中心。两条都走 navigateToSetting。

const SHEET_NONE: string = '';
const SHEET_PLAYLIST: string = 'playlist';
const SHEET_ADD: string = 'add';
const SHEET_CREATE: string = 'create';
const SHEET_CAST: string = 'cast';
const SHEET_SEARCH: string = 'search';

// 机器人搜索的防抖。实测 bot 200–600ms 回来，350ms 手感上刚好不抢跑。
const BOT_SEARCH_DEBOUNCE_MS: number = 350;

const QUEUE_LIBRARY: string = 'library';
const QUEUE_COLLECTION: string = 'collection';

const TAB_PLAY: number = 0;
const TAB_MINE: number = 1;

const PAGE_INSET: number = 20;
const PAGE_BOTTOM_GAP: number = 16;

@Builder
export function MusicCenterPageBuilder(): void {
  MusicCenterPage();
}

@Component
export struct MusicCenterPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_MUSIC_CENTER_ON) centerOn: boolean = true;

  @State private tab: number = TAB_PLAY;
  // '' = 不在合集详情里。
  @State private detailId: string = '';
  @State private sheet: string = SHEET_NONE;
  @State private query: string = '';
  @State private newName: string = '';
  @State private createFromAdd: boolean = false;
  @State private tracks: MusicTrack[] = [];
  @State private libLoading: boolean = false;
  // 机器人搜索的那一段（曲库之外的来源，见 store/MusicBotSearchApi）。
  @State private botTracks: MusicTrack[] = [];
  @State private botLoading: boolean = false;
  // 会话式机器人那一段（@music_v1bot）。搜索要手点，不跟着输入跑——每搜一次
  // 都真往那个 bot 的会话里发一条 /search。
  @State private chatLabels: string[] = [];
  @State private chatBusy: boolean = false;
  @State private chatError: string = '';
  @State private chatFetching: number = -1;
  @State private collections: MusicCollection[] = [];
  @State private snapshot: MusicPlaybackSnapshot = {
    trackKey: '', index: -1, playing: false, loading: false, positionMs: 0, durationMs: 0
  };
  @State private source: AudioSourceInfo = {
    format: '', sampleRateHz: 0, bitDepth: 0, channels: 0, bitrateKbps: 0, durationSec: 0
  };
  @State private detailTracks: MusicTrack[] = [];
  @State private detailLoading: boolean = false;
  @State private castRows: MusicCastRow[] = [];
  @State private castChip: string = '';
  @State private current: MusicTrack | null = null;
  // 当前曲目的封面路径，'' = 没有内嵌封面或还没取到（播放页退回渐变）。
  @State private coverPath: string = '';

  private navStack: NavPathStack | undefined = undefined;
  private library: MusicLibraryStore = new MusicLibraryStore(getTdClient());
  private player: MusicPlayerController = new MusicPlayerController();
  private unsubLibrary: (() => void) | null = null;
  private unsubPlayer: (() => void) | null = null;
  private unsubCollections: (() => void) | null = null;
  private unsubDevices: (() => void) | null = null;
  // 已经探过音源的那首歌，避免每帧都去问。
  private probedKey: string = '';
  // 详情页正在解析的合集，晚到的结果不能盖掉后点开的那个。
  private detailSeq: number = 0;
  // 当前队列是从哪儿来的：曲库还是某个合集。见 adoptLibraryQueue。
  private queueSource: string = QUEUE_LIBRARY;
  // 机器人搜索的防抖与竞态：输入框每敲一下都发一次查询既浪费也会被 bot 限流；
  // 晚回来的旧查询不能盖掉新的（同 detailSeq 的做法）。
  private botSeq: number = 0;
  private botTimer: number = -1;
  // 本次搜索的 inline_query_id；落地（发消息）时要用，过期了 API 会自己重查。
  private botQueryId: string = '';
  // 落地时用的查询词：queryId 过期后重查要靠它。
  private botQuery: string = '';
  private chatHits: ChatBotHit[] = [];
  private chatListMessageId: number = 0;

  aboutToAppear(): void {
    ensureMusicCollections(this.ctx());
    ensureMusicBotSent(this.ctx());
    // 机器人结果的落地钩子：点播放时先发进收藏夹换回真消息。
    this.player.setMaterializer((track: MusicTrack): Promise<MusicTrack | null> =>
      materializeBotTrack(this.botQuery, this.botQueryId, track.botResultId, Date.now()));
    this.unsubCollections = subscribeMusicCollections((): void => {
      this.collections = musicCollections().slice();
      this.refreshDetail();
    });
    this.unsubLibrary = this.library.subscribe((): void => { this.onLibraryChanged(); });
    this.unsubPlayer = this.player.subscribe((snapshot: MusicPlaybackSnapshot): void => {
      this.snapshot = snapshot;
      this.current = this.player.current();
      this.probeCurrent();
    });
    this.unsubDevices = audioOutputDevices().subscribe((): void => { this.refreshDevices(); });
    this.refreshDevices();
    this.adoptNowPlaying();
    this.library.search('');
  }

  aboutToDisappear(): void {
    if (this.botTimer !== -1) { clearTimeout(this.botTimer); this.botTimer = -1; }
    if (this.unsubLibrary !== null) { this.unsubLibrary(); this.unsubLibrary = null; }
    if (this.unsubPlayer !== null) { this.unsubPlayer(); this.unsubPlayer = null; }
    if (this.unsubCollections !== null) { this.unsubCollections(); this.unsubCollections = null; }
    if (this.unsubDevices !== null) { this.unsubDevices(); this.unsubDevices = null; }
    this.library.close();
    // 控制器只解绑订阅，**不停播**：用户退出这一页时音乐该继续放（底栏迷你条接手）。
    this.player.dispose();
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  // —— 数据 ——

  private onLibraryChanged(): void {
    this.tracks = this.library.getTracks();
    this.libLoading = this.library.getState() === 'loading';
    // 合集详情要按键把歌取回来，曲库里见过的先存一份，能省掉一次 getMessage。
    rememberMusicTracks(this.tracks);
    this.adoptLibraryQueue();
  }

  // 曲库就绪后把它当成播放队列，上一首/下一首因此能在整个曲库里走。
  //
  // 两处不换：
  //   · 队列是从某个合集起播的（那是用户选的范围，不该被一次搜索改掉）；
  //   · 正在放的那首不在这一页结果里（换过去会把它从队列里弄丢，index 变 -1）。
  private adoptLibraryQueue(): void {
    if (this.queueSource !== QUEUE_LIBRARY) {
      return;
    }
    const playing: MusicTrack | null = this.player.current();
    if (playing !== null) {
      const key: string = musicTrackKey(playing.chatId, playing.messageId);
      const present: boolean = this.tracks.some((t: MusicTrack): boolean =>
        trackKeyOf(t) === key);
      if (!present) {
        return;
      }
    }
    this.player.setQueue(this.tracks);
  }

  // 进来之前就在放（从会话页起播的那种）：把那首歌认回来，页面才不会显示「还没有歌曲」。
  // 通道里只有曲名/演唱者/路径，文件 id、大小、格式都没有，所以按曲目键去把原消息取回来。
  private adoptNowPlaying(): void {
    const playing: NowPlaying | null = currentNowPlaying();
    if (playing === null || this.player.current() !== null) {
      return;
    }
    const key: string = musicTrackKey(playing.chatId, playing.messageId);
    resolveMusicTracks([key]).then((tracks: MusicTrack[]): void => {
      if (tracks.length > 0) {
        this.player.adopt(tracks[0]);
      }
    });
  }

  private refreshDevices(): void {
    const devices: AudioOutputDevice[] = audioOutputDevices().devices();
    const activeId: number = audioOutputDevices().activeId();
    const fallbacks: Map<string, string> = new Map<string, string>();
    this.castRows = buildCastRows(devices, activeId, fallbacks);
    this.castChip = castChipName(devices, activeId);
  }

  // 音源信息（格式/码率/采样率/位深）只在换歌时探一次，结果带缓存。
  private probeCurrent(): void {
    const track: MusicTrack | null = this.current;
    if (track === null) {
      this.probedKey = '';
      return;
    }
    const key: string = trackKeyOf(track);
    if (key === this.probedKey) {
      return;
    }
    this.probedKey = key;
    this.loadCover(track);
    probeMusicSource(track).then((info: AudioSourceInfo): void => {
      // 期间又换了歌：这份结果已经不是当前这首的了。
      if (this.probedKey === key) {
        this.source = info;
      }
    });
  }

  // 封面先读缓存（同一张专辑在列表里多半已经取过），没有才发请求。
  private loadCover(track: MusicTrack): void {
    const fileId: number = track.coverFileId;
    this.coverPath = cachedMusicCover(fileId);
    if (fileId <= 0 || this.coverPath !== '') {
      return;
    }
    ensureMusicCover(fileId).then((path: string): void => {
      // 期间换了歌就不要这份了。
      if (path !== '' && this.current?.coverFileId === fileId) {
        this.coverPath = path;
      }
    });
  }

  private detailCollection(): MusicCollection | null {
    return this.collections.find((c: MusicCollection): boolean => c.id === this.detailId) ?? null;
  }

  private refreshDetail(): void {
    const collection: MusicCollection | null = this.detailCollection();
    if (collection === null) {
      this.detailTracks = [];
      this.detailLoading = false;
      return;
    }
    const seq: number = ++this.detailSeq;
    this.detailLoading = true;
    resolveMusicTracks(collection.trackKeys).then((tracks: MusicTrack[]): void => {
      if (seq !== this.detailSeq) {
        return;
      }
      this.detailTracks = tracks;
      this.detailLoading = false;
    });
  }

  // —— 动作 ——

  // 机器人搜索：停手 350ms 再发。清空输入立刻收起这一段，别留着上一次的结果。
  private scheduleBotSearch(query: string): void {
    if (this.botTimer !== -1) {
      clearTimeout(this.botTimer);
      this.botTimer = -1;
    }
    const q: string = query.trim();
    if (q === '') {
      this.botSeq++;
      this.botTracks = [];
      this.botLoading = false;
      return;
    }
    const seq: number = ++this.botSeq;
    this.botLoading = true;
    this.botTimer = setTimeout((): void => {
      this.botTimer = -1;
      searchMusicBot(q).then((res: MusicBotSearchResult): void => {
        // 期间又敲了别的词：这份结果已经过期。
        if (this.botSeq !== seq) {
          return;
        }
        this.botTracks = res.tracks;
        this.botQueryId = res.queryId;
        this.botQuery = q;
        this.botLoading = false;
      });
    }, BOT_SEARCH_DEBOUNCE_MS);
  }

  // 会话式机器人：手点一次 = 往 bot 会话发一条 /search，等它回编号列表。
  private runChatBotSearch(): void {
    const q: string = this.query.trim();
    if (q === '' || this.chatBusy) {
      return;
    }
    this.chatBusy = true;
    this.chatError = '';
    this.chatLabels = [];
    this.chatHits = [];
    chatBotSearch(q).then((res: ChatBotSearchOutcome): void => {
      this.chatBusy = false;
      // 期间把搜索词改了：这份结果已经不对应界面上的词了，丢掉。
      if (this.query.trim() !== q) {
        return;
      }
      if (res.error !== '') {
        this.chatError = this.chatBotErrorText(res.error);
        return;
      }
      this.chatHits = res.hits;
      this.chatListMessageId = res.listMessageId;
      this.chatLabels = res.hits.map((h: ChatBotHit): string => h.label);
    });
  }

  // 三种失败要分清：连不上 / 没响应 / 回复读不懂。
  // 最后一种尤其不能说成"没搜到"——那是 bot 改了版式，我们得看得见。
  private chatBotErrorText(code: string): string {
    if (code === CHAT_BOT_ERR_OFFLINE) {
      return str('mc_search_chatbot_offline', MUSIC_CHAT_BOT_USERNAME);
    }
    if (code === CHAT_BOT_ERR_UNREADABLE) {
      return str('mc_search_chatbot_unreadable', MUSIC_CHAT_BOT_USERNAME);
    }
    return str('mc_search_chatbot_timeout', MUSIC_CHAT_BOT_USERNAME);
  }

  // 点一条：点 bot 那个编号按钮，等它把音频发过来，然后就是一首普通的歌。
  private pickChatBotHit(index: number): void {
    if (index < 0 || index >= this.chatHits.length || this.chatFetching !== -1) {
      return;
    }
    this.chatFetching = index;
    this.chatError = '';
    chatBotFetch(this.chatListMessageId, this.chatHits[index]).then(
      (track: MusicTrack | null): void => {
        this.chatFetching = -1;
        if (track === null) {
          this.chatError = str('mc_search_chatbot_failed');
          return;
        }
        // 已经是一条真音频消息了，之后和曲库里的歌没有区别。
        rememberMusicTracks([track]);
        this.player.setQueue([track]);
        this.player.playAt(0);
        this.tab = TAB_PLAY;
        this.detailId = '';
        this.closeSheet();
      });
  }

  // 机器人结果起播。**队列只放机器人这一段**：把它和曲库拼在一起的话，
  // 「下一首」会从一首云端歌跳到你自己会话里的歌，来源混了反而难理解。
  //
  // 真正的「发消息换成真曲目」在 MusicPlayerController.playAt 里做（那是所有
  // 播放的唯一漏斗，上一首/下一首才能一起生效），这里只管把队列交过去。
  private playFromBot(index: number): void {
    this.queueSource = QUEUE_LIBRARY;
    this.player.setQueue(this.botTracks);
    this.player.playAt(index);
    this.tab = TAB_PLAY;
    this.detailId = '';
    this.closeSheet();
  }

  private playFromLibrary(index: number): void {
    this.queueSource = QUEUE_LIBRARY;
    this.player.setQueue(this.tracks);
    this.player.playAt(index);
    this.tab = TAB_PLAY;
    this.detailId = '';
    this.closeSheet();
  }

  private playFromDetail(index: number): void {
    this.queueSource = QUEUE_COLLECTION;
    this.player.setQueue(this.detailTracks);
    this.player.playAt(index);
    this.tab = TAB_PLAY;
    this.detailId = '';
  }

  private shuffleDetail(): void {
    if (this.detailTracks.length === 0) {
      return;
    }
    this.playFromDetail(Math.floor(Math.random() * this.detailTracks.length));
  }

  private closeSheet(): void {
    this.sheet = SHEET_NONE;
    this.newName = '';
    this.createFromAdd = false;
  }

  private confirmCreate(): void {
    const created: MusicCollection | null = createCollection(this.newName);
    if (created === null) {
      return;   // 空名或重名，判据在 musicCollectionModel
    }
    // 从「添加到合集」进来的：建好顺手把这首歌放进去，人不用再点一次。
    if (this.createFromAdd && this.snapshot.trackKey !== '') {
      addTrackToCollectionById(created.id, this.snapshot.trackKey);
      this.sheet = SHEET_ADD;
      this.newName = '';
      this.createFromAdd = false;
      return;
    }
    this.closeSheet();
    this.tab = TAB_MINE;
    this.detailId = created.id;
    this.refreshDetail();
  }

  private deleteDetail(): void {
    const collection: MusicCollection | null = this.detailCollection();
    if (collection === null) {
      return;
    }
    deleteCollection(collection.id);
    this.detailId = '';
  }

  // 音源徽标：回到这首歌所在的那条消息。navigateToChat 是所有会话入口的唯一漏斗。
  private openInChat(): void {
    const track: MusicTrack | null = this.current;
    if (track === null || track.chatId === 0) {
      return;
    }
    const params: Record<string, Object> = { 'chatId': track.chatId, 'jumpTo': track.messageId };
    navigateToChat(params, 'navbar').catch(logChatNavFailure);
  }

  private goBack(): void {
    const stack: NavPathStack | undefined = this.navStack;
    if (stack !== undefined) {
      stack.pop();
    }
  }

  // 返回键：先关浮层，再退出合集详情，最后才出栈。
  private onBack(): boolean {
    if (this.sheet !== SHEET_NONE) {
      this.closeSheet();
      return true;
    }
    if (this.detailId !== '') {
      this.detailId = '';
      return true;
    }
    return false;
  }

  // —— 画 ——

  // 背景：封面色的两团光。设计稿里页面底色就是封面色的延伸。
  @Builder
  glow() {
    Stack() {
      Column()
        .width(360).height(360).borderRadius(180)
        .backgroundColor(musicGlowColors(this.current).from)
        .opacity(0.5).blur(70)
        .offset({ x: -120, y: -200 });
      Column()
        .width(320).height(320).borderRadius(160)
        .backgroundColor(musicGlowColors(this.current).to)
        .opacity(0.4).blur(80)
        .offset({ x: 130, y: 60 });
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  tabsBar() {
    Row() {
      if (this.detailId === '') {
        Row({ space: 2 }) {
          this.tabPill($r('app.string.mc_tab_play'), TAB_PLAY);
          this.tabPill($r('app.string.mc_tab_mine'), TAB_MINE);
        }
        .padding(3).borderRadius(20)
        .backgroundColor($r('app.color.tab_pill_bg'))
        .border({ width: 0.5, color: $r('app.color.divider') });
      } else {
        Text($r('app.string.mc_my_collections'))
          .fontSize(14).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%').height(38).margin({ top: 14 })
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  tabPill(label: ResourceStr, index: number) {
    Text(label)
      .fontSize(14).fontWeight(FontWeight.Bold)
      .fontColor(this.tab === index ? COLOR_ON_PRIMARY : COLOR_TEXT_PRIMARY)
      .textAlign(TextAlign.Center)
      .height(32).padding({ left: 22, right: 22 })
      .borderRadius(16)
      .backgroundColor(this.tab === index ? COLOR_PRIMARY : Color.Transparent)
      .onClick((): void => {
        this.tab = index;
        if (index === TAB_PLAY) {
          this.detailId = '';
        }
      });
  }

  @Builder
  body() {
    if (this.detailId !== '' && this.detailCollection() !== null) {
      Scroll() {
        Column() {
          MusicCollectionDetailView({
            collection: this.detailCollection()!,
            tracks: this.detailTracks,
            playingKey: this.snapshot.trackKey,
            playing: this.snapshot.playing,
            loading: this.detailLoading,
            onPlayAll: (): void => { this.playFromDetail(0); },
            onShuffle: (): void => { this.shuffleDetail(); },
            onPlay: (index: number): void => { this.playFromDetail(index); },
            onRemove: (trackKey: string): void => {
              removeTrackFromCollectionById(this.detailId, trackKey);
            },
            onDelete: (): void => { this.deleteDetail(); }
          });
        }
        .width('100%').padding({ top: 8, bottom: 50 });
      }
      .layoutWeight(1).width('100%')
      .scrollBar(BarState.Off).align(Alignment.Top);
    } else if (this.tab === TAB_MINE) {
      Scroll() {
        Column() {
          MusicCollectionsView({
            collections: this.collections,
            onSelect: (collectionId: string): void => {
              this.detailId = collectionId;
              this.refreshDetail();
            },
            onCreate: (): void => {
              this.createFromAdd = false;
              this.sheet = SHEET_CREATE;
            }
          });
        }
        .width('100%').padding({ top: 18, bottom: 50 });
      }
      .layoutWeight(1).width('100%')
      .scrollBar(BarState.Off).align(Alignment.Top);
    } else {
      MusicPlayerView({
        track: this.current,
        snapshot: this.snapshot,
        source: this.source,
        centerOn: this.centerOn,
        castLabel: this.castChip !== '' ? this.castChip : str('mc_cast'),
        coverPath: this.coverPath,
        inCollection: this.snapshot.trackKey !== '' && trackInAnyCollection(this.snapshot.trackKey),
        onToggle: (): void => { this.player.toggle(); },
        onPrev: (): void => { this.player.prev(); },
        onNext: (): void => { this.player.next(); },
        onSeek: (fraction: number): void => { this.player.seekFraction(fraction); },
        onOpenPlaylist: (): void => { this.sheet = SHEET_PLAYLIST; },
        onOpenAddTo: (): void => { this.sheet = SHEET_ADD; },
        onOpenCast: (): void => {
          this.refreshDevices();
          this.sheet = SHEET_CAST;
        },
        onOpenInChat: (): void => { this.openInChat(); }
      });
    }
  }

  @Builder
  overlays() {
    // 遮罩。搜索层是盖满整页的，自己就是遮罩，不需要再来一层。
    if (this.sheet !== SHEET_NONE && this.sheet !== SHEET_SEARCH) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => { this.closeSheet(); });
    }
    if (this.sheet === SHEET_PLAYLIST) {
      MusicPlaylistSheet({
        tracks: this.tracks,
        playingKey: this.snapshot.trackKey,
        playing: this.snapshot.playing,
        bottomInset: this.bottomSafe,
        onPlay: (index: number): void => { this.playFromLibrary(index); }
      });
    }
    if (this.sheet === SHEET_ADD) {
      MusicAddToSheet({
        collections: this.collections,
        trackKey: this.snapshot.trackKey,
        trackTitle: this.current?.title ?? '',
        trackArtist: this.current?.artist ?? '',
        bottomInset: this.bottomSafe,
        onToggle: (collectionId: string): void => {
          toggleTrackInCollectionById(collectionId, this.snapshot.trackKey);
        },
        onCreate: (): void => {
          this.createFromAdd = true;
          this.sheet = SHEET_CREATE;
        }
      });
    }
    if (this.sheet === SHEET_CAST) {
      MusicCastSheet({ rows: this.castRows, bottomInset: this.bottomSafe });
    }
    if (this.sheet === SHEET_CREATE) {
      // 新建合集是屏幕中间的一张卡，不是底部浮层——外面这层负责把它顶到中间。
      Column() {
        MusicCreateDialog({
          fromAddTo: this.createFromAdd,
          trackTitle: this.current?.title ?? '',
          name: this.newName,
          onNameChange: (name: string): void => { this.newName = name; },
          onCancel: (): void => { this.closeSheet(); },
          onConfirm: (): void => { this.confirmCreate(); }
        });
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: PAGE_INSET, right: PAGE_INSET });
    }
    if (this.sheet === SHEET_SEARCH) {
      MusicSearchOverlay({
        query: this.query,
        tracks: this.tracks,
        loading: this.libLoading,
        botTracks: this.botTracks,
        botLoading: this.botLoading,
        botName: MUSIC_BOT_USERNAME,
        chatBotName: MUSIC_CHAT_BOT_USERNAME,
        chatLabels: this.chatLabels,
        chatBusy: this.chatBusy,
        chatError: this.chatError,
        chatFetching: this.chatFetching,
        playingKey: this.snapshot.trackKey,
        playing: this.snapshot.playing,
        topInset: this.topSafe,
        bottomInset: this.bottomSafe,
        onQueryChange: (query: string): void => {
          this.query = query;
          this.library.search(query);
          this.scheduleBotSearch(query);
          // 换词了：上一轮 bot 的结果不再对应，收掉（但**不自动重搜**）。
          this.chatLabels = [];
          this.chatHits = [];
          this.chatError = '';
        },
        onClose: (): void => {
          this.query = '';
          this.library.search('');
          this.scheduleBotSearch('');
          this.closeSheet();
        },
        onPlay: (index: number): void => { this.playFromLibrary(index); },
        onPlayBot: (index: number): void => { this.playFromBot(index); },
        onChatSearch: (): void => { this.runChatBotSearch(); },
        onChatPick: (index: number): void => { this.pickChatBotHit(index); },
        onLoadMore: (): void => { this.library.loadMore(); }
      });
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        this.glow();
        Column() {
          MusicCenterTopBar({
            centerOn: this.centerOn,
            onBack: (): void => {
              if (!this.onBack()) {
                this.goBack();
              }
            },
            onToggleCenter: (): void => {
              setBoolean(KEY_MUSIC_CENTER_ON, !this.centerOn);
              this.closeSheet();
            },
            onSearch: (): void => { this.sheet = SHEET_SEARCH; }
          });
          this.tabsBar();
          this.body();
        }
        .width('100%').height('100%')
        // 底部只留系统安全区 + 一点余量：本页是推进设置栈的子页，底栏 dock 不在
        // 它上面（同 ArchivePage 的 reserveDockSpace: false）。
        .padding({
          left: PAGE_INSET, right: PAGE_INSET,
          top: this.topSafe, bottom: this.bottomSafe + PAGE_BOTTOM_GAP
        });
        this.overlays();
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.page_bg'))
      .clip(true)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
    // 顶栏是自绘的（音乐中心开关那颗 pill 在 HDS 标题栏里放不下，见 [[hds-titlebar-limits]]）。
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
    })
    .onBackPressed((): boolean => this.onBack())
    .width('100%').height('100%');
  }
}
