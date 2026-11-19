import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { TdObject } from '../../tdkit/TdTypes';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentMapFile } from '../../util/documentMapCache';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { str } from '../../util/strings';

@ComponentV2
export struct DrawnDocumentMap {
  @Require @Param widget: DrawnDocumentWidget;
  @Param chatId: number = 0;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Event onOpen: () => void = (): void => {};
  @Local private path: string = '';
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  private pin: DrawnMediaControl = new DrawnMediaControl();
  private env = chatEnv;
  @Computed private get environment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get imageSpec(): CachedImageSpec {
    return this.specs.prepare({ path: this.path, boxWidth: this.boxWidth, boxHeight: this.boxHeight,
      fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `document-map:${this.chatId}:${this.widget.latitude}:${this.widget.longitude}:${this.widget.zoom}` });
  }
  private off: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach(); this.path = '';
    if (!this.visible) { return; }
    const owner = this.generation;
    documentMapFile(this.widget, this.chatId, this.boxWidth, this.boxHeight).then((file: TdObject): void => {
      if (owner !== this.generation || !this.visible) { return; }
      this.path = documentFileState(file).path;
      this.off = watchDocumentFile(file, (state: DocumentFileState): void => { if (owner === this.generation) { this.path = state.path; } });
      requestDocumentFile(file, THUMBNAIL_PRIORITY);
    }).catch((): void => { /* The coordinate/pin remains actionable without a thumbnail. */ });
  }
  @Monitor('widget', 'chatId', 'boxWidth', 'boxHeight') onSourceChanged(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  build() {
    Stack() {
      if (this.path !== '') { CachedImage({ spec: this.imageSpec }); }
      Row().width(30).height(30).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        .drawModifier(this.pin.bind(this.getUIContext(), this.environment, 30, '#00000000', '#DD534D', 'pin'));
    }.width(this.boxWidth).height(this.boxHeight).backgroundColor($r('app.color.surface_alt')).clip(true)
      .accessibilityText(`${str('loc_location')} ${this.widget.latitude}, ${this.widget.longitude}`)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } })
      .onClick((): void => this.onOpen());
  }
}
