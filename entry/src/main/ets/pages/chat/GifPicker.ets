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
import { probeHit } from '../../util/panelProbe';
import { logE } from '../../util/log';

export interface GifItem {
  fileId: number;    // the animation file (what gets sent)
  width: number;
  height: number;
  duration: number;
  thumbPath: string; // raster thumbnail ('' while downloading)
  srcPath: string;   // local animation source ('' until downloaded)
}

const GIF_SKELETONS: number[] = [0, 1, 2, 3, 4, 5];

// Saved-GIF picker for the input panel. It keeps a static thumbnail when
// autoplay/reduced-motion/power-saving settings disable playback.
@Component
export struct GifPicker {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  onPick: (g: GifItem) => void = (): void => {};
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) @Watch('onPlaybackSettingChanged') autoplayGif: boolean = true;
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onPlaybackSettingChanged') powerSaving: boolean = false;
  @StorageProp(KEY_REDUCE_ANIM) @Watch('onPlaybackSettingChanged') reduceAnimations: boolean = false;
  @State gifs: GifItem[] = [];
  @State loadState: string = 'loading'; // loading | ready | error
  @State errorText: string = '';
  @State sendingGifId: number = 0;
  private loadSeq: number = 0;
  private disposed: boolean = false;
  private sourceLoading: Set<number> = new Set<number>();
  private sendGuardTimer: number = -1;

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

  private playbackProbed(): boolean {
    probeHit('gif.cell');
    return this.playbackEnabled();
  }

  private playbackEnabled(): boolean {
    return this.autoplayGif && !this.powerSaving && !this.reduceAnimations;
  }

  private onPlaybackSettingChanged(): void {
    if (this.playbackEnabled()) {
      this.requestMissingSources();
    }
  }

  private localPath(file: TdObject | undefined): string {
    const local = file !== undefined ? (file['local'] as TdObject | undefined) : undefined;
    if (local === undefined || !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
      return '';
    }
    return (local['path'] as string | undefined) ?? '';
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
      this.gifs = items;
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
        this.requestMissingSources();
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
      this.gifs = this.gifs.map((g: GifItem): GifItem =>
        g.fileId === gifFileId
          ? {
            fileId: g.fileId, width: g.width, height: g.height, duration: g.duration,
            thumbPath: path, srcPath: g.srcPath
          }
          : g);
    }).catch((e: TdError) => {
      logE(`GifPicker.downloadThumb failed: ${e.message}`);
    });
  }

  private requestMissingSources(): void {
    if (!this.playbackEnabled()) {
      return;
    }
    const seq: number = this.loadSeq;
    for (const g of this.gifs) {
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
      this.gifs = this.gifs.map((g: GifItem): GifItem =>
        g.fileId === gifFileId
          ? {
            fileId: g.fileId, width: g.width, height: g.height, duration: g.duration,
            thumbPath: g.thumbPath, srcPath: path
          }
          : g);
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
                .width('100%').aspectRatio(1)
                .backgroundColor($r('app.color.surface_alt')).borderRadius(9)
                .opacity(idx % 2 === 0 ? 0.85 : 0.55);
            }
          }, (idx: number) => `gif_skeleton_${idx}`);
        }
        .columnsTemplate('1fr 1fr 1fr').columnsGap(7).rowsGap(7)
        .padding({ left: 10, right: 10, top: 10, bottom: 8 })
        .width('100%').height('100%');
      } else if (this.loadState === 'error') {
        this.stateMessage($r('sys.symbol.exclamationmark_circle'), this.errorText,
          str('check_network_retry'), true);
      } else if (this.gifs.length === 0) {
        this.stateMessage($r('sys.symbol.video'), str('gif_none_saved'),
          str('gif_none_saved_sub'), false);
      } else {
        Grid() {
          // 探针：这里是 ForEach 不是 LazyForEach——网格不虚拟化，拿回多少
          // 条就一次性建多少格。计一下实际规模。
          ForEach(this.gifs, (g: GifItem) => {
            GridItem() {
              Stack() {
                if (this.playbackProbed() && g.srcPath !== '') {
                  SmartLoopVideo({
                    videoPath: g.srcPath, thumbPath: g.thumbPath,
                    boxWidth: 112, boxHeight: 112, powerCategory: 'gif'
                  });
                } else if (g.thumbPath !== '') {
                  Image(`file://${g.thumbPath}`).draggable(false)
                    .width('100%').height('100%').objectFit(ImageFit.Cover);
                } else {
                  Column() {
                    LoadingProgress().width(20).height(20).color(COLOR_TEXT_SECONDARY);
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
                }
              }
              .width('100%').height('100%')
              .borderRadius(9).clip(true)
              .onClick(() => { this.pickGif(g); });
            }
            .aspectRatio(1);
          }, (g: GifItem) => `${g.fileId}_${g.thumbPath}_${g.srcPath}`);
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(7).rowsGap(7)
        .padding({ left: 10, right: 10, top: 7, bottom: 8 })
        .width('100%').height('100%');
      }
    }
    // 高度跟着抽屉的内容区走（见 util/drawerMetrics）。写死过一次 241，
    // 抽屉从 300 压到 260 之后就会溢出。
    .width('100%').height(EMOJI_CONTENT_HEIGHT)
    .constraintSize({ minHeight: EMOJI_CONTENT_HEIGHT, maxHeight: EMOJI_CONTENT_HEIGHT });
  }
}
