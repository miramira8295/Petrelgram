import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnDocumentPlayback } from './DrawnDocumentPlayback';
import { str } from '../../util/strings';
import { DrawnDocumentMedia, documentFileId } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { LiveProgressRing } from './LiveProgressRing';

// Image state belongs to this asset, never the row's paragraph/layout key.
@ComponentV2
export struct DrawnDocumentMediaIsland {
  @Require @Param media: DrawnDocumentMedia;
  @Param pageActive: boolean = true;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Event onOpen: () => void = (): void => {};
  @Local private path: string = '';
  @Local private failed: boolean = false;
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  private control: DrawnMediaControl = new DrawnMediaControl();
  private env = chatEnv;
  @Computed private get environment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get imageSpec(): CachedImageSpec {
    return this.specs.prepare({ path: this.path, boxWidth: this.boxWidth, boxHeight: this.boxHeight,
      fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `document-media:${this.media.key}:${documentFileId(this.media.file)}:${documentFileId(this.media.thumbnail)}` });
  }
  private generation: number = 0;
  private off: (() => void) | null = null;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach(); this.path = ''; this.failed = false;
    const file = this.media.thumbnail ?? (this.media.kind === 'photo' ? this.media.file : undefined);
    if (file === undefined) { return; }
    const generation = this.generation;
    const initial = documentFileState(file); this.path = initial.path; this.failed = initial.failed;
    if (!this.visible || !this.pageActive) { return; }
    this.off = watchDocumentFile(file, (state: DocumentFileState): void => {
      if (generation !== this.generation) { return; }
      if (this.path !== state.path) { this.path = state.path; }
      if (this.failed !== state.failed) { this.failed = state.failed; }
    });
    requestDocumentFile(file, THUMBNAIL_PRIORITY);
  }
  @Monitor('media', 'pageActive') onMediaChanged(): void { this.bind(); }
  aboutToAppear(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  aboutToRecycle(): void { this.visible = false; this.detach(); this.path = ''; }
  aboutToReuse(): void { this.visible = false; this.bind(); }
  build() {
    Stack() {
      if (this.path !== '') {
        CachedImage({ spec: this.imageSpec });
      } else if (!this.failed && (this.media.thumbnail !== undefined || this.media.kind === 'photo')) {
        LiveProgressRing({ fileId: documentFileId(this.media.thumbnail ?? this.media.file), ringSize: 30 });
      }
      if (this.media.kind !== 'photo' || this.failed) {
        Row().width(44).height(44).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          .drawModifier(this.control.bind(this.getUIContext(), this.environment, 44,
            '#73000000', '#FFFFFF', this.media.kind !== 'photo' ? 'play' : 'retry'));
      }
      if (this.media.kind === 'video' || this.media.kind === 'animation') {
        DrawnDocumentPlayback({ media: this.media, pageActive: this.pageActive, boxWidth: this.boxWidth, boxHeight: this.boxHeight,
          posterPath: this.path }).hitTestBehavior(HitTestMode.None);
      }
    }.width(this.boxWidth).height(this.boxHeight).backgroundColor($r('app.color.surface_alt'))
    .clip(true).accessibilityLevel('yes').accessibilityText(str(this.media.kind === 'photo' ? 'preview_photo' : 'preview_video'))
    .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } })
    .onClick((event: ClickEvent): void => { this.onOpen(); });
  }
}
