import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { logE, logI } from '../../util/log';
import { reuseParam } from '../../util/reuseParams';

let nextAvLoopId: number = 1;

// Muted, seamlessly looping video via the system AVPlayer (hardware decode,
// native loop — much lighter than ijkplayer). H.264/H.265 content only; VP9
// webm still needs WebmStickerView's software decoder.
@Component
export struct AvLoopVideo {
  @Prop @Watch('onVideoPathChanged') videoPath: string;
  @Prop boxWidth: number = 100;
  @Prop boxHeight: number = 100;
  @Prop loop: boolean = true;
  // 圆形视频是"点一下放一遍并出声"，和贴纸/GIF 的静音循环不是一回事。
  @Prop muted: boolean = true;
  onFinished: () => void = (): void => {};
  onFailed: () => void = (): void => {};   // codec/demux failure — caller may fall back
  onWorking: () => void = (): void => {};  // first successful playback
  private player: media.AVPlayer | null = null;
  private ctrl: XComponentController = new XComponentController();
  private fd: number = -1;
  private destroyed: boolean = false;
  private readonly instanceId: number = nextAvLoopId++;
  private surfaceId: string = '';
  private playerSeq: number = 0;

  aboutToAppear(): void {
    this.destroyed = false;
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    this.playerSeq++;
    this.release();
  }

  aboutToRecycle(): void {
    this.destroyed = true;
    this.playerSeq++;
    this.release();
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.playerSeq++;
    // reuseParam：params 是 {} 还是 undefined 都安全（P3 批 2 第 1 项，见
    // util/reuseParams.ets）。取不到就保留 this.videoPath，下面的 release/
    // 重新 init 仍然无条件跑。
    const videoPath: string | undefined = reuseParam(params, 'videoPath') as string | undefined;
    if (videoPath !== undefined) {
      this.videoPath = videoPath;
    }
    this.destroyed = false;
    this.release();
    if (this.surfaceId !== '') {
      setTimeout((): void => {
        if (!this.destroyed && this.player === null) {
          this.initPlayer(this.surfaceId);
        }
      }, 0);
    }
  }

  private release(): void {
    const p = this.player;
    this.player = null;
    if (p !== null) {
      p.release().catch((e: Object) => {
        logE(`AvLoopVideo.release failed: ${JSON.stringify(e)}`);
      });
    }
    if (this.fd >= 0) {
      try {
        fs.closeSync(this.fd);
      } catch (e) {
        logE(`AvLoopVideo fd close failed: ${e}`);
      }
      this.fd = -1;
    }
  }

  private onVideoPathChanged(): void {
    this.playerSeq++;
    this.release();
    if (!this.destroyed && this.surfaceId !== '') {
      setTimeout((): void => {
        if (!this.destroyed && this.player === null) {
          this.initPlayer(this.surfaceId);
        }
      }, 0);
    }
  }

  private initPlayer(surfaceId: string): void {
    if (this.videoPath === '' || this.destroyed) {
      return;
    }
    const seq: number = ++this.playerSeq;
    const sourcePath: string = this.videoPath;
    media.createAVPlayer().then((p: media.AVPlayer) => {
      if (this.destroyed || seq !== this.playerSeq || sourcePath !== this.videoPath) {
        p.release();
        return;
      }
      this.player = p;
      p.on('stateChange', (state: string) => {
        if (this.player !== p) {
          return;
        }
        if (state === 'initialized') {
          p.surfaceId = surfaceId;
          p.prepare().catch((e: Object) => {
            logE(`AvLoopVideo.prepare failed: ${JSON.stringify(e)}`);
            this.onFailed();
          });
        } else if (state === 'prepared') {
          p.loop = this.loop;
          // 保比例裁切填充。默认的拉伸填充会把竖屏录屏（约 0.46 比例）压进
          // 裁到 0.56 的气泡框——纵向压扁 20%，就是"视频缩略图变形"。
          // FIT_CROP 与底层缩略图的 ImageFit.Cover 行为一致，切换无跳变。
          p.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP;
          p.setVolume(this.muted ? 0 : 1);
          p.play().catch((e: Object) => {
            logE(`AvLoopVideo.play failed: ${JSON.stringify(e)}`);
            this.onFailed();
          });
        } else if (state === 'playing') {
          logI(`AvLoopVideo playing: ${this.videoPath}`);
          this.onWorking();
        } else if (state === 'completed') {
          // 非循环播放（圆形视频）播完要通知调用方收回播放态。
          this.onFinished();
        }
      });
      p.on('error', (err: Object) => {
        logE(`AvLoopVideo player error: ${JSON.stringify(err)}`);
        this.onFailed();
      });
      try {
        const f = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
        this.fd = f.fd;
        p.url = `fd://${f.fd}`;
      } catch (e) {
        logE(`AvLoopVideo open(${sourcePath}) failed: ${e}`);
        this.onFailed();
      }
    }).catch((e: Object) => {
      if (this.destroyed || seq !== this.playerSeq || sourcePath !== this.videoPath) {
        return;
      }
      logE(`AvLoopVideo.createAVPlayer failed: ${JSON.stringify(e)}`);
      this.onFailed();
    });
  }

  build() {
    XComponent({ id: `avloop_${this.instanceId}`, type: XComponentType.TEXTURE, controller: this.ctrl })
      .width(this.boxWidth).height(this.boxHeight)
      .onLoad(() => {
        this.surfaceId = this.ctrl.getXComponentSurfaceId();
        this.destroyed = false;
        logI(`AvLoopVideo surface ready for ${this.videoPath}`);
        this.initPlayer(this.surfaceId);
      })
      .onDestroy(() => {
        this.surfaceId = '';
        this.destroyed = true;
        this.playerSeq++;
        this.release();
      });
  }
}
