import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { COLOR_PRIMARY } from '../../util/theme';
import { logE } from '../../util/log';

let nextLocalPlayerId: number = 1;

const CONTROLS_AUTO_HIDE_MS: number = 3000;

// 全屏播放沙箱里的本地视频文件（下载列表预览用）。和 AvLoopVideo 的区别是
// 它有声音、有播放控件、可拖动进度；和 StreamingVideoPlayer 的区别是它只认
// 一个已经落盘的完整文件，不参与边下边播的分段逻辑。
@Component
export struct LocalVideoPlayer {
  @Prop videoPath: string;
  @Prop title: string = '';
  onClose: () => void = (): void => {};
  // 全屏浮层要自己避让状态栏，否则关闭按钮会被压在状态栏下点不到。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State private playing: boolean = false;
  @State private durationMs: number = 0;
  @State private positionMs: number = 0;
  @State private ready: boolean = false;
  @State private failed: boolean = false;
  @State private controlsVisible: boolean = true;
  // 拖动进度条期间冻结 timeUpdate 的回写，否则手指还没松滑块就被弹回去。
  @State private seeking: boolean = false;
  private player: media.AVPlayer | null = null;
  private ctrl: XComponentController = new XComponentController();
  private fd: number = -1;
  private destroyed: boolean = false;
  private hideTimer: number = -1;
  private readonly instanceId: number = nextLocalPlayerId++;

  aboutToDisappear(): void {
    this.destroyed = true;
    this.clearHideTimer();
    this.release();
  }

  private clearHideTimer(): void {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  // 控件常亮只在暂停态：播放中隔几秒自动收起，避免挡住画面。
  private scheduleHideControls(): void {
    this.clearHideTimer();
    if (!this.playing) {
      return;
    }
    this.hideTimer = setTimeout((): void => {
      this.hideTimer = -1;
      if (!this.destroyed && this.playing) {
        this.controlsVisible = false;
      }
    }, CONTROLS_AUTO_HIDE_MS);
  }

  private toggleControls(): void {
    this.controlsVisible = !this.controlsVisible;
    if (this.controlsVisible) {
      this.scheduleHideControls();
    } else {
      this.clearHideTimer();
    }
  }

  private release(): void {
    const p = this.player;
    this.player = null;
    if (p !== null) {
      p.release().catch((e: Object): void => {
        logE(`LocalVideoPlayer.release failed: ${JSON.stringify(e)}`);
      });
    }
    if (this.fd >= 0) {
      try {
        fs.closeSync(this.fd);
      } catch (e) {
        logE(`LocalVideoPlayer fd close failed: ${e}`);
      }
      this.fd = -1;
    }
  }

  private fail(where: string, e: Object): void {
    logE(`LocalVideoPlayer.${where} failed: ${JSON.stringify(e)}`);
    if (!this.destroyed) {
      this.failed = true;
    }
  }

  private initPlayer(surfaceId: string): void {
    if (this.videoPath === '' || this.destroyed) {
      return;
    }
    media.createAVPlayer().then((p: media.AVPlayer): void => {
      if (this.destroyed) {
        p.release();
        return;
      }
      this.player = p;
      p.on('stateChange', (state: string): void => {
        if (this.player !== p) {
          return;
        }
        if (state === 'initialized') {
          p.surfaceId = surfaceId;
          p.prepare().catch((e: Object): void => this.fail('prepare', e));
        } else if (state === 'prepared') {
          this.ready = true;
          this.durationMs = p.duration > 0 ? p.duration : 0;
          p.play().catch((e: Object): void => this.fail('play', e));
        } else if (state === 'playing') {
          this.playing = true;
          this.scheduleHideControls();
        } else if (state === 'paused') {
          this.playing = false;
          this.clearHideTimer();
          this.controlsVisible = true;
        } else if (state === 'completed') {
          // 播完停在末帧并亮出控件，让"再播一次"是一次明确的点击。
          this.playing = false;
          this.positionMs = this.durationMs;
          this.controlsVisible = true;
          this.clearHideTimer();
        }
      });
      p.on('timeUpdate', (time: number): void => {
        if (this.player === p && !this.seeking) {
          this.positionMs = time;
        }
      });
      p.on('error', (err: Object): void => this.fail('player', err));
      try {
        const f = fs.openSync(this.videoPath, fs.OpenMode.READ_ONLY);
        this.fd = f.fd;
        p.url = `fd://${f.fd}`;
      } catch (e) {
        this.fail('open', e as Object);
      }
    }).catch((e: Object): void => this.fail('createAVPlayer', e));
  }

  private togglePlay(): void {
    const p = this.player;
    if (p === null || !this.ready) {
      return;
    }
    if (this.playing) {
      p.pause().catch((e: Object): void => this.fail('pause', e));
      return;
    }
    // 从末帧再播：先回到 0，否则 play() 会立刻再次 completed。
    if (this.durationMs > 0 && this.positionMs >= this.durationMs - 200) {
      p.seek(0);
      this.positionMs = 0;
    }
    p.play().catch((e: Object): void => this.fail('play', e));
  }

  private seekTo(ms: number): void {
    const p = this.player;
    if (p === null || !this.ready || this.durationMs <= 0) {
      return;
    }
    const clamped: number = Math.max(0, Math.min(this.durationMs, Math.round(ms)));
    this.positionMs = clamped;
    p.seek(clamped);
  }

  private static timeLabel(ms: number): string {
    const total: number = Math.max(0, Math.floor(ms / 1000));
    const mm: number = Math.floor(total / 60);
    const ss: number = total % 60;
    return `${mm}:${ss < 10 ? '0' : ''}${ss}`;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%').height('100%').backgroundColor(Color.Black);

      if (this.failed) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle')).fontSize(34).fontColor([Color.White]);
          Text($r('app.string.lvp_cannot_play')).fontSize(15).fontColor(Color.White);
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else {
        XComponent({
          id: `localvideo_${this.instanceId}`,
          type: XComponentType.TEXTURE,
          controller: this.ctrl
        })
          .width('100%').height('100%')
          .onLoad((): void => { this.initPlayer(this.ctrl.getXComponentSurfaceId()); })
          .onDestroy((): void => { this.release(); });
      }

      // 点击层：切换控件显隐。放在画面之上、控件之下，这样点控件本身不会
      // 被它吞掉（HitTestMode.None 只让自己不响应，子节点照样响应，所以这里
      // 用的是一个没有子节点的空 Column）。
      Column()
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent)
        .onClick((): void => this.toggleControls());

      if (this.controlsVisible && !this.failed) {
        Column({ space: 6 }) {
          Row({ space: 12 }) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r(this.playing ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
                .fontSize(22).fontColor([Color.White]);
            }
            .width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText(this.playing ? $r('app.string.lvp_pause') : $r('app.string.lvp_play'))
            .onClick((): void => this.togglePlay());
            Text(LocalVideoPlayer.timeLabel(this.positionMs))
              .fontSize(13).fontColor(Color.White);
            Slider({
              value: this.positionMs,
              min: 0,
              max: this.durationMs > 0 ? this.durationMs : 1,
              step: 1,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .blockColor(Color.White)
              .trackColor('#59FFFFFF')
              .selectedColor(COLOR_PRIMARY)
              .enabled(this.ready && this.durationMs > 0)
              .onChange((value: number, mode: SliderChangeMode): void => {
                if (mode === SliderChangeMode.Begin) {
                  this.seeking = true;
                  this.positionMs = value;
                  return;
                }
                if (mode === SliderChangeMode.Moving) {
                  this.positionMs = value;
                  return;
                }
                this.seeking = false;
                this.seekTo(value);
                this.scheduleHideControls();
              });
            Text(LocalVideoPlayer.timeLabel(this.durationMs))
              .fontSize(13).fontColor(Color.White);
          }
          .width('100%').alignItems(VerticalAlign.Center);
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 24 })
        .backgroundColor('#99000000');
      }

      if (this.controlsVisible) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([Color.White]);
          }
          .width(40).height(40).backgroundColor('#4D000000')
          .accessibilityText($r('app.string.close'))
          .onClick((): void => this.onClose());
          if (this.title !== '') {
            Text(this.title).fontSize(15).fontColor(Color.White)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
          }
        }
        .width('100%').height(56 + this.topSafe)
        .padding({ left: 12, right: 16, top: this.topSafe })
        .alignItems(VerticalAlign.Center)
        .position({ x: 0, y: 0 });
      }
    }
    .width('100%').height('100%');
  }
}
