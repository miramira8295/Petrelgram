import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { cachedMusicCover, ensureMusicCover, musicCoverSource } from '../../services/MusicCoverCache';

// Image completion invalidates this 40vp island only, never the row/paragraph.
@ComponentV2
export struct DrawnDocumentAudioCover {
  @Param fileId: number = 0;
  @Param mini: string = '';
  @Local private coverPath: string = '';
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  @Computed private get imageSpec(): CachedImageSpec {
    return this.specs.prepare({ path: this.coverPath !== '' ? musicCoverSource(this.coverPath) : this.mini,
      boxWidth: 40, boxHeight: 40, radius: 6, fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `document-audio:${this.fileId}` });
  }
  private generation: number = 0;
  private visible: boolean = false;
  private bind(): void {
    const owner = ++this.generation;
    this.coverPath = cachedMusicCover(this.fileId);
    if (!this.visible || this.fileId <= 0 || this.coverPath !== '') { return; }
    ensureMusicCover(this.fileId).then((path: string): void => {
      if (owner === this.generation && this.visible && this.coverPath !== path) { this.coverPath = path; }
    });
  }
  @Monitor('fileId', 'mini') onSourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.generation++; }
  build() {
    Stack() {
      if (this.coverPath !== '' || this.mini !== '') {
        CachedImage({ spec: this.imageSpec }).opacity(0.35);
      }
    }.width(40).height(40).borderRadius(6).clip(true).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
