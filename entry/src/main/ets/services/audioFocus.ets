// 音频焦点：别的应用或来电开始发声时，让我们自己停下来。
//
// 官方《基于AVPlayer播放长视频实践》给的做法是 AVPlayer.on('audioInterrupt')，
// 但本应用的视频走的是 ijkplayer，拿不到那个回调。官方文档《查询和监听音频输出
// 设备》正好写明了这种处境的出路：
//
//   「应用使用播放器的 SDK 播放音频流，不持有 AudioRenderer 对象，因此无法灵活
//     控制播放设备的选择和状态监听。从 API version 20 开始，AudioSession 不仅
//     增加了焦点管理功能，还提供了音频输出设备管理功能。」
//
// 于是走 AudioSessionManager：激活会话拿到系统的默认焦点策略，再监听
// audioSessionStateChanged。@since 20 == 本应用的 compatibleSdkVersion 6.0.0(20)，
// 所有目标设备都有，不需要运行时判版本。
//
// 引用计数而不是单一开关：AudioSession 是**应用级**的，一次 deactivate 会影响
// 应用里所有还在响的东西。将来语音消息、直播也接进来时，谁先来谁激活、谁最后
// 走谁停用，不必各自记账。
//
// 这里不碰播放器：只负责"系统说该停/该继续了"，怎么停由订阅方决定。

import { audio } from '@kit.AudioKit';
import { logE } from '../util/log';

// 系统要求我们做什么。
export const FOCUS_PAUSE: string = 'pause';    // 让位：暂停，等 resume
export const FOCUS_RESUME: string = 'resume';  // 打断结束：可以接着放
export const FOCUS_STOP: string = 'stop';      // 永久失去焦点：停下且**不要**自动恢复

export type AudioFocusListener = (action: string) => void;

const listeners: AudioFocusListener[] = [];
let holders: number = 0;
let sessionManager: audio.AudioSessionManager | null = null;
let subscribed: boolean = false;

// 枚举只在函数体里解引用，绝不放模块级——v1.3.6 的启动崩溃就是模块级取高
// 版本枚举成员造成的（见 util/overlayMaterial 的说明）。
function actionOf(hint: audio.AudioSessionStateChangeHint): string {
  if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) {
    return FOCUS_PAUSE;
  }
  if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
    return FOCUS_RESUME;
  }
  if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP ||
    hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP) {
    return FOCUS_STOP;
  }
  // DUCK / MUTE 这几档不转成暂停：那是"把音量压低让别人说话"，视频该继续放，
  // 压音量由系统自己完成。转成暂停会把导航播报这类瞬时提示变成打断。
  return '';
}

function managerOf(): audio.AudioSessionManager | null {
  if (sessionManager === null) {
    try {
      sessionManager = audio.getAudioManager().getSessionManager();
    } catch (e) {
      logE(`audioFocus.getSessionManager failed: ${e}`);
      sessionManager = null;
    }
  }
  return sessionManager;
}

function notify(action: string): void {
  if (action === '') {
    return;
  }
  // 复制一份再遍历：回调里可能会调 releaseAudioFocus 把自己摘掉。
  for (const listener of [...listeners]) {
    listener(action);
  }
}

function subscribe(manager: audio.AudioSessionManager): void {
  if (subscribed) {
    return;
  }
  try {
    manager.on('audioSessionStateChanged', (event: audio.AudioSessionStateChangedEvent): void => {
      notify(actionOf(event.stateChangeHint));
    });
    subscribed = true;
  } catch (e) {
    logE(`audioFocus.on(audioSessionStateChanged) failed: ${e}`);
  }
}

// 开始播放时调。返回的函数在停止播放时调，调多次是幂等的。
export function acquireAudioFocus(listener: AudioFocusListener): () => void {
  const manager = managerOf();
  listeners.push(listener);
  holders += 1;
  if (manager !== null) {
    subscribe(manager);
    if (holders === 1) {
      // CONCURRENCY_DEFAULT：系统默认焦点策略——别人抢焦点我们就该让位，
      // 这正是"别的应用/来电开始发声时自动暂停"要的行为。
      const strategy: audio.AudioSessionStrategy = {
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
      };
      manager.activateAudioSession(strategy).catch((e: Error): void => {
        logE(`audioFocus.activateAudioSession failed: ${e.message}`);
      });
    }
  }
  let released: boolean = false;
  return (): void => {
    if (released) {
      return;
    }
    released = true;
    const at: number = listeners.indexOf(listener);
    if (at >= 0) {
      listeners.splice(at, 1);
    }
    holders = Math.max(0, holders - 1);
    if (holders === 0 && manager !== null) {
      manager.deactivateAudioSession().catch((e: Error): void => {
        logE(`audioFocus.deactivateAudioSession failed: ${e.message}`);
      });
    }
  };
}
