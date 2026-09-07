import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_GIF, KEY_REDUCE_ANIM
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { EMOJI_CONTENT_HEIGHT } from '../../util/drawerMetrics';
import { logE } from '../../util/log';
import { guardKey } from '../../util/keyGuard';
import { InlineQueryPage, InlineResultRow } from '../../store/BotApi';
import { searchGifs } from '../../store/GifSearchApi';

// 一格 GIF。**两种来源共用这一个形状**：
//   已保存  fileId>0、resultId===''  → 用 sendAnimation(fileId) 发
//   搜索/热门 fileId 是动图文件 id（用来下预览），resultId!=='' → 用
//           sendInlineResult(queryId, resultId) 发
// 合成一个类型是因为它们在同一条网格里混排（已保存在上、热门在下），拆两个
// 类型会让数据源和格子渲染各分叉一次。
export interface GifItem {
  fileId: number;    // the animation file (what gets sent / previewed)
  width: number;
  height: number;
  duration: number;
  thumbPath: string; // raster thumbnail ('' while downloading)
  srcPath: string;   // local animation source ('' until downloaded)
  queryId: string;   // 内联结果所属的查询（已保存的为 ''）
  resultId: string;  // 内联结果 id（已保存的为 ''）
  // 非空 = 这一格其实是**分区标题**（「已保存的 GIF」/「热门 GIF」），整行铺满、
  // 不是真的 GIF。做成同一个数组里的哨兵项而不是两个 Grid：两段必须在同一条
  // 滚动里连续排（用户要的是"往下滑出现热门"），拆成两个容器就各滚各的了。
  header: string;
}

// 标题项的哨兵：fileId 0，下载与点击路径都据此跳过。
function headerItem(title: string): GifItem {
  return {
    fileId: 0, width: 0, height: 0, duration: 0,
    thumbPath: '', srcPath: '', queryId: '', resultId: '', header: title
  };
}

const GIF_SKELETONS: number[] = [0, 1, 2, 3, 4, 5];
const GIF_COLUMNS: number = 2;
const GIF_GRID_GAP: number = 6;
const GIF_GRID_SIDE_PADDING: number = 10;
const GIF_CELL_ASPECT: number = 1.45;

// Saved GIF lists can grow large. Keep native players limited to the visible
// rows instead of mounting every GIF as soon as the drawer opens.
class GifDataSource implements IDataSource {
  private items: GifItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): GifItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }

  update(next: GifItem[]): void {
    const previous: GifItem[] = this.items;
    this.items = next;

    if (previous.length === next.length) {
      let identityChanged: boolean = false;
      const changes: DataOperation[] = [];
      for (let i = 0; i < next.length; i++) {
        if (previous[i].fileId !== next[i].fileId) {
          identityChanged = true;
          break;
        }
        if (previous[i].thumbPath !== next[i].thumbPath || previous[i].srcPath !== next[i].srcPath ||
          previous[i].duration !== next[i].duration || previous[i].width !== next[i].width ||
          previous[i].height !== next[i].height) {
          changes.push({ type: DataOperationType.CHANGE, index: i } as DataChangeOperation);
        }
      }
      if (!identityChanged) {
        this.notify(changes);
        return;
      }
    }

    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  private notify(operations: DataOperation[]): void {
    if (operations.length === 0) {
      return;
    }
    for (const listener of this.listeners) {
      listener.onDatasetChange(operations);
    }
  }
}

// Saved-GIF picker for the input panel. It keeps a static thumbnail when
// autoplay/reduced-motion/power-saving settings disable playback.
@Component
export struct GifPicker {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  onPick: (g: GifItem) => void = (): void => {};
  @Prop @Watch('onPlaybackSettingChanged') active: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) @Watch('onPlaybackSettingChanged') autoplayGif: boolean = true;
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onPlaybackSettingChanged') powerSaving: boolean = false;
  @StorageProp(KEY_REDUCE_ANIM) @Watch('onPlaybackSettingChanged') reduceAnimations: boolean = false;
  @State gifs: GifItem[] = [];
  @State loadState: string = 'loading'; // loading | ready | error
  @State errorText: string = '';
  @State sendingGifId: number = 0;
  @State pressedGifId: number = 0;
  @State gridWidth: number = 0;
  private loadSeq: number = 0;
  private disposed: boolean = false;
  private sourceLoading: Set<number> = new Set<number>();
  private sendGuardTimer: number = -1;
  private gridData: GifDataSource = new GifDataSource();
  private visibleFirst: number = 0;
  private visibleLast: number = GIF_SKELETONS.length - 1;

  // ── GIF 搜索 / 热门（见 store/GifSearchApi 的文件头：Telegram 没有独立的
  // GIF 市场接口，那个"市场"就是内联机器人 @gif）──────────────────────────
  //
  // 列表的组织：**已保存在最上，往下接热门**，同一条网格里混排；顶部搜索框有词
  // 时整条换成搜索结果，清空再换回来。
  //
  // 内联查询要带当前会话 id（机器人据此判断能不能在这里发），由外层传进来。
  @Prop chatId: number;
  @State searchText: string = '';
  // 搜索态：this.gifs 换成了结果，browseBackup 存着「已保存 + 热门」那份。
  @State searchActive: boolean = false;
  private browseBackup: GifItem[] = [];
  private searchTimer: number = -1;
  private searchSeq: number = 0;
  private trendingRequested: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.load();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.loadSeq++;
    this.sourceLoading.clear();
    if (this.sendGuardTimer !== -1) {
      clearTimeout(this.sendGuardTimer);
      this.sendGuardTimer = -1;
    }
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.searchSeq++;
  }

  private playbackEnabled(): boolean {
    return this.active && this.autoplayGif && !this.powerSaving && !this.reduceAnimations;
  }

  private onPlaybackSettingChanged(): void {
    if (this.playbackEnabled()) {
      this.requestVisibleSources();
    }
  }

  private localPath(file: TdObject | undefined): string {
    const local = file !== undefined ? (file['local'] as TdObject | undefined) : undefined;
    if (local === undefined || !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
      return '';
    }
    return (local['path'] as string | undefined) ?? '';
  }

  private publishGifs(next: GifItem[]): void {
    this.gifs = next;
    this.gridData.update(next);
  }

  private gifCellWidth(): number {
    const available: number = this.gridWidth > 0 ? this.gridWidth : 360;
    const gaps: number = GIF_GRID_SIDE_PADDING * 2 + GIF_GRID_GAP * (GIF_COLUMNS - 1);
    return Math.max(120, Math.floor((available - gaps) / GIF_COLUMNS));
  }

  private gifCellHeight(): number {
    return Math.max(84, Math.floor(this.gifCellWidth() / GIF_CELL_ASPECT));
  }

  private load(): void {
    const seq: number = ++this.loadSeq;
    this.loadState = 'loading';
    this.errorText = '';
    const req: TdRequest = { '@type': 'getSavedAnimations' };
    getTdClient().send(req).then((res: TdObject) => {
      if (this.disposed || seq !== this.loadSeq) {
        return;
      }
      const raw = (res['animations'] as TdObject[] | undefined) ?? [];
      const items: GifItem[] = [];
      for (const a of raw) {
        const file = a['animation'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        items.push({
          fileId,
          width: (a['width'] as number | undefined) ?? 0,
          height: (a['height'] as number | undefined) ?? 0,
          duration: (a['duration'] as number | undefined) ?? 0,
          thumbPath: '',
          srcPath: this.localPath(file),
          queryId: '', resultId: '', header: ''
        });
      }
      // Publish first, then start downloads. Previously a very fast thumbnail
      // completion could patch the old empty array and the image stayed blank.
      // 有已保存的才挂标题——一条都没有时挂个空标题比不挂更难看。
      this.publishGifs(items.length > 0
        ? [headerItem(str('gif_section_saved')), ...items] : items);
      this.loadState = 'ready';
      for (const a of raw) {
        const file = a['animation'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        this.downloadThumb(fileId, a['thumbnail'] as TdObject | undefined, seq);
      }
      if (this.playbackEnabled()) {
        this.requestVisibleSources();
      }
      // 已保存落地之后再接热门：先让用户自己的那几个立刻可见，网络那一跳
      // 不挡着首屏。
      this.loadTrending(seq);
    }).catch((e: TdError) => {
      if (this.disposed || seq !== this.loadSeq) {
        return;
      }
      logE(`GifPicker.getSavedAnimations failed: ${e.message}`);
      this.errorText = str('gif_load_failed');
      this.loadState = 'error';
    });
  }

  // 内联结果（热门 / 搜索）转成格子。fileId 用**动图本体**的文件 id，
  // 于是 requestVisibleSources / downloadSource 那套现成的预览下载一行不用改
  // 就能复用；发送走的是 queryId+resultId，与已保存那条分开。
  private itemsFromPage(page: InlineQueryPage): GifItem[] {
    const out: GifItem[] = [];
    for (const row of page.rows) {
      if (row.animationFileId === 0) {
        continue;
      }
      out.push({
        fileId: row.animationFileId,
        width: 0, height: 0, duration: 0,
        thumbPath: '', srcPath: '',
        queryId: page.queryId, resultId: row.resultId, header: ''
      });
    }
    return out;
  }

  // 热门 GIF：空 query 问同一个机器人。**失败静默**——它只是"已保存"下面的
  // 附加内容，拿不到就当没有，不能把整个面板打成错误态。
  private loadTrending(seq: number): void {
    if (this.trendingRequested || this.chatId === 0) {
      return;
    }
    this.trendingRequested = true;
    searchGifs(this.chatId, '').then((page: InlineQueryPage): void => {
      if (this.disposed || seq !== this.loadSeq || this.searchActive) {
        return;
      }
      const extra: GifItem[] = this.itemsFromPage(page);
      if (extra.length === 0) {
        return;
      }
      // 追加而不是替换：已保存那几个必须留在最上面。**在当前列表尾部追加**而不是
      // 重新拼一遍，否则已保存那几格刚下好的缩略图/预览补丁会被整片覆盖掉。
      this.publishGifs([...this.gifs, headerItem(str('gif_section_trending')), ...extra]);
      for (const it of extra) {
        this.downloadThumbById(it.fileId, seq);
      }
      if (this.playbackEnabled()) {
        this.requestVisibleSources();
      }
    }).catch((e: TdError): void => {
      logE(`GifPicker.loadTrending failed: ${e.message}`);
    });
  }

  // 搜索框回调。防抖 320ms，与 @bot 内联那条一致（ComposerSuggestionState）。
  private onSearchChanged(value: string): void {
    this.searchText = value;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    const query: string = value.trim();
    if (query === '') {
      this.exitSearch();
      return;
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.runSearch(query);
    }, 320);
  }

  private exitSearch(): void {
    this.searchSeq++;
    if (!this.searchActive) {
      return;
    }
    this.searchActive = false;
    // 回到「已保存 + 热门」那份快照。搜索期间对结果的补丁不回灌浏览态，
    // 那些格子下次进搜索会重新下。
    this.publishGifs(this.browseBackup);
    this.browseBackup = [];
    this.loadState = 'ready';
  }

  private runSearch(query: string): void {
    const seq: number = ++this.searchSeq;
    if (!this.searchActive) {
      this.browseBackup = this.gifs;
      this.searchActive = true;
    }
    this.loadState = 'loading';
    searchGifs(this.chatId, query).then((page: InlineQueryPage): void => {
      if (this.disposed || seq !== this.searchSeq || !this.searchActive) {
        return;
      }
      const items: GifItem[] = this.itemsFromPage(page);
      this.publishGifs(items);
      this.loadState = 'ready';
      for (const it of items) {
        this.downloadThumbById(it.fileId, this.loadSeq);
      }
      if (this.playbackEnabled()) {
        this.requestVisibleSources();
      }
    }).catch((e: TdError): void => {
      if (this.disposed || seq !== this.searchSeq) {
        return;
      }
      logE(`GifPicker.runSearch failed: ${e.message}`);
      this.publishGifs([]);
      this.loadState = 'ready';
    });
  }

  // 内联结果只给了文件 id（不像已保存那条带着 thumbnail 对象），所以单开一个
  // 按 id 下的入口；已保存那条解析完 thumbnail 之后也走到这里。
  private downloadThumbById(gifFileId: number, seq: number): void {
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = gifFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      if (this.disposed || seq !== this.loadSeq) {
        return;
      }
      const path = this.localPath(f);
      if (path === '') {
        return;
      }
      this.publishGifs(this.gifs.map((g: GifItem): GifItem =>
        g.fileId === gifFileId
          ? {
            fileId: g.fileId, width: g.width, height: g.height, duration: g.duration,
            thumbPath: g.thumbPath === '' ? path : g.thumbPath, srcPath: path,
            queryId: g.queryId, resultId: g.resultId, header: g.header
          }
          : g));
    }).catch((e: TdError) => {
      logE(`GifPicker.downloadThumbById failed: ${e.message}`);
    });
  }

  private downloadThumb(gifFileId: number, thumb: TdObject | undefined, seq: number): void {
    const format = thumb !== undefined ? (thumb['format'] as TdObject | undefined) : undefined;
    const formatName = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
    const isRaster = formatName === 'thumbnailFormatJpeg' || formatName === 'thumbnailFormatWebp'
      || formatName === 'thumbnailFormatPng';
    const thumbFile = thumb !== undefined && isRaster ? (thumb['file'] as TdObject | undefined) : undefined;
    const thumbFileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    if (thumbFileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = thumbFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      if (this.disposed || seq !== this.loadSeq) {
        return;
      }
      const path = this.localPath(f);
      if (path === '') {
        return;
      }
      this.publishGifs(this.gifs.map((g: GifItem): GifItem =>
        g.fileId === gifFileId
          ? {
            fileId: g.fileId, width: g.width, height: g.height, duration: g.duration,
            thumbPath: path, srcPath: g.srcPath,
            queryId: g.queryId, resultId: g.resultId, header: g.header
          }
          : g));
    }).catch((e: TdError) => {
      logE(`GifPicker.downloadThumb failed: ${e.message}`);
    });
  }

  private requestVisibleSources(): void {
    if (!this.playbackEnabled()) {
      return;
    }
    const seq: number = this.loadSeq;
    const first: number = Math.max(0, this.visibleFirst);
    const last: number = Math.min(this.gifs.length - 1,
      Math.max(this.visibleLast, first + GIF_SKELETONS.length - 1) + GIF_COLUMNS);
    for (let i = first; i <= last; i++) {
      const g: GifItem = this.gifs[i];
      if (g.fileId !== 0 && g.srcPath === '' && !this.sourceLoading.has(g.fileId)) {
        this.downloadSource(g.fileId, seq);
      }
    }
  }

  private downloadSource(gifFileId: number, seq: number): void {
    this.sourceLoading.add(gifFileId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = gifFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      this.sourceLoading.delete(gifFileId);
      if (this.disposed || seq !== this.loadSeq) {
        return;
      }
      const path = this.localPath(f);
      if (path === '') {
        return;
      }
      this.publishGifs(this.gifs.map((g: GifItem): GifItem =>
        g.fileId === gifFileId
          ? {
            fileId: g.fileId, width: g.width, height: g.height, duration: g.duration,
            thumbPath: g.thumbPath, srcPath: path,
            queryId: g.queryId, resultId: g.resultId, header: g.header
          }
          : g));
    }).catch((e: TdError) => {
      this.sourceLoading.delete(gifFileId);
      logE(`GifPicker.downloadSource failed: ${e.message}`);
    });
  }

  private pickGif(g: GifItem): void {
    if (this.sendingGifId !== 0 || g.header !== '' || g.fileId === 0) {
      return;
    }
    this.sendingGifId = g.fileId;
    this.onPick(g);
    this.sendGuardTimer = setTimeout((): void => {
      this.sendGuardTimer = -1;
      this.sendingGifId = 0;
    }, 450);
  }

  @Builder
  stateMessage(symbol: Resource, title: string, detail: string, retry: boolean) {
    Column({ space: 8 }) {
      SymbolGlyph(symbol).fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(detail).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      if (retry) {
        Text($r('app.string.settings_reload'))
          .fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.selected_pill')).borderRadius(16)
          .onClick(() => { this.load(); });
      }
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center);
  }

  // 顶部搜索框。空着 = 浏览态（已保存在上、热门在下），有词 = 搜索结果。
  @Builder
  searchBar() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
      TextInput({ text: this.searchText, placeholder: $r('app.string.gif_search_hint') })
        .layoutWeight(1).height(36).fontSize(15)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .onChange((v: string): void => { this.onSearchChanged(v); });
      if (this.searchText !== '') {
        SymbolGlyph($r('sys.symbol.xmark_circle')).fontSize(17).fontColor([COLOR_ICON_SECONDARY])
          .onClick((): void => { this.onSearchChanged(''); });
      }
    }
    // **不能写 .width('100%') + 左右 margin**：ArkUI 先按父容器的 100% 算出宽，
    // 再把 margin 加上去，于是整条比可用宽度还宽、两侧顶死（和 ChatSearchBars
    // 的 SearchHeader 同一个坑，那边也是用 calc 解决的）。
    .width('calc(100% - 24vp)').height(36)
    .padding({ left: 12, right: 12 })
    .margin({ left: 12, right: 12, top: 8, bottom: 4 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(18)
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.searchBar();
      if (this.loadState === 'loading') {
        Grid() {
          ForEach(GIF_SKELETONS, (idx: number) => {
            GridItem() {
              Column()
                .width('100%').aspectRatio(GIF_CELL_ASPECT)
                .backgroundColor($r('app.color.surface_alt')).borderRadius(8)
                .opacity(idx % 2 === 0 ? 0.85 : 0.55);
            }
          }, (idx: number) => `gif_skeleton_${idx}`);
        }
        .columnsTemplate('1fr 1fr').columnsGap(GIF_GRID_GAP).rowsGap(GIF_GRID_GAP)
        .padding({ left: GIF_GRID_SIDE_PADDING, right: GIF_GRID_SIDE_PADDING, top: 10, bottom: 8 })
        .width('100%').height('100%');
      } else if (this.loadState === 'error') {
        this.stateMessage($r('sys.symbol.exclamationmark_circle'), this.errorText,
          str('check_network_retry'), true);
      } else if (this.gifs.length === 0) {
        this.stateMessage($r('sys.symbol.video'),
          this.searchActive ? str('gif_search_none') : str('gif_none_saved'),
          this.searchActive ? '' : str('gif_none_saved_sub'), false);
      } else {
        Grid() {
          LazyForEach(this.gridData, (g: GifItem) => {
            if (g.header !== '') {
              // 分区标题：占满整行。columnStart/columnEnd 是 Grid 给的跨列能力，
              // 两列模板下 0..1 就是整行。
              GridItem() {
                Text(g.header)
                  .fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_SECONDARY)
                  .width('100%')
                  .padding({ left: 2, top: 6, bottom: 2 });
              }
              .columnStart(0).columnEnd(GIF_COLUMNS - 1)
              .height(28);
            } else {
            GridItem() {
              Stack({ alignContent: Alignment.BottomEnd }) {
                if (this.playbackEnabled() && g.srcPath !== '') {
                  SmartLoopVideo({
                    videoPath: g.srcPath, thumbPath: g.thumbPath,
                    boxWidth: this.gifCellWidth(), boxHeight: this.gifCellHeight(), powerCategory: 'gif'
                  });
                } else if (g.thumbPath !== '') {
                  Image(`file://${g.thumbPath}`).draggable(false)
                    .width('100%').height('100%').objectFit(ImageFit.Cover);
                } else {
                  Column() {
                    LoadingProgress().width(20).height(20).color(COLOR_ICON_SECONDARY);
                  }
                  .width('100%').height('100%')
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.surface_alt'));
                }
                if (this.sendingGifId === g.fileId) {
                  Row() {
                    LoadingProgress().width(20).height(20).color(Color.White);
                  }
                  .width('100%').height('100%').justifyContent(FlexAlign.Center)
                  .backgroundColor('#33000000');
                } else if (g.duration > 0) {
                  Text(`${g.duration}s`)
                    .fontSize(10).fontWeight(FontWeight.Medium).fontColor(Color.White)
                    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                    .backgroundColor('#73000000').borderRadius(5)
                    .margin({ right: 6, bottom: 6 });
                }
              }
              .width('100%').height('100%')
              .borderRadius(8).clip(true)
              .opacity(this.pressedGifId === g.fileId ? 0.8 : 1)
              .scale({
                x: this.pressedGifId === g.fileId ? 0.97 : 1,
                y: this.pressedGifId === g.fileId ? 0.97 : 1
              })
              .animation({
                duration: this.reduceAnimations || this.powerSaving ? 0 : 100,
                curve: Curve.EaseOut
              })
              .onTouch((event: TouchEvent): void => {
                if (event.type === TouchType.Down) {
                  this.pressedGifId = g.fileId;
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedGifId = 0;
                }
              })
              .onClick(() => { this.pickGif(g); });
            }
            .height(this.gifCellHeight());
            }
          }, (g: GifItem, index: number) => guardKey('saved_gifs', index, `${g.fileId}_${g.resultId}_${g.header}`));
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(GIF_GRID_GAP).rowsGap(GIF_GRID_GAP)
        .padding({ left: GIF_GRID_SIDE_PADDING, right: GIF_GRID_SIDE_PADDING, top: 8, bottom: 8 })
        .width('100%').height('100%')
        .onScrollIndex((first: number, last: number): void => {
          this.visibleFirst = first;
          this.visibleLast = last;
          this.requestVisibleSources();
        })
        .onAreaChange((_old: Area, area: Area): void => {
          const width: number = area.width as number;
          if (width > 0 && Math.abs(width - this.gridWidth) > 0.5) {
            this.gridWidth = width;
          }
        });
      }
    }
    // 高度跟着抽屉的内容区走（见 util/drawerMetrics）。写死过一次 241，
    // 抽屉从 300 压到 260 之后就会溢出。
    .width('100%').height(EMOJI_CONTENT_HEIGHT)
    .constraintSize({ minHeight: EMOJI_CONTENT_HEIGHT, maxHeight: EMOJI_CONTENT_HEIGHT });
  }
}
