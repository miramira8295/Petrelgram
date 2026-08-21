import { router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { getCallSession } from '../../tdkit/Globals';
import { CallSession, CallSnapshot } from '../../services/CallSession';
import { AvatarView } from '../chatlist/AvatarView';
import {
  callPhaseLabel, callDurationLabel, callEndLabel
} from '../../util/callPresentation';
import { CALL_VIDEO_OFF, CALL_VIDEO_FRONT } from '../../services/CallMediaBridge';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logI } from '../../util/log';

const BG_COLOR: string = '#FF17212B';
const CONTROL_BG: string = '#33FFFFFF';
const DANGER: string = '#FFE5484D';
const ACCEPT: string = '#FF31C48D';

// 1对1 通话页：单页覆盖 拨出/来电/通话中/已结束 四态，状态由 CallSession 驱动。
@Entry
@Component
struct CallPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State snap: CallSnapshot | null = null;
  @State nowMs: number = 0;
  private unsub: (() => void) | null = null;
  private tickTimer: number = -1;
  private closeTimer: number = -1;
  private remoteController: XComponentController = new XComponentController();
  private localController: XComponentController = new XComponentController();
  // 记录当前绑定的 surfaceId：重挂时旧组件的 onDestroy 可能晚于新组件的
  // onLoad 触发，无条件清零会抹掉新绑定（帧照刷、屏幕不显示）。
  private boundRemoteSurface: string = '0';
  private boundLocalSurface: string = '0';

  aboutToAppear(): void {
    const session: CallSession = getCallSession();
    this.unsub = session.subscribe((s: CallSnapshot): void => {
      this.snap = s;
      if (s.phase === 'ended' && this.closeTimer === -1) {
        this.closeTimer = setTimeout((): void => {
          router.back();
        }, 1500);
      }
    });
    this.tickTimer = setInterval((): void => {
      this.nowMs = Date.now();
    }, 1000);
    this.requestCallPermissions();
  }

  // 首次通话前申请麦克风（视频通话再加摄像头）。拒绝不阻断页面 ——
  // 无权限时对端听不到本端，由用户自行退出；后续可加显式提示。
  private requestCallPermissions(): void {
    const permissions: Permissions[] = ['ohos.permission.MICROPHONE'];
    if (this.snap !== null && this.snap.isVideo) {
      permissions.push('ohos.permission.CAMERA');
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, permissions)
        .catch((error: Error): void => {
          logE(`CallPage permission request failed: ${error.message}`);
        });
    } catch (e) {
      logE(`CallPage permission request threw: ${(e as Error).message}`);
    }
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    if (this.closeTimer !== -1) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }

  // 尚无悬浮窗/最小化形态：返回即结束通话，避免离开页面后通话变成
  // 无法找回的"孤儿"。响铃中返回视为拒接。
  onBackPress(): boolean {
    const s = this.snap;
    if (s === null || s.phase === 'ended' || s.phase === 'idle') {
      return false;
    }
    if (s.phase === 'ringing') {
      getCallSession().decline();
    } else {
      getCallSession().hangup();
    }
    return false; // 挂断后仍允许返回
  }

  private statusLine(): string {
    const s = this.snap;
    if (s === null) {
      return '';
    }
    if (s.phase === 'ended') {
      return callEndLabel(s.endReason, s.errorText);
    }
    if (s.phase === 'active') {
      return callDurationLabel(s.startedAtMs, this.nowMs === 0 ? Date.now() : this.nowMs);
    }
    return callPhaseLabel(s.phase, s.isVideo);
  }

  private videoActive(): boolean {
    const s = this.snap;
    return s !== null && s.phase === 'active' &&
      (s.remoteVideoActive || s.localVideoMode !== CALL_VIDEO_OFF);
  }

  // 图标一律用仓库其它页面验证过的符号名（无效符号名会静默画成空白）。
  @Builder
  roundControl(symbol: string, label: string, bg: string, rotateDeg: number, onTap: () => void) {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph($r(symbol)).fontSize(24).fontColor([Color.White])
          .rotate({ angle: rotateDeg });
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor(bg)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => { onTap(); });
      if (label !== '') {
        Text(label).fontSize(11).fontColor('#B8C4CF');
      }
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  identityHeader() {
    Column({ space: 12 }) {
      AvatarView({
        avatarPath: '', initials: this.snap !== null && this.snap.peerName !== ''
          ? this.snap.peerName.substring(0, 1).toUpperCase() : '?',
        colorSeed: this.snap !== null ? this.snap.peerUserId : 0,
        avatarSize: 96
      });
      Text(this.snap !== null && this.snap.peerName !== '' ? this.snap.peerName : $r('app.string.pp_call'))
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '86%' });
      Text(this.statusLine())
        .fontSize(15).fontColor('#B8C4CF');
      if (this.snap !== null && this.snap.phase === 'active' && this.snap.emojis.length > 0) {
        // 端到端加密校验 emoji：双方一致即链路未被中间人替换。
        Text(this.snap.emojis.join(' ')).fontSize(18).margin({ top: 2 });
      }
    }
    .alignItems(HorizontalAlign.Center);
  }

  // 有状态的按钮必须是无参 builder 直接读 this.snap：@Builder 的值参数
  // 不随 @State 变化重新求值（见 ChatProfilePage.muteButton 的同款注释）。
  @Builder
  muteControl() {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.mic')).fontSize(24)
          .fontColor([this.snap !== null && this.snap.muted ? Color.Black : Color.White]);
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor(this.snap !== null && this.snap.muted ? '#E6FFFFFF' : CONTROL_BG)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => { getCallSession().toggleMute(); });
      Text(this.snap !== null && this.snap.muted ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'))
        .fontSize(11).fontColor('#B8C4CF');
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  speakerControl() {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.speaker')).fontSize(24)
          .fontColor([this.snap !== null && this.snap.speakerOn ? Color.Black : Color.White]);
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor(this.snap !== null && this.snap.speakerOn ? '#E6FFFFFF' : CONTROL_BG)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => { getCallSession().toggleSpeaker(); });
      Text($r('app.string.call_speaker')).fontSize(11).fontColor('#B8C4CF');
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  videoToggleControl() {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.video')).fontSize(24)
          .fontColor([this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF
            ? Color.Black : Color.White]);
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor(this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF
        ? '#E6FFFFFF' : CONTROL_BG)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => {
        const s = this.snap;
        if (s !== null) {
          getCallSession().setVideoMode(
            s.localVideoMode === CALL_VIDEO_OFF ? CALL_VIDEO_FRONT : CALL_VIDEO_OFF);
        }
      });
      Text(this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF ? $r('app.string.call_video_off') : $r('app.string.storage_video'))
        .fontSize(11).fontColor('#B8C4CF');
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  activeControls() {
    Row({ space: 14 }) {
      this.muteControl();
      this.speakerControl();
      this.videoToggleControl();
      if (this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF) {
        this.roundControl('sys.symbol.arrow_clockwise', str('call_switch'), CONTROL_BG, 0,
          (): void => { getCallSession().switchCamera(); });
      }
      // phone_fill 旋转 135° 作挂断（repo 无验证过的 phone_down 符号）。
      this.roundControl('sys.symbol.phone_fill', str('call_hang_up'), DANGER, 135,
        (): void => { getCallSession().hangup(); });
    }
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  ringingControls() {
    Row() {
      this.roundControl('sys.symbol.phone_fill', str('ga_decline'), DANGER, 135,
        (): void => { getCallSession().decline(); });
      Blank().layoutWeight(1);
      this.roundControl(
        this.snap !== null && this.snap.isVideo ? 'sys.symbol.video' : 'sys.symbol.phone_fill',
        str('call_answer'), ACCEPT, 0,
        (): void => { getCallSession().accept(); });
    }
    .width('62%');
  }

  @Builder
  dialingControls() {
    this.roundControl('sys.symbol.phone_fill', str('call_hang_up'), DANGER, 135,
      (): void => { getCallSession().hangup(); });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor(BG_COLOR);
      // 远端视频全屏（TEXTURE 参与 ArkUI 合成，覆盖层才能正常显示）。
      if (this.videoActive()) {
        XComponent({
          id: 'call_remote_video',
          type: XComponentType.TEXTURE,
          controller: this.remoteController
        })
          .onLoad((): void => {
            const surfaceId: string = this.remoteController.getXComponentSurfaceId();
            this.boundRemoteSurface = surfaceId;
            logI(`CallPage remote surface bind ${surfaceId}`);
            getCallSession().setRemoteSurface(surfaceId);
          })
          .onDestroy((): void => {
            // 仅当仍绑定着本组件的 surface 时才清除，避免抹掉重挂后的新绑定。
            const surfaceId: string = this.remoteController.getXComponentSurfaceId();
            if (this.boundRemoteSurface === surfaceId) {
              this.boundRemoteSurface = '0';
              logI(`CallPage remote surface clear ${surfaceId}`);
              getCallSession().setRemoteSurface('0');
            }
          })
          .width('100%').height('100%');
      }
      Column() {
        this.identityHeader();
        Blank().layoutWeight(1);
        if (this.snap !== null && this.snap.phase === 'ringing') {
          this.ringingControls();
        } else if (this.snap !== null &&
          (this.snap.phase === 'dialing' || this.snap.phase === 'connecting')) {
          this.dialingControls();
        } else if (this.snap !== null && this.snap.phase === 'active') {
          this.activeControls();
        }
      }
      .width('100%').height('100%')
      .padding({ top: this.topSafe + 46, bottom: this.bottomSafe + 42 })
      .alignItems(HorizontalAlign.Center);
      // 本地预览小窗（右上角）。
      if (this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF &&
        this.snap.phase === 'active') {
        XComponent({
          id: 'call_local_preview',
          type: XComponentType.TEXTURE,
          controller: this.localController
        })
          .onLoad((): void => {
            const surfaceId: string = this.localController.getXComponentSurfaceId();
            this.boundLocalSurface = surfaceId;
            logI(`CallPage local surface bind ${surfaceId}`);
            getCallSession().setLocalSurface(surfaceId);
          })
          .onDestroy((): void => {
            const surfaceId: string = this.localController.getXComponentSurfaceId();
            if (this.boundLocalSurface === surfaceId) {
              this.boundLocalSurface = '0';
              logI(`CallPage local surface clear ${surfaceId}`);
              getCallSession().setLocalSurface('0');
            }
          })
          .width(104).height(150)
          .borderRadius(10)
          .clip(true)
          .position({ x: '68%', y: this.topSafe + 12 });
      }
    }
    .width('100%').height('100%');
  }
}
