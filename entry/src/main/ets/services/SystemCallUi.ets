import { voipCall } from '@kit.CallServiceKit';
import { image } from '@kit.ImageKit';
import { avatarPixelMapOrPlaceholder } from '../util/avatarPixelMap';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

// 系统级来电界面（Call Service Kit）。官方完整方案依赖 Push Kit 下发 VoIP
// 消息后上报，但文档同时说明"应用通过自己的网络连接收到来电"也可直接上报
// —— 我们走的正是这条路（TDLib 长连接）。是否被系统接受由真机结果决定，
// 失败时安静退回应用内来电页，不影响既有通话流程。
class SystemCallUi {
  private reportedCallId: string = '';

  // 收到来电（应用存活期间）时调用。返回是否已交给系统展示。
  reportIncoming(callId: number, peerName: string, isVideo: boolean,
    avatarPath: string): void {
    if (callId === 0 || this.reportedCallId !== '') {
      return;
    }
    const id: string = `tg_${callId}`;
    try {
      const placeholder: image.PixelMap = avatarPixelMapOrPlaceholder(avatarPath);
      const attribute: voipCall.VoipCallAttribute = {
        callId: id,
        voipCallType: isVideo
          ? voipCall.VoipCallType.VOIP_CALL_VIDEO : voipCall.VoipCallType.VOIP_CALL_VOICE,
        userName: peerName !== '' ? peerName : str('ns_incoming_call'),
        userProfile: placeholder,
        abilityName: 'EntryAbility',
        voipCallState: voipCall.VoipCallState.VOIP_CALL_STATE_RINGING,
        showBannerForIncomingCall: true
      };
      this.reportedCallId = id;
      voipCall.reportIncomingCall(attribute).then((reason: voipCall.ErrorReason): void => {
        logI(`[SystemCallUi] reportIncomingCall reason=${reason} ` +
          `(0=ERROR_NONE 表示系统已接管来电界面)`); // i18n-exempt: console diagnostic, explains the numeric reason code
        if (reason !== voipCall.ErrorReason.ERROR_NONE) {
          this.reportedCallId = '';
        }
      }).catch((e: Error): void => {
        logE(`[SystemCallUi] reportIncomingCall failed: ${e.message}`);
        this.reportedCallId = '';
      });
    } catch (e) {
      logE(`[SystemCallUi] threw: ${(e as Error).message}`);
      this.reportedCallId = '';
    }
  }

  // 接通：系统界面切到通话中，否则会一直停在"响铃"。
  reportActive(): void {
    if (this.reportedCallId === '') {
      return;
    }
    voipCall.reportCallStateChange(this.reportedCallId,
      voipCall.VoipCallState.VOIP_CALL_STATE_ACTIVE)
      .catch((e: Error): void => {
        logE(`[SystemCallUi] reportActive failed: ${e.message}`);
      });
  }

  // 结束：必须上报，否则系统来电/通话界面不会消失。
  reportEnded(): void {
    const id: string = this.reportedCallId;
    if (id === '') {
      return;
    }
    this.reportedCallId = '';
    voipCall.reportCallStateChange(id, voipCall.VoipCallState.VOIP_CALL_STATE_DISCONNECTED)
      .catch((e: Error): void => {
        logE(`[SystemCallUi] reportEnded failed: ${e.message}`);
      });
  }

  // 接管系统来电界面上的按钮（接听/拒接/挂断/静音）。系统界面是独立进程，
  // 用户在上面的操作只能经这个事件回传，不订阅就等于按钮失灵。
  bindActions(actions: SystemCallActions): void {
    if (this.bound) {
      return;
    }
    this.bound = true;
    try {
      voipCall.on('voipCallUiEvent', (info: voipCall.VoipCallUiEventInfo): void => {
        const event: voipCall.VoipCallUiEvent = info.voipCallUiEvent;
        logI(`[SystemCallUi] ui event=${event} callId=${info.callId}`);
        if (event === voipCall.VoipCallUiEvent.VOIP_CALL_EVENT_VOICE_ANSWER ||
          event === voipCall.VoipCallUiEvent.VOIP_CALL_EVENT_VIDEO_ANSWER) {
          actions.accept();
        } else if (event === voipCall.VoipCallUiEvent.VOIP_CALL_EVENT_REJECT) {
          actions.decline();
        } else if (event === voipCall.VoipCallUiEvent.VOIP_CALL_EVENT_HANGUP) {
          actions.hangup();
        } else if (event === voipCall.VoipCallUiEvent.VOIP_CALL_EVENT_MUTED) {
          actions.setMuted(true);
        } else if (event === voipCall.VoipCallUiEvent.VOIP_CALL_EVENT_UNMUTED) {
          actions.setMuted(false);
        }
      });
    } catch (e) {
      logE(`[SystemCallUi] bindActions failed: ${(e as Error).message}`);
      this.bound = false;
    }
  }

  private bound: boolean = false;

  // 通话结束/被拒/被接听后清理，避免下一通被当作重复上报。
  clear(): void {
    this.reportedCallId = '';
  }
}

// 系统来电界面按钮回传的动作。
export interface SystemCallActions {
  accept: () => void;
  decline: () => void;
  hangup: () => void;
  setMuted: (muted: boolean) => void;
}

export const systemCallUi: SystemCallUi = new SystemCallUi();
