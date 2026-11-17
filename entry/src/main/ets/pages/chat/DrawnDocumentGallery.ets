import { DrawnDocumentMedia } from '../../util/drawnDocumentMedia';
import { DrawnDocumentMediaIsland } from './DrawnDocumentMediaIsland';
import { setTableScrollTouch } from '../../util/tableTouchChannel';

class DocumentGallerySource implements IDataSource {
  private items: DrawnDocumentMedia[] = [];
  private listeners: Set<DataChangeListener> = new Set<DataChangeListener>();
  generation: number = 0;
  totalCount(): number { return this.items.length; }
  getData(index: number): DrawnDocumentMedia { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.add(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners.delete(listener); }
  update(items: DrawnDocumentMedia[]): void {
    if (this.items === items) { return; }
    this.items = items; this.generation++;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
}

// Android's slideshow keeps its own page/gesture state. The native Swiper is
// the ArkUI equivalent; caption and bubble geometry never change on a swipe.
@ComponentV2
export struct DrawnDocumentGallery {
  @Require @Param slides: DrawnDocumentMedia[];
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Event onOpen: (media: DrawnDocumentMedia) => void = (): void => {};
  @Local private selected: number = 0;
  private source: DocumentGallerySource = new DocumentGallerySource();
  aboutToAppear(): void { this.source.update(this.slides); }
  private touching: boolean = false;
  private releaseTouch(): void { if (this.touching) { this.touching = false; setTableScrollTouch(false); } }
  aboutToDisappear(): void { this.releaseTouch(); }
  @Monitor('slides') onSourceChanged(): void { this.selected = 0; this.releaseTouch(); this.source.update(this.slides); }
  build() {
    Swiper() {
      LazyForEach(this.source, (media: DrawnDocumentMedia, index: number) => {
        DrawnDocumentMediaIsland({ media, boxWidth: this.boxWidth, boxHeight: this.boxHeight,
          pageActive: index === this.selected,
          onOpen: (): void => { this.onOpen(media); } });
      }, (media: DrawnDocumentMedia): string => `${this.source.generation}:${media.key}`);
    }.width(this.boxWidth).height(this.boxHeight).index(this.selected).loop(false).cachedCount(1)
    .onChange((index: number): void => { if (index >= 0 && index < this.slides.length) { this.selected = index; } })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.touching = true; setTableScrollTouch(true); }
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.releaseTouch(); }
    });
  }
}
