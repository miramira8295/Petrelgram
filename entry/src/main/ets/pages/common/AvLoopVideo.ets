import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { logE, logI } from '../../util/log';

let nextAvLoopId: number = 1;

// Muted, seamlessly looping video via the system AVPlayer (hardware decode,
// native loop — much lighter than ijkplayer). H.264/H.265 content only; VP9
// webm still needs WebmStickerView's software decoder.
// P4 批 6b：迁 @ComponentV2（配方同批 1~6a）。复用同步化；@Monitor 兜非复用
// 路径的换源。
@ComponentV2
export struct AvLoopVideo {
  @Param videoPath: string = '';
  @Param boxWidth: number = 100;
  @Param boxHeight: number = 100;
  @Param loop: boolean = true;
  // 滑动期间暂停。**暂停而不是卸载**：卸载会让 surface 一起消失，重新挂上去
  // 有一帧空白，表现就是"滑动时 GIF 闪一下"（用户 2026-09-07 报）。暂停则把
  // 最后一帧留在 surface 上，肉眼看不出中断。
  // 同一条道理见 issue #164 的修复：贴纸的滑动闸也是 pause 不 destroy。
  @Param paused: boolean = false;
  // 圆形视频是"点一下放一遍并出声"，和贴纸/GIF 的静音循环不是一回事。
  @Param muted: boolean = true;
  @Param onFinished: () => void = (): void => {};
  @Param onFailed: () => void = (): void => {};   // codec/demux failure — caller may fall back
  @Param onWorking: () => void = (): void => {};  // first successful playback
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

  aboutToReuse(): void {
    // @Param videoPath 已是新值（批 0.5 判读）：V1 写回 @Prop 的做法退役。
    this.playerSeq++;
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

  // paused 翻转就直接操作播放器，不重建：重建等于卸载，闪的就是它。
  // 播放器还没到 prepared 之前不动它——那时 play() 本来也还没发出去。
  @Monitor('paused')
  private onPausedChanged(): void {
    const p: media.AVPlayer | null = this.player;
    if (p === null) {
      return;
    }
    if (this.paused) {
      if (p.state === 'playing') {
        p.pause().catch((e: Object) => { logE(`AvLoopVideo.pause failed: ${JSON.stringify(e)}`); });
      }
      return;
    }
    // **'prepared' 必须和 'paused' 一起认。** 滑动期间新挂上来的那些行，播放器
    // 从来没播过——prepare() 完成时 paused 已经是 true，起播那一步被跳过了，
    // 状态停在 'prepared' 而不是 'paused'。只认 'paused' 的话，松手之后这些
    // GIF 会永远定格在首帧（滑久了新加载的那一批全中招）。
    if (p.state === 'paused' || p.state === 'prepared') {
      p.play().catch((e: Object) => { logE(`AvLoopVideo.resume failed: ${JSON.stringify(e)}`); });
    }
  }

  @Monitor('videoPath')
  onVideoPathChanged(): void {
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
          // 进来时就在滑动：直接停在首帧，别播一下再被暂停（那也是一次闪）。
          if (this.paused) {
            return;
          }
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
