// 语音/音乐气泡的播放进度：比例 + 秒数。
//
// 这两件事**永远成对写**（两个组件的每一处写入都是相邻两行：进度回调、拖动、
// 播放结束、复位）。拆成两个 @Local 时，每次进度回调要发两次通知、跑两遍依赖
// 遍历；合成一个快照后是一次赋值、一次通知，且写入前先比较，值没变就整条短路。
//
// 【为什么只合并这两个】同一组件里的 playbackStatus / dragging / finished / speed
// 与进度是**不同时机**变的（拖动中进度不动、loading 时状态变而进度不变），
// 合并进去只会互相误伤——这也是本仓 09-03 那条「合并省的是逐参数登记，赔的是
// 粗粒度失效」在 @Local 上的同一结论。
export interface AudioClock {
  progress: number;
  elapsed: number;
}

// 复位用的初值。同一个模块常量 = 同一个引用：复位到它时若已经是它，
// @Local 的 `===` 比较直接短路。
export const IDLE_AUDIO_CLOCK: AudioClock = { progress: 0, elapsed: 0 };
