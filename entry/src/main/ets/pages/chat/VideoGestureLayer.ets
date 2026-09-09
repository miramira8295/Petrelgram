import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { AVVolumePanel } from '@ohos.multimedia.avVolumePanel';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE } from '../../util/log';
import { fractionOf, volumeLevelFor } from '../../util/systemVolume';
import { CONTROL_BAR_BG } from '../../util/playerChrome';
import {
  GESTURE_LOCK_VP, GESTURE_ZONE_LEFT, gestureZoneOf, levelAfterDrag
} from '../../util/videoGestures';
import {
  applyWindowBrightness, currentBrightnessLevel, restoreWindowBrightness
} from '../../util/screenBrightness';

// 全屏播放器的竖拖手势层：左半屏调亮度、右半屏调音量。
//
// 【为什么单独一个组件】两套播放引擎并存（ijk / AVPlayer），手感必须一样——
// 和 util/playerChrome、util/videoGestures 同一个理由。两边各挂一次这个组件，
// 判据和 HUD 只写一份。
//
// 【为什么骨架照抄 controlBar】上半 layoutWeight(1) + 底部让出控制条的高度，
// 手势区正好等于那两个 tapZone 的范围。不让的话，在进度条上竖拖会一边拖滑块
// 一边改音量。
//
// 【为什么是 Transparent】这一层压在控制条上面（否则控制条可见时手势被它吃掉），
// 而单击切显隐、双击 ±15s 都在下面的 tapZone 上。HitTestMode.Transparent 让
// 本层响应的同时**不阻塞兄弟节点**，两边都收得到。
//
// 【为什么只认竖向】查看器里左右滑是多媒体消息之间翻页，同一块 surface 上两件
// 事必冲突。PanDirection.Vertical 让横向手势压根不被认领。
//
// 【竖屏横屏】一律用传进来的实际宽高算，不读窗口、不判方向；转屏后调用方给的
// 是新的宽高，比例自然跟着变。
const HUD_KIND_NONE: string = '';
const HUD_KIND_BRIGHTNESS: string = 'brightness';
const HUD_KIND_VOLUME: string = 'volume';

// 控制条大致高度，手势区要让出来。宁可多让一点：让少了会和进度条抢，
// 让多了只是手势区小一圈。
const CONTROL_BAR_RESERVE_VP: number = 96;

@Component
export struct VideoGestureLayer {
  @Prop viewportW: number = 0;
  @Prop viewportH: number = 0;
  // 控制条是否在场——在场就要让出底部那一条。
  @Prop controlsVisible: boolean = false;

  @State private hudKind: string = HUD_KIND_NONE;
  @State private hudLevel: number = 0;

  // 起手时的档位与分区。整个手势锁死在起手那一侧——手指从左半屏拖到右半屏，
  // 调的仍然是亮度。
  private startLevel: number = 0;
  private zone: string = GESTURE_ZONE_LEFT;
  private hudTimer: number = -1;

  // 系统音量：AVVolumePanel 的 volumeLevel 收的是**设备档位（整数）**，给它赋值
  // 就会设置系统音量——这是官方给普通应用的唯一入口（AudioManager.setVolume 要
  // 权限且已废弃，废弃说明点名的替代品就是它）。所以硬件音量键和手势调的是
  // 同一个量，不会各调各的。
  @State private volumePanelLevel: number = -1;
  private volumeMin: number = 0;
  private volumeMax: number = 15;
  // 硬件按键改了音量也要跟着走，否则下一次起手用的是过期的起点。
  private volumeWatch: ((event: audio.VolumeEvent) => void) | null = null;

  private volumeManager(): audio.AudioVolumeManager | null {
    try {
      return audio.getAudioManager().getVolumeManager();
    } catch (e) {
      logE(`VideoGestureLayer.getVolumeManager failed: ${e}`);
      return null;
    }
  }

  // 当前系统音量的比例（0..1）。读不到就退回中点——读不到就别装作读到了。
  private systemVolumeFraction(): number {
    const mgr = this.volumeManager();
    if (mgr === null) {
      return 0.5;
    }
    try {
      const usage: audio.StreamUsage = audio.StreamUsage.STREAM_USAGE_MOVIE;
      this.volumeMin = mgr.getMinVolumeByStream(usage);
      this.volumeMax = mgr.getMaxVolumeByStream(usage);
      return fractionOf(mgr.getVolumeByStream(usage), this.volumeMin, this.volumeMax);
    } catch (e) {
      logE(`VideoGestureLayer.readSystemVolume failed: ${e}`);
      return 0.5;
    }
  }

  aboutToAppear(): void {
    const mgr = this.volumeManager();
    if (mgr === null) {
      return;
    }
    this.volumeWatch = (event: audio.VolumeEvent): void => {
      if (event.volumeType === audio.AudioVolumeType.MEDIA && this.hudKind === HUD_KIND_VOLUME) {
        this.hudLevel = fractionOf(event.volume, this.volumeMin, this.volumeMax);
      }
    };
    try {
      mgr.on('volumeChange', this.volumeWatch);
    } catch (e) {
      logE(`VideoGestureLayer.on(volumeChange) failed: ${(e as BusinessError).message}`);
    }
  }

  aboutToDisappear(): void {
    const mgr = this.volumeManager();
    if (mgr !== null && this.volumeWatch !== null) {
      try {
        mgr.off('volumeChange', this.volumeWatch);
      } catch (e) {
        logE(`VideoGestureLayer.off(volumeChange) failed: ${(e as BusinessError).message}`);
      }
    }
    this.volumeWatch = null;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    // **必须还原**，否则整个应用会一直被压在用户划到的那个亮度上。
    restoreWindowBrightness(getContext(this) as common.UIAbilityContext);
  }

  // 名字不能叫 onDragStart/onDragEnd：那几个是 CustomComponent 自带的成员，
  // 同名会被编译器判为不兼容的覆盖（和 VideoBubbleSurface 里 sourceWidth
  // 不能叫 width 是同一类坑）。
  private beginAdjust(event: GestureEvent): void {
    const fingers = event.fingerList;
    const startX: number = fingers.length > 0 ? fingers[0].localX : this.viewportW / 2;
    this.zone = gestureZoneOf(startX, this.viewportW);
    if (this.zone === GESTURE_ZONE_LEFT) {
      this.startLevel = currentBrightnessLevel();
      this.hudKind = HUD_KIND_BRIGHTNESS;
    } else {
      this.startLevel = this.systemVolumeFraction();
      this.hudKind = HUD_KIND_VOLUME;
    }
    this.hudLevel = this.startLevel;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
  }

  private updateAdjust(event: GestureEvent): void {
    const next: number = levelAfterDrag(this.startLevel, event.offsetY, this.viewportH);
    this.hudLevel = next;
    if (this.zone === GESTURE_ZONE_LEFT) {
      applyWindowBrightness(getContext(this) as common.UIAbilityContext, next);
    } else {
      this.volumePanelLevel = volumeLevelFor(next, this.volumeMin, this.volumeMax);
    }
  }

  private endAdjust(): void {
    // HUD 停留一下再走，松手就消失看不清最后停在哪一档。
    this.hudTimer = setTimeout((): void => {
      this.hudTimer = -1;
      this.hudKind = HUD_KIND_NONE;
    }, 600);
  }

  @Builder
  hud() {
    Row({ space: 10 }) {
      if (this.hudKind === HUD_KIND_BRIGHTNESS) {
        SymbolGlyph($r('sys.symbol.sun_max_fill')).fontSize(20).fontColor([Color.White]);
      } else if (this.hudLevel <= 0.001) {
        SymbolGlyph($r('sys.symbol.speaker_slash_fill')).fontSize(20).fontColor([Color.White]);
      } else {
        SymbolGlyph($r('sys.symbol.speaker_wave_2_fill')).fontSize(20).fontColor([Color.White]);
      }
      Stack({ alignContent: Alignment.Start }) {
        Row().width(104).height(4).borderRadius(2).backgroundColor('#59FFFFFF');
        Row()
          .width(104 * Math.max(0, Math.min(1, this.hudLevel)))
          .height(4).borderRadius(2).backgroundColor(Color.White);
      }.width(104).height(4);
      Text(`${Math.round(this.hudLevel * 100)}`)
        .fontSize(13).fontColor(Color.White).width(28)
        .textAlign(TextAlign.End);
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(CONTROL_BAR_BG)
    .borderRadius(20)
    // HUD 纯展示，绝不能吃手势——手指正压在它上面继续拖。
    .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Column() {
      Stack() {
        if (this.hudKind !== HUD_KIND_NONE) {
          this.hud();
        }
        // 系统音量的**驱动件**，不是界面：给它的 volumeLevel 赋值就会设置设备
        // 音量。只在调音量时挂，宽高 0 + 不吃手势——手指正压在这块地方继续拖。
        if (this.hudKind === HUD_KIND_VOLUME && this.volumePanelLevel >= 0) {
          AVVolumePanel({ volumeLevel: this.volumePanelLevel })
            .width(0).height(0)
            .hitTestBehavior(HitTestMode.None);
        }
      }
      .width('100%')
      .layoutWeight(1)
      .hitTestBehavior(HitTestMode.Transparent)
      .gesture(
        PanGesture({ fingers: 1, distance: GESTURE_LOCK_VP, direction: PanDirection.Vertical })
          .onActionStart((event: GestureEvent): void => { this.beginAdjust(event); })
          .onActionUpdate((event: GestureEvent): void => { this.updateAdjust(event); })
          .onActionEnd((): void => { this.endAdjust(); })
          .onActionCancel((): void => { this.endAdjust(); })
      );
      if (this.controlsVisible) {
        Column().width('100%').height(CONTROL_BAR_RESERVE_VP);
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.Transparent);
  }
}
