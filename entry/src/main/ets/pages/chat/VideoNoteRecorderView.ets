import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import {
  VideoNoteRecorder, VideoNoteOpenResult, VIDEO_NOTE_MAX_SECONDS
} from '../../services/VideoNoteRecorder';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';

type VideoNotePhase = 'opening' | 'ready' | 'recording' | 'sending' | 'error';

const PREVIEW_SIDE: number = 260;
const RING_SIDE: number = 276;
// 上滑取消的触发距离：太短容易被握持抖动误触发，太长够不着。
const CANCEL_DISTANCE_VP: number = 70;
const TICK_MS: number = 200;
// 短于这个时长的多半是误触，直接当取消处理（与 Telegram 的手感一致）。
const MIN_RECORD_MS: number = 800;

// 圆形视频消息的录制浮层：圆形取景 + 按住录制 / 松手发送 / 上滑取消。
// 只负责采集，产出的文件路径交给调用方去发消息。
@Component
export struct VideoNoteRecorderView {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  onCaptured: (path: string, durationSec: number, length: number) => void =
    (): void => {};
  onClose: () => void = (): void => {};
  // 全屏浮层要自己避让状态栏：不加这个 padding，顶部那行会被压在状态栏
  // 底下，点击落到系统层而不是应用。
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // 前后摄像头。圆形视频默认自拍，所以起手是前置。
  @State private useFront: boolean = true;
  @State private canSwitchCamera: boolean = false;
  @State private previewRotation: number = 0;

  @State phase: VideoNotePhase = 'opening';
  @State errorText: string = '';
  @State elapsedMs: number = 0;
  @State willCancel: boolean = false;

  private controller: XComponentController = new XComponentController();
  private recorder: VideoNoteRecorder | null = null;
  private tickTimer: number = -1;
  private pressed: boolean = false;
  private touchStartY: number = 0;
  // 文件已经交给调用方发送后，浮层退场时不能再去删它。
  private consumed: boolean = false;
  private opening: boolean = false;

  aboutToDisappear(): void {
    this.stopTick();
    const recorder: VideoNoteRecorder | null = this.recorder;
    this.recorder = null;
    if (recorder !== null && !this.consumed) {
      recorder.cancel();
    }
  }

  private openCamera(): void {
    if (this.opening || this.recorder !== null) {
      return;
    }
    const surfaceId: string = this.controller.getXComponentSurfaceId();
    if (surfaceId === '') {
      this.phase = 'error';
      this.errorText = str('vn_preview_failed');
      return;
    }
    this.opening = true;
    const recorder: VideoNoteRecorder = new VideoNoteRecorder();
    this.recorder = recorder;
    recorder.open(getContext(this) as common.UIAbilityContext, surfaceId, this.useFront)
      .then((result: VideoNoteOpenResult): void => {
        this.opening = false;
        if (this.recorder !== recorder) {
          // 浮层已经退场，回调迟到了。
          recorder.cancel();
          return;
        }
        if (result === 'ok') {
          this.phase = 'ready';
          this.canSwitchCamera = recorder.bothCameras;
          this.previewRotation = recorder.previewRotationDeg;
          return;
        }
        this.phase = 'error';
        this.errorText = result === 'denied'
          ? str('vn_needs_permission')
          : str('vn_camera_failed');
      })
      .catch((e: Object): void => {
        this.opening = false;
        logE(`VideoNoteRecorderView.openCamera failed: ${JSON.stringify(e)}`);
        this.phase = 'error';
        this.errorText = str('vn_camera_failed');
      });
  }

  private startTick(): void {
    this.stopTick();
    this.tickTimer = setInterval((): void => {
      this.elapsedMs += TICK_MS;
      if (this.elapsedMs >= VIDEO_NOTE_MAX_SECONDS * 1000) {
        // 到达 60 秒上限自动收尾，超时的圆形视频服务端会拒绝。
        this.finish();
      }
    }, TICK_MS);
  }

  private stopTick(): void {
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  // 切换前后摄像头：录制中不允许切（会打断这一条），只在待机时生效。
  private switchCamera(): void {
    if (this.phase !== 'ready' || this.opening) {
      return;
    }
    const recorder: VideoNoteRecorder | null = this.recorder;
    this.recorder = null;
    if (recorder !== null) {
      recorder.cancel();
    }
    this.useFront = !this.useFront;
    this.phase = 'opening';
    this.openCamera();
  }

  private beginRecord(): void {
    const recorder: VideoNoteRecorder | null = this.recorder;
    if (this.phase !== 'ready' || recorder === null) {
      return;
    }
    recorder.beginRecord().then((ok: boolean): void => {
      if (this.recorder !== recorder) {
        return;
      }
      if (!ok) {
        this.phase = 'error';
        this.errorText = str('vn_record_failed');
        return;
      }
      this.phase = 'recording';
      this.elapsedMs = 0;
      this.startTick();
      if (!this.pressed) {
        // 起录比手指松开还慢，补一次收尾，否则会一直录下去。
        if (this.willCancel) {
          this.cancelRecord();
        } else {
          this.finish();
        }
      }
    }).catch((e: Object): void => {
      logE(`VideoNoteRecorderView.beginRecord failed: ${JSON.stringify(e)}`);
      this.phase = 'error';
      this.errorText = str('vn_record_failed');
    });
  }

  private finish(): void {
    const recorder: VideoNoteRecorder | null = this.recorder;
    if (this.phase !== 'recording' || recorder === null) {
      return;
    }
    if (this.elapsedMs < MIN_RECORD_MS) {
      // 按太短只是这一条不算，不该把整个录制界面关掉——用户多半是想重录。
      promptAction.showToast({ message: $r('app.string.vn_hold_to_record'), duration: 1600 });
      this.discardTake();
      return;
    }
    this.stopTick();
    this.phase = 'sending';
    recorder.stop().then((durationSec: number): void => {
      if (durationSec > 0 && recorder.path !== '') {
        this.consumed = true;
        this.onCaptured(recorder.path, durationSec, recorder.length);
      }
      this.onClose();
    }).catch((e: Object): void => {
      logE(`VideoNoteRecorderView.finish failed: ${JSON.stringify(e)}`);
      this.onClose();
    });
  }

  // 放弃当前这条录制，但保持摄像头开着、界面不退。和 cancelRecord 的区别
  // 就在于后者会 onClose()。
  private discardTake(): void {
    this.stopTick();
    const recorder: VideoNoteRecorder | null = this.recorder;
    if (recorder !== null) {
      recorder.cancel();
    }
    this.recorder = null;
    this.phase = 'opening';
    this.elapsedMs = 0;
    this.willCancel = false;
    this.openCamera();
  }

  private cancelRecord(): void {
    this.stopTick();
    const recorder: VideoNoteRecorder | null = this.recorder;
    this.recorder = null;
    if (recorder !== null) {
      recorder.cancel();
    }
    this.onClose();
  }

  private onRecordTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return;
    }
    const y: number = event.touches[0].windowY;
    if (event.type === TouchType.Down) {
      this.pressed = true;
      this.willCancel = false;
      this.touchStartY = y;
      this.beginRecord();
      return;
    }
    if (event.type === TouchType.Move) {
      this.willCancel = this.touchStartY - y > CANCEL_DISTANCE_VP;
      return;
    }
    // Up / Cancel
    this.pressed = false;
    if (this.phase !== 'recording') {
      return;
    }
    if (this.willCancel) {
      this.discardTake();
    } else {
      this.finish();
    }
  }

  private secondsLabel(): string {
    const total: number = Math.floor(this.elapsedMs / 1000);
    const m: number = Math.floor(total / 60);
    const s: number = total % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  private hintText(): string {
    if (this.phase === 'error') {
      return this.errorText;
    }
    if (this.phase === 'opening') {
      return str('vn_opening_camera');
    }
    if (this.phase === 'sending') {
      return str('vn_sending');
    }
    if (this.phase === 'recording') {
      return this.willCancel ? str('vn_release_to_cancel') : str('vn_swipe_cancel');
    }
    return str('vn_hold_hint');
  }

  build() {
    Column() {
      Row() {
        Blank();
        if (this.canSwitchCamera) {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_triangle_2_circlepath_camera'))
              .fontSize(21).fontColor([Color.White]);
          }
          .width(44).height(44).borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#33FFFFFF')
          .margin({ right: 10 })
          .enabled(this.phase === 'ready')
          .accessibilityText(this.useFront ? $r('app.string.vn_switch_rear') : $r('app.string.vn_switch_front'))
          .onClick((): void => { this.switchCamera(); });
        }
        // 点击热区交给容器：裸图标只有 22vp，在屏幕角落几乎点不中。
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22).fontColor([Color.White]);
        }
        .width(44).height(44).borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#33FFFFFF')
        .accessibilityText($r('app.string.vn_close'))
        .onClick((): void => { this.cancelRecord(); });
      }
      .width('100%').height(56 + this.topSafe)
      .padding({ left: 16, right: 12, top: this.topSafe })
      .alignItems(VerticalAlign.Center);

      Blank();

      Stack({ alignContent: Alignment.Center }) {
        // 60 秒进度环包在取景圆外面，录制时才可见。
        Progress({
          value: Math.min(this.elapsedMs / 1000, VIDEO_NOTE_MAX_SECONDS),
          total: VIDEO_NOTE_MAX_SECONDS,
          type: ProgressType.Ring
        })
          .width(RING_SIDE).height(RING_SIDE)
          .color(this.willCancel ? '#FF3B30' : '#3390EC')
          .backgroundColor('#33FFFFFF')
          .style({ strokeWidth: 4 })
          .visibility(this.phase === 'recording' || this.phase === 'sending'
            ? Visibility.Visible : Visibility.Hidden);
        Stack() {
          // TEXTURE 参与 ArkUI 合成，圆形裁剪才会生效；SURFACE 是独立图层，
          // 叠加裁剪/浮层后画面会变黑（参考 LiveStreamViewerPage 的同款说明）。
          XComponent({
            id: 'video_note_preview',
            type: XComponentType.TEXTURE,
            controller: this.controller
          })
            .width(PREVIEW_SIDE).height(PREVIEW_SIDE)
            // 取景框是正方形，旋转不影响构图。
            .rotate({ angle: this.previewRotation })
            .onLoad((): void => { this.openCamera(); });
        }
        .width(PREVIEW_SIDE).height(PREVIEW_SIDE)
        .borderRadius(PREVIEW_SIDE / 2)
        .clip(true)
        .backgroundColor('#1C1C1E');
      }
      .width(RING_SIDE).height(RING_SIDE);

      Text(this.secondsLabel())
        .fontSize(17).fontColor(Color.White)
        .margin({ top: 18 })
        .visibility(this.phase === 'recording' || this.phase === 'sending'
          ? Visibility.Visible : Visibility.Hidden);

      Text(this.hintText())
        .fontSize(14)
        .fontColor(this.phase === 'error' ? '#FF3B30' : '#B0B3B8')
        .margin({ top: 8 })
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 });

      Blank();

      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 84, height: 84 })
          .fill(this.willCancel ? '#FF3B30' : '#3390EC')
          .opacity(this.phase === 'recording' ? 1 : 0.85);
        if (this.phase === 'sending') {
          LoadingProgress().width(28).height(28).color(Color.White);
        } else {
          SymbolGlyph($r('sys.symbol.video_fill'))
            .fontSize(30).fontColor([Color.White]);
        }
      }
      .width(96).height(96)
      .scale({
        x: this.phase === 'recording' ? 1.12 : 1,
        y: this.phase === 'recording' ? 1.12 : 1
      })
      .animation({ duration: 140, curve: Curve.EaseOut })
      .enabled(this.phase === 'ready' || this.phase === 'recording')
      .accessibilityText($r('app.string.vn_hold_to_record'))
      .onTouch((event: TouchEvent): void => { this.onRecordTouch(event); })
      .margin({ bottom: 48 });
    }
    .width('100%').height('100%')
    .backgroundColor('#F2000000');
  }
}
