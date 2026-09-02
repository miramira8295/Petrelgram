import { StreamingVideoPlayer } from './StreamingVideoPlayer';

// 播放位气泡的薄封装：把一屏播放器的参数收在这一个组件里，MessageBubble 的
// 视频分支只多一个组件调用，而不是多一屏 StreamingVideoPlayer 的 props。
// 内嵌模式：无控制条、无手势层、不申请后台保活（见 StreamingVideoPlayer.embedded）。
// P4 批 6b：迁 @ComponentV2（纯参数转发件）。
@ComponentV2
export struct VideoBubbleSurface {
  @Param fileId: number = 0;
  @Param fileSize: number = 0;
  @Param mimeType: string = '';
  // Not "width"/"height": those names collide with CustomComponent's own
  // .width()/.height() chained attribute setters.
  @Param sourceWidth: number = 0;
  @Param sourceHeight: number = 0;
  @Param posterPath: string = '';
  @Param muted: boolean = true;
  @Param startPositionMs: number = 0;
  @Param onPositionChanged: (positionMs: number) => void =
    (_positionMs: number): void => {};
  @Param onEnded: () => void = (): void => {};

  build() {
    StreamingVideoPlayer({
      fileId: this.fileId,
      fileSize: this.fileSize,
      mimeType: this.mimeType,
      videoWidth: this.sourceWidth,
      videoHeight: this.sourceHeight,
      posterPath: this.posterPath,
      embedded: true,
      showControls: false,
      muted: this.muted,
      startPositionMs: this.startPositionMs,
      onPositionChanged: (positionMs: number): void => { this.onPositionChanged(positionMs); },
      onEnded: (): void => { this.onEnded(); },
      // 失败与播完对挂载点是同一件事：把播放位让出去，回落到封面。
      onFailed: (): void => { this.onEnded(); }
    });
  }
}
