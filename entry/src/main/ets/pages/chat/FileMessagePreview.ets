import { LiveThumbImage, LiveThumbSpec, LiveThumbSpecCache } from './LiveThumbImage';
import { FilePreviewSource, sameFilePreview } from '../../util/filePreview';
import { posterFor, requestPoster, subscribePoster } from '../../util/videoPosterStore';

// The local thumbnail owns its own decode/poster lifecycle. Covers never publish
// row geometry. Reuse/visibility callbacks cannot carry a poster to another file.
@ComponentV2
export struct FileMessagePreview {
  @Require @Param source: FilePreviewSource;
  @Param boxSize: number = 86;
  @BuilderParam placeholder: () => void;
  @Local private poster: string = '';
  private specs: LiveThumbSpecCache = new LiveThumbSpecCache();
  private active: boolean = false;
  private visible: boolean = false;
  private generation: number = 0;
  private bound: FilePreviewSource | null = null;
  private off: (() => void) | null = null;
  private requested: boolean = false;

  private detach(): void { this.generation++; this.off?.(); this.off = null; this.bound = null; this.requested = false; }
  private attach(): void {
    if (!this.active) { return; }
    const source = this.source;
    if (!sameFilePreview(this.bound, source)) {
      this.detach(); this.bound = source;
      const generation = this.generation;
      const localVideo = source.kind === 'video' && source.filePath !== '' && source.thumbnailId === 0 && source.thumbnailPath === '';
      this.poster = localVideo ? posterFor(source.filePath) : '';
      if (localVideo) {
        this.off = subscribePoster(source.filePath, (path: string): void => {
          if (this.active && this.generation === generation && sameFilePreview(source, this.source)) { this.poster = path; }
        });
      }
    }
    if (this.visible && this.off !== null && !this.requested && this.poster === '') {
      this.requested = true; requestPoster(source.filePath, source.fileSize, 0);
    }
  }
  @Computed private get imageSpec(): LiveThumbSpec {
    const s = this.source;
    const path = s.thumbnailPath || (s.thumbnailId === 0 ? (s.kind === 'image' ? s.filePath : this.poster) : '');
    return this.specs.prepare({ fileId: s.thumbnailId, initialPath: path, boxWidth: this.boxSize, boxHeight: this.boxSize,
      radius: 10, fit: ImageFit.Cover, opaque: false, backdrop: '', mini: s.mini, drawOnCanvas: true });
  }
  @Monitor('source') private changed(): void { this.attach(); }
  aboutToAppear(): void { this.active = true; this.attach(); }
  aboutToReuse(): void { this.detach(); this.active = true; this.visible = false; this.attach(); }
  aboutToRecycle(): void { this.active = false; this.visible = false; this.detach(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  build() {
    Stack() {
      if (this.source.mini !== '') {
        Image(this.source.mini).width(this.boxSize).height(this.boxSize).objectFit(ImageFit.Cover).draggable(false);
      } else { this.placeholder(); }
      LiveThumbImage({ spec: this.imageSpec, placeholder: (): void => {} });
    }.width(this.boxSize).height(this.boxSize).borderRadius(10).clip(true)
    .onVisibleAreaChange([0, 0.01], (visible: boolean, ratio: number): void => {
      this.visible = visible && ratio > 0; this.attach();
    });
  }
}
