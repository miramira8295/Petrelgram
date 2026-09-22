// 全屏视频播放器的**外观与手感常量**，以及两个纯格式化函数。
//
// 【为什么单独一个文件】现在有两套播放引擎并存：ijkplayer 的
// StreamingVideoPlayer 和系统 AVPlayer 的 AvVideoPlayer（见 util/videoEngine
// 的说明）。两边的控制条必须长得一模一样、手感一模一样，否则用户切一下引擎
// 就发现界面变了。常量放一处是唯一能保证这件事的做法。
//
// 只放**与引擎无关**的东西。任何一句 IjkMediaPlayer / media.AVPlayer 的调用
// 都不属于这里。

import { audio } from '@kit.AudioKit';

export const CONTROL_BAR_BG: string = '#6e3e3e40';

// **一律字面白，不跟主题。**
//
// 'viewer' 这一面不用沉浸材质，底色固定成深色半透明（见 util/overlayMaterial
// 的 usesImmersiveMaterial）——身后是用户随便一张照片，没有任何自适应能成立。
// 底既然恒暗，前景就该恒白，和压在视频画面上的那些元素统一。
export const CONTROL_ACCENT: ResourceColor = '#FFFFFF';
export const CONTROL_TEXT_SOFT: ResourceColor = '#EAEEF2';
// 进度条自后向前三层：未缓冲底槽 → 已下载段 → 已播放段。
export const CONTROL_TRACK_SOFT: string = '#804C5259';
export const CONTROL_TRACK_SOFT_FILL: string = '#8E969E';
// 已播放段和拇指同色。
export const CONTROL_TRACK: ResourceColor = '#FFFFFF';

export const SPEEDS: string[] = ['0.5', '1.0', '1.5', '2.0'];
export const SPEED_LABELS: string[] = ['0.5x', '1.0x', '1.5x', '2.0x'];
export const DEFAULT_SPEED_IDX: number = 1;

// 双击左右半屏的跳转量。
export const QUICK_SEEK_MS: number = 15_000;

// 长按快退/快进（issue #160）：按住这么久算长按，之后每隔同样的时长再跳一次
// HOLD_SEEK_STEP_MS。500 是系统默认值，取小一点更跟手；再小会和双击抢。
export const LONG_PRESS_SEEK_MS: number = 400;

// 长按连续快进/快退**每一跳**的步长。
//
// 【为什么和双击分开】原来两者共用 QUICK_SEEK_MS，于是按住不放是每 400ms 跳
// 15 秒——37 倍速，根本不是"快进"而是连续瞬移，想停在某一处只能靠运气
// （用户 2026-09-22：「播放器长按会有连续快进 15s 改成 2s」）。2 秒 / 400ms
// 是 5 倍速，按住能看着画面走、松手停得住。
// 双击那一下仍然是 15 秒：那是"跳过片头"的量，和连续拖动不是一回事。
export const HOLD_SEEK_STEP_MS: number = 2_000;

// 状态文字「延迟出现」的门槛。见 util/playerStatusGate（issue #192）。
export const STATUS_DELAY_MS: number = 350;

// 出错后自动重试的间隔（ms），用完为止。第一次失败多半是文件刚开始下载
// 播放器就去开的竞态（issue #127），几百毫秒后再开通常就好了。
export const AUTO_RETRY_DELAYS_MS: number[] = [300, 900, 2000];

// 算「耳机」的输出设备类型：拔掉/断开其中之一就暂停，而不是外放炸出来。
export const HEADSET_DEVICE_TYPES: audio.DeviceType[] = [
  audio.DeviceType.WIRED_HEADSET,
  audio.DeviceType.WIRED_HEADPHONES,
  audio.DeviceType.BLUETOOTH_SCO,
  audio.DeviceType.BLUETOOTH_A2DP
];

// 快进/快退角标该显示多少秒（毫秒，正数）。
//
// 【为什么要累加】双击是一下跳 15 秒，角标写死"15 秒"就够了。长按改成每 400ms
// 跳 HOLD_SEEK_STEP_MS（2 秒）之后，写死一个数就开始撒谎——按住两秒实际走了
// 10 秒，角标还在说 2 秒。同一侧连着跳就把量加起来，松手（角标淡出）后下一次
// 从头算。换一侧也从头算：从"快进 6 秒"直接接着数到"后退 8 秒"没有意义。
//
// visible = 角标此刻还亮着（淡出计时器还没到），currentSide/currentMs 是它正在
// 显示的那一份。
export function nextSeekFeedbackMs(
  visible: boolean, currentSide: number, currentMs: number, deltaMs: number
): number {
  const step: number = Math.abs(deltaMs);
  const side: number = deltaMs < 0 ? -1 : 1;
  return visible && currentSide === side ? currentMs + step : step;
}

// mm:ss（超过一小时给 h:mm:ss）。
export function formatMs(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  const mm = h > 0 ? `${m}`.padStart(2, '0') : `${m}`;
  const ss = `${s}`.padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

// 下载吞吐（字节/秒 → "1.2 MB/s" / "340 KB/s"）。
export function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec >= 1024 * 1024) {
    return `${(bytesPerSec / (1024 * 1024)).toFixed(1)} MB/s`;
  }
  if (bytesPerSec >= 1024) {
    return `${Math.round(bytesPerSec / 1024)} KB/s`;
  }
  return `${Math.round(bytesPerSec)} B/s`;
}
