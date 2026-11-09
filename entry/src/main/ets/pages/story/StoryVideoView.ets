import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE } from '../../util/log';

// 故事视频播放器：本地文件、带声音、播一次，结束回调 onEnded。
// 与 AvLoopVideo（静音循环）职责不同，故单列组件。
@Component
export struct StoryVideoView {
  @Prop videoPath: string;
  @Prop @Watch('onPausedChanged') paused: boolean = false;
  onEnded: () => void = (): void => {};
  onDuration: (durationMs: number) => void = (): void => {};
  private controller: XComponentController = new XComponentController();
  private player: media.AVPlayer | null = null;
  private file: fs.File | null = null;
  private disposed: boolean = false;

  aboutToDisappear(): void {
    this.disposed = true;
    this.release();
  }

  onPausedChanged(): void {
    const player = this.player;
    if (player === null) {
      return;
    }
    if (this.paused) {
      player.pause();
    } else {
      player.play();
    }
  }

  private release(): void {
    const player = this.player;
    this.player = null;
    if (player !== null) {
      player.release().catch((e: BusinessError): void => {
        logE(`StoryVideoView.release failed: ${e.message}`);
      });
    }
    if (this.file !== null) {
      fs.close(this.file.fd).catch((): void => {});
      this.file = null;
    }
  }

  private startPlayback(surfaceId: string): void {
    media.createAVPlayer().then((player: media.AVPlayer): void => {
      if (this.disposed) {
        player.release();
        return;
      }
      this.player = player;
      player.on('stateChange', (state: string): void => {
        if (this.disposed) {
          return;
        }
        if (state === 'initialized') {
          player.surfaceId = surfaceId;
          player.prepare();
        } else if (state === 'prepared') {
          this.onDuration(player.duration);
          player.loop = false;
          player.play();
        } else if (state === 'completed') {
          this.onEnded();
        }
      });
      player.on('error', (e: BusinessError): void => {
        logE(`StoryVideoView player error: ${e.message}`);
        this.onEnded(); // 播放失败当作播完，让查看器继续推进
      });
      try {
        const file = fs.openSync(this.videoPath, fs.OpenMode.READ_ONLY);
        this.file = file;
        player.url = `fd://${file.fd}`;
      } catch (e) {
        logE(`StoryVideoView open failed: ${(e as Error).message}`);
        this.onEnded();
      }
    }).catch((e: BusinessError): void => {
      logE(`StoryVideoView.createAVPlayer failed: ${e.message}`);
      this.onEnded();
    });
  }

  build() {
    XComponent({
      id: 'story_video',
      type: XComponentType.SURFACE,
      controller: this.controller
    })
      .onLoad((): void => {
        this.startPlayback(this.controller.getXComponentSurfaceId());
      })
      .width('100%')
      .height('100%');
  }
}
