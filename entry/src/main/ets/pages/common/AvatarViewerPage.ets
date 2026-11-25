import { AvatarPhoto } from './AvatarGallerySession';
import { AvLoopVideo } from './AvLoopVideo';

// Only the selected lazy page owns a player. At 1x, horizontal gestures belong
// to Swiper; vertical dragging dismisses, while zoomed dragging pans the photo.
@Component
export struct AvatarViewerPage {
  @ObjectLink photo: AvatarPhoto;
  @Prop @Watch('onActiveChanged') active: boolean = false;
  @Prop boxWidth: number = 0;
  @Prop boxHeight: number = 0;
  @StorageProp('appIsForeground') private foreground: boolean = true;
  onClose: () => void = (): void => {};
  onZoom: (zoomed: boolean) => void = (_zoomed: boolean): void => {};
  onRetry: () => void = (): void => {};
  @State private zoom: number = 1;
  @State private x: number = 0;
  @State private y: number = 0;
  @State private playbackFailed: boolean = false;
  private baseScale: number = 1;
  private baseX: number = 0;
  private baseY: number = 0;

  private reset(): void { this.zoom = 1; this.x = 0; this.y = 0; this.onZoom(false); }
  private onActiveChanged(): void { this.zoom = 1; this.x = 0; this.y = 0; this.playbackFailed = false; }
  private videoSide(): number { return Math.max(0, Math.min(this.boxWidth, this.boxHeight)); }

  build() {
    Stack() {
      Stack() {
        // Retain the small preview beneath the full image while it decodes.
        if (this.photo.thumbPath !== '') {
          Image(this.photo.thumbPath.startsWith('/') ? `file://${this.photo.thumbPath}` : this.photo.thumbPath)
            .draggable(false).width('100%').height('100%').objectFit(ImageFit.Contain);
        }
        if (this.photo.imagePath !== '') {
          Image(this.photo.imagePath.startsWith('/') ? `file://${this.photo.imagePath}` : this.photo.imagePath)
            .draggable(false).width('100%').height('100%').objectFit(ImageFit.Contain);
        }
        if (this.active && this.photo.videoPath !== '' && !this.playbackFailed && this.videoSide() > 0) {
          AvLoopVideo({ videoPath: this.photo.videoPath, boxWidth: this.videoSide(), boxHeight: this.videoSide(),
            muted: true, loop: true, paused: !this.foreground,
            onFailed: (): void => { this.playbackFailed = true; } })
            .hitTestBehavior(HitTestMode.None);
        }
      }
      .width('100%').height('100%')
      .scale({ x: this.zoom, y: this.zoom })
      .translate({ x: this.x, y: this.y });
      if (this.photo.imagePath === '' && !this.photo.downloadFailed) {
        LoadingProgress().width(32).height(32).color(Color.White);
      }
      if (this.photo.downloadFailed || this.playbackFailed) {
        Button($r('app.string.settings_reload'))
          .fontColor(Color.White).backgroundColor('#66000000')
          .onClick((): void => { this.playbackFailed = false; this.onRetry(); });
      }
    }
    .width('100%').height('100%')
    .gesture(GestureGroup(GestureMode.Exclusive,
      TapGesture({ count: 2 }).onAction((): void => {
        if (this.zoom > 1.01) { this.reset(); }
        else { this.zoom = 2.5; this.onZoom(true); }
      }),
      TapGesture({ count: 1 }).onAction((): void => {
        if (this.zoom > 1.01) { this.reset(); } else { this.onClose(); }
      })
    ))
    .priorityGesture(GestureGroup(GestureMode.Parallel,
      PinchGesture({ fingers: 2 })
        .onActionStart((): void => { this.baseScale = this.zoom; })
        .onActionUpdate((event: GestureEvent): void => {
          this.zoom = Math.min(4, Math.max(1, this.baseScale * event.scale));
          this.onZoom(this.zoom > 1.01);
        })
        .onActionEnd((): void => { if (this.zoom <= 1.01) { this.reset(); } }),
      PanGesture({ fingers: 1, distance: this.zoom > 1.01 ? 3 : 20,
        direction: this.zoom > 1.01 ? PanDirection.All : PanDirection.Vertical })
        .onActionStart((): void => { this.baseX = this.x; this.baseY = this.y; })
        .onActionUpdate((event: GestureEvent): void => {
          if (this.zoom > 1.01) { this.x = this.baseX + event.offsetX; this.y = this.baseY + event.offsetY; }
          else { this.y = Math.max(0, event.offsetY); }
        })
        .onActionEnd((): void => {
          if (this.zoom <= 1.01 && this.y > 120) { this.onClose(); }
          else if (this.zoom <= 1.01) { this.reset(); }
        })
        .onActionCancel((): void => { if (this.zoom <= 1.01) { this.reset(); } })
    ));
  }
}
