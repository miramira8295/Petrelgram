import { common } from '@kit.AbilityKit';
import { saveMediaToGallery } from '../../util/mediaSaver';
import { getTdClient } from '../../tdkit/Globals';
import { AvatarGallerySession, AvatarPhoto } from './AvatarGallerySession';
import { AvatarViewerPage } from './AvatarViewerPage';
import { AvatarFilmstripCell } from './AvatarFilmstripCell';

// Avatar history is its own paged source, not a message-album snapshot.
// Lazy pages retain stills; only the selected page creates a muted loop player.
@Component
export struct AvatarViewer {
  @Prop imagePath: string;
  @Prop @Watch('onSeedVideoChanged') videoPath: string = '';
  @Prop imageFileId: number = 0;
  @Prop userId: number = 0;
  @Prop chatId: number = 0;
  onClose: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @Prop originX: number = 0;
  @Prop originY: number = 0;
  @State private index: number = 0;
  @State private count: number = 1;
  @State private ready: boolean = false;
  @State private loading: boolean = false;
  @State private hasMore: boolean = true;
  @State private loadError: boolean = false;
  @State private zoomed: boolean = false;
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  @State private saving: boolean = false;
  private source: AvatarGallerySession | null = null;
  private filmScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.source = new AvatarGallerySession(getTdClient(), this.userId, this.chatId,
      this.imageFileId, this.imagePath, this.videoPath, (): void => {
        const source = this.source;
        if (source === null) { return; }
        this.count = source.totalCount(); this.loading = source.loading;
        this.hasMore = source.hasMore; this.loadError = source.error;
      });
    this.ready = true;
    this.source.open();
  }

  aboutToDisappear(): void { this.source?.close(); this.source = null; }
  private onSeedVideoChanged(): void { this.source?.updateSeedVideo(this.videoPath); }

  private selectPhoto(index: number): void {
    if (this.source === null || index < 0 || index >= this.source.totalCount()) { return; }
    if (this.index !== index) {
      this.index = index; this.zoomed = false; this.source.select(index);
    }
    this.centerFilmstrip();
  }

  private centerFilmstrip(): void {
    if (this.source !== null && this.count > 1) {
      this.filmScroller.scrollToIndex(this.index, false, ScrollAlign.CENTER);
    }
  }

  @Builder
  filmstrip() {
    List({ space: 6, scroller: this.filmScroller }) {
      LazyForEach(this.source, (photo: AvatarPhoto) => {
        ListItem() {
          AvatarFilmstripCell({ photo, current: photo.index === this.index,
            onLoad: (): void => { this.source?.ensureThumbnail(photo.index); } });
        }.onClick((): void => { this.selectPhoto(photo.index); });
      }, (photo: AvatarPhoto): string => photo.key);
    }
    .listDirection(Axis.Horizontal).width('100%').height(56)
    .padding({ left: 12, right: 12 }).scrollBar(BarState.Off).cachedCount(4)
    .onAppear((): void => {
      setTimeout((): void => { this.centerFilmstrip(); }, 0);
    });
  }

  private async saveImage(): Promise<void> {
    const photo = this.source?.getData(this.index);
    if (this.saving || photo === undefined) { return; }
    const video = photo.videoPath !== '';
    const path = video ? photo.videoPath : photo.imagePath;
    if (path === '') { return; }
    this.saving = true;
    try {
      await saveMediaToGallery(this.getUIContext().getHostContext() as common.UIAbilityContext, path, video);
    } finally { this.saving = false; }
  }

  private openTransition(): TransitionEffect {
    const scaled: ScaleOptions = this.originX > 0 || this.originY > 0
      ? { x: 0.25, y: 0.25, centerX: this.originX, centerY: this.originY } : { x: 0.25, y: 0.25 };
    return TransitionEffect.scale(scaled).combine(TransitionEffect.OPACITY)
      .animation({ duration: 300, curve: Curve.Friction });
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.ready && this.source !== null) {
        Swiper() {
          LazyForEach(this.source, (photo: AvatarPhoto) => {
            AvatarViewerPage({ photo, active: photo.index === this.index,
              boxWidth: this.viewportWidth, boxHeight: this.viewportHeight,
              onClose: this.onClose,
              onZoom: (value: boolean): void => { if (photo.index === this.index) { this.zoomed = value; } },
              onRetry: (): void => { this.source?.retry(); }
            });
          }, (photo: AvatarPhoto): string => photo.key);
        }
        .width('100%').height('100%').loop(false).indicator(false).cachedCount(1)
        .index(this.index).disableSwipe(this.zoomed)
        .onChange((index: number): void => {
          this.selectPhoto(index);
        });
      }
      Row({ space: 12 }) {
        Button(this.saving ? $r('app.string.saving') : $r('app.string.ms_save_to_gallery'))
          .id('avatarViewerSave').height(40).padding({ left: 16, right: 16 })
          .fontSize(14).fontColor(Color.White).backgroundColor('#4D000000')
          .enabled(!this.saving)
          .onClick((): void => { this.saveImage(); });
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(22).fontColor([Color.White]);
        }.width(40).height(40).backgroundColor('#4D000000')
        .accessibilityText($r('app.string.close')).onClick((): void => { this.onClose(); });
      }.margin({ top: this.topSafe + 12, right: 12 });
      Column({ space: 10 }) {
        if (this.ready && this.source !== null && this.count > 1) {
          this.filmstrip();
        }
        Row({ space: 12 }) {
        Text(`${this.index + 1} / ${this.count}${this.hasMore ? '+' : ''}`)
          .fontColor(Color.White).fontSize(14);
        if (this.loading) {
          LoadingProgress().width(20).height(20).color(Color.White);
        } else if (this.loadError || (this.hasMore && this.index === this.count - 1)) {
          Button(this.loadError ? $r('app.string.settings_reload') : $r('app.string.load_more'))
            .fontColor(Color.White).backgroundColor('#4D000000')
            .onClick((): void => { this.source?.loadMore(); });
        }
        }
      }.width('100%').align(Alignment.Bottom).margin({ bottom: this.bottomSafe + 24 });
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onAreaChange((_old: Area, area: Area): void => {
      const width = area.width as number; const height = area.height as number;
      if (width > 0 && Math.abs(width - this.viewportWidth) > 0.5) { this.viewportWidth = width; }
      if (height > 0 && Math.abs(height - this.viewportHeight) > 0.5) { this.viewportHeight = height; }
    })
    .transition(this.openTransition());
  }
}
