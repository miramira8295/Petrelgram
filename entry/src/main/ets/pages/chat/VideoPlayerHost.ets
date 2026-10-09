import { StreamingVideoPlayer } from './StreamingVideoPlayer';

// 全屏查看器的播放器宿主。原来是 ijkplayer / 系统 AVPlayer 的引擎分流件；
// 2026-10-08 用户决定删掉系统播放器（ijkplayer 升到 2.0.11，FFmpeg 8 + 按能力自动
// 硬解并直接输出到窗口），只剩 ijk 一路。组件保留成一层薄转发，调用处
// （MediaViewerOverlay 那 17 个参数）不用动。
//
// 气泡里的内嵌播放位（VideoBubbleSurface）一直走 ijk，不经过这里。
@Component
export struct VideoPlayerHost {
  @Prop fileId: number;
  @Prop fileSize: number;
  @Prop mimeType: string = '';
  @Prop videoWidth: number = 0;
  @Prop videoHeight: number = 0;
  @Prop localPath: string = '';
  @Prop posterPath: string = '';
  @Prop showControls: boolean = true;
  @Prop landscape: boolean = false;
  @Prop muted: boolean = false;
  @Prop startPositionMs: number = 0;
  @Prop liveToggleSeq: number = 0;
  @Prop liveMode: boolean = false;
  onPlayStateChanged: (playing: boolean) => void = (): void => {};
  onBackgroundTap: () => void = (): void => {};
  onSwipeNext: () => void = (): void => {};
  onSwipePrev: () => void = (): void => {};
  onOrientationChange: (landscape: boolean) => void = (_landscape: boolean): void => {};
  onPositionChanged: (positionMs: number) => void = (_positionMs: number): void => {};

  build() {
    StreamingVideoPlayer({
      fileId: this.fileId,
      fileSize: this.fileSize,
      mimeType: this.mimeType,
      videoWidth: this.videoWidth,
      videoHeight: this.videoHeight,
      localPath: this.localPath,
      posterPath: this.posterPath,
      showControls: this.showControls,
      liveMode: this.liveMode,
      liveToggleSeq: this.liveToggleSeq,
      onPlayStateChanged: (playing: boolean): void => { this.onPlayStateChanged(playing); },
      landscape: this.landscape,
      muted: this.muted,
      startPositionMs: this.startPositionMs,
      onPositionChanged: (positionMs: number): void => { this.onPositionChanged(positionMs); },
      onBackgroundTap: (): void => { this.onBackgroundTap(); },
      onSwipeNext: (): void => { this.onSwipeNext(); },
      onSwipePrev: (): void => { this.onSwipePrev(); },
      onOrientationChange: (landscape: boolean): void => { this.onOrientationChange(landscape); }
    });
  }
}
