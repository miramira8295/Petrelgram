import { AvatarPhoto } from './AvatarGallerySession';

// V1 counterpart of the chat viewer's film cell: the same 52vp geometry,
// stable photo identity and cell-local updates. No player or full-size fetch.
@Component
export struct AvatarFilmstripCell {
  @ObjectLink photo: AvatarPhoto;
  @Prop current: boolean = false;
  onLoad: () => void = (): void => {};

  aboutToAppear(): void { this.onLoad(); }

  private preview(): string {
    const path = this.photo.thumbPath || this.photo.imagePath;
    return path.startsWith('/') ? `file://${path}` : path;
  }

  build() {
    Stack() {
      if (this.photo.thumbPath !== '' || this.photo.imagePath !== '') {
        Image(this.preview()).draggable(false)
          .width(52).height(52).objectFit(ImageFit.Cover).borderRadius(6);
      }
      if (this.photo.videoId > 0 || this.photo.videoPath !== '') {
        Text('▶').fontSize(14).fontColor(Color.White).hitTestBehavior(HitTestMode.None);
      }
    }
    .width(52).height(52).backgroundColor('#333333').borderRadius(6).clip(true)
    .border({ width: this.current ? 2 : 0, color: Color.White })
    .opacity(this.current ? 1 : 0.68)
    .scale({ x: this.current ? 1 : 0.92, y: this.current ? 1 : 0.92 });
  }
}
