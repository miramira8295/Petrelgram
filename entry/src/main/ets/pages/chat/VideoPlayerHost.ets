import { StreamingVideoPlayer } from './StreamingVideoPlayer';
import { AvVideoPlayer } from './AvVideoPlayer';
import { KEY_VIDEO_ENGINE_AVPLAYER } from '../../store/AppSettings';

// 全屏播放器的**引擎分流件**：同一组参数，按设置交给 ijkplayer 还是系统 AVPlayer。
//
// 【为什么是一个组件而不是在调用处 if】MediaViewerOverlay 那边要传 17 个参数，
// 在调用处分叉就得把这 17 行写两遍，往后加一个参数要改四处。收在这里，两个
// 分支各写一次，调用处只有一个组件。
//
// 【为什么只管全屏】气泡里的内嵌播放位（VideoBubbleSurface）恒走 ijk，不参与
// 分流：需要 HDR 的是全屏观看，而内嵌那条是静音预览、在列表滚动的关键路径上，
// 没有理由拿它冒险。
//
// 【怎么切回去】设置 → 关掉「用系统播放器」。开关默认关；读一次 AppStorage，
// 组件重建时生效（关掉查看器再打开即可），不需要重启应用。
@Component
export struct VideoPlayerHost {
  @StorageProp(KEY_VIDEO_ENGINE_AVPLAYER) useAvPlayer: boolean = false;
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
    if (this.useAvPlayer) {
      AvVideoPlayer({
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
    } else {
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
}
