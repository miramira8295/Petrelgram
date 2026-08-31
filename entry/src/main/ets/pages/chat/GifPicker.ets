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

export interface GifItem {
  fileId: number;    // the animation file (what gets sent)
  width: number;
  height: number;
  duration: number;
  thumbPath: string; // raster thumbnail ('' while downloading)
  srcPath: string;   // local animation source ('' until downloaded)
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
          srcPath: this.localPath(file)
        });
      }
      // Publish first, then start downloads. Previously a very fast thumbnail
      // completion could patch the old empty array and the image stayed blank.
      this.publishGifs(items);
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
    }).catch((e: TdError) => {
      if (this.disposed || seq !== this.loadSeq) {
        return;
      }
      logE(`GifPicker.getSavedAnimations failed: ${e.message}`);
      this.errorText = str('gif_load_failed');
      this.loadState = 'error';
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
            thumbPath: path, srcPath: g.srcPath
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
      if (g.srcPath === '' && !this.sourceLoading.has(g.fileId)) {
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
            thumbPath: g.thumbPath, srcPath: path
          }
          : g));
    }).catch((e: TdError) => {
      this.sourceLoading.delete(gifFileId);
      logE(`GifPicker.downloadSource failed: ${e.message}`);
    });
  }

  private pickGif(g: GifItem): void {
    if (this.sendingGifId !== 0) {
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

  build() {
    Column() {
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
        this.stateMessage($r('sys.symbol.video'), str('gif_none_saved'),
          str('gif_none_saved_sub'), false);
      } else {
        Grid() {
          LazyForEach(this.gridData, (g: GifItem) => {
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
          }, (g: GifItem, index: number) => guardKey('saved_gifs', index, `${g.fileId}`));
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
