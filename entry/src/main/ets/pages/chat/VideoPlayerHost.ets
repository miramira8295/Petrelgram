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
// 【怎么切回去】设置 → 关掉「用系统播放器」。**开关默认开**（见 AppSettings 的
// DATA_BOOLEAN_TRUE_DEFAULTS，09-04 改的；此处原注释写"默认关"，是那次漏改的）。
// 读一次 AppStorage，组件重建时生效（关掉查看器再打开即可），不需要重启应用。
//
// 【自动回退】AVPlayer 有 HDR 但解码器是系统那一套，比 FFmpeg 窄；ijkplayer 反过来。
// 分流原本是静态的：AVPlayer 解不了就直接失败，用户得自己去设置里换引擎——
// 而他根本不知道有这么个开关。现在 AvVideoPlayer 遇到"格式/能力不支持"会回调
// onEngineUnsupported，本组件就地切 ijk 重开一次，用户无感。
// 判据在 util/videoEngineFallback（纯函数 + 单测），只有确定性失败才换引擎，
// IO/网络那些仍走原有的退避重试。
@Component
export struct VideoPlayerHost {
  @StorageProp(KEY_VIDEO_ENGINE_AVPLAYER) useAvPlayer: boolean = false;
  // 本次会话里已知"AVPlayer 解不了"的那个 fileId。**按 fileId 记而不是一个布尔**：
  // 查看器可以左右翻到下一条视频，那一条应当重新给 AVPlayer 一次机会（HDR 在
  // 它那边）。0 表示没有回退过。
  //
  // 不做跨会话的持久名单：一次回退的代价只是重开一次播放器，而持久化会带来
  // "换了设备/系统升级之后仍然记着旧结论"的问题。真要做，等 [VideoEngine]
  // 打点收集到真实分布之后再说。
  @State private fallbackFileId: number = 0;
  @Prop @Watch('onFileIdChanged') fileId: number;
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

  // 翻到另一条视频：上一条的回退结论不适用，清掉重新给 AVPlayer 机会。
  private onFileIdChanged(): void {
    if (this.fallbackFileId !== 0 && this.fallbackFileId !== this.fileId) {
      this.fallbackFileId = 0;
    }
  }

  build() {
    // 用 AVPlayer 的条件：开关开着，**且**这一条没有被判定为它解不了。
    if (this.useAvPlayer && this.fallbackFileId !== this.fileId) {
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
        onOrientationChange: (landscape: boolean): void => { this.onOrientationChange(landscape); },
        // 记下这一条，build 随即改走 ijk 分支。组件实例会被销毁重建——
        // 这正是我们要的：AVPlayer 那边已经进了错误态，复用它没有意义。
        onEngineUnsupported: (): void => { this.fallbackFileId = this.fileId; }
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
