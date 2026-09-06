// 全屏播放引擎的失败分流判据。
//
// **背景。** 全屏播放有两套引擎（见 pages/chat/VideoPlayerHost）：系统 AVPlayer
// 与 ijkplayer。AVPlayer 默认，因为只有它有 HDR 通路（PlaybackStrategy.preferredHdr）；
// ijkplayer 靠 FFmpeg 吃格式广，但渲染层没有 HDR。
//
// 两者是互补的，可是分流原本是**静态**的：一个设置开关，AVPlayer 解不了的片源
// 就直接失败，用户得自己去设置里换引擎——而他根本不知道有这么个开关。
//
// **这个文件解决的是"错误码该怎么分类"。** 三档：
//   · engine-unsupported —— 这台设备的 AVPlayer 就是解不了这个片源。重试多少次
//     结果都一样，应当**立刻换引擎**，不要浪费用户的时间在"重连中…"上。
//   · transient        —— IO / 网络 / 超时。原有的退避重试是对的，保持不变。
//   · fatal            —— 其余（无权限、参数错、服务挂了）。重试无意义，也换不了
//     引擎能解决，直接报错。
//
// **为什么单独成文件而不是写在组件的 catch 里。** 判据是"哪些码算引擎不行"，
// 这是一条会随系统版本增补的清单，且它是**可测的纯函数**；写在组件里就只能靠
// 肉眼 review，而这一簇的失败恰恰是"用户看到播放失败"这种没有本地手段能发现的。
//
// 错误码取自 SDK 的 media.AVErrorCode（@ohos.multimedia.media.d.ts:1422-1600）。
// 这里**用字面量而不是 import 那个枚举**：枚举是 ArkTS 的运行时对象，而本文件
// 要能被单测直接 import（测试环境没有 media 模块的原生实现）。每个字面量旁边
// 都标了枚举名，改的时候对着 SDK 核。

// AVERR_UNSUPPORT_CAPABILITY：能力不支持。
export const AV_ERR_UNSUPPORT_CAPABILITY: number = 801;
// AVERR_UNSUPPORT_FORMAT：格式不支持——最常见的那一个。
export const AV_ERR_UNSUPPORT_FORMAT: number = 5400106;

// AVERR_IO：5400103；AVERR_TIMEOUT：5400104。
const AV_ERR_IO: number = 5400103;
const AV_ERR_TIMEOUT: number = 5400104;
// 5411001..5411013 整段都是 IO 子类（HOST_NOT_FOUND / CONNECTION_TIMEOUT /
// NETWORK_ABNORMAL / NETWORK_UNAVAILABLE / NO_PERMISSION / REQUEST_DENIED /
// RESOURCE_NOT_FOUND / SSL_* / UNSUPPORTED_REQUEST）。按段判而不是逐个列：
// 这一段是官方划给 IO 的号段，新增的子类天然也该走重试。
const AV_ERR_IO_RANGE_START: number = 5411000;
const AV_ERR_IO_RANGE_END: number = 5411999;

export type VideoErrorKind = 'engine-unsupported' | 'transient' | 'fatal';

// **这台设备的 AVPlayer 解不了这个片源** —— 换引擎，别重试。
//
// 注意 801 的含义比"格式不支持"宽（分辨率超出、profile 不支持、并发实例用尽都
// 可能报它）。其中"并发实例用尽"理论上是暂时的，但在全屏播放这个场景里同一时刻
// 只会有一个播放器，撞上它更可能是设备能力问题——归到换引擎这一档，代价是最多
// 白切一次引擎，而 ijk 那边多半也能放出来。
export function isEngineUnsupportedError(code: number): boolean {
  return code === AV_ERR_UNSUPPORT_FORMAT || code === AV_ERR_UNSUPPORT_CAPABILITY;
}

// **暂时性失败** —— 保持原有的退避重试。
export function isTransientError(code: number): boolean {
  if (code === AV_ERR_IO || code === AV_ERR_TIMEOUT) {
    return true;
  }
  return code >= AV_ERR_IO_RANGE_START && code <= AV_ERR_IO_RANGE_END;
}

// 三档分类。组件只调这一个。
export function classifyVideoError(code: number): VideoErrorKind {
  if (isEngineUnsupportedError(code)) {
    return 'engine-unsupported';
  }
  if (isTransientError(code)) {
    return 'transient';
  }
  return 'fatal';
}

// ── 静默卡死：报不出错的那一类"解不了" ──────────────────────────────────
//
// 【它修的是什么】用户报「Pad 上自己发的视频点开是黑屏，也不转圈」。
// 上面那套分类是**基于错误码**的，前提是 AVPlayer 会报错。但还有一类失败它
// 不报：prepare 成功、状态机走到 playing、然后一帧也解不出来。AvVideoPlayer
// 在 'prepared' 里就无条件把封面撤掉（showFirstFrameOnPrepare 的前提是真有
// 首帧），于是屏幕上只剩一张空 Surface——纯黑。
//
// 【为什么连圈都不转】本地文件那条路 bufferedPercent 直接置 100（没有下载
// 阶段），状态卡片又因为 isPrepared 已经为真而不再出现。三件事叠在一起，
// 用户看到的就是一块什么都没有的黑。
//
// 【判据为什么是这三个】
//   playing             —— 播放器自己说在播（暂停/实况静止态不该被误判）
//   bufferedPercent≥100 —— 数据是齐的。**这一条把网络卡顿整个排除掉**：
//                          缓冲不足导致的停顿有自己的重试路径，不该换引擎。
//   位置多久没动         —— 数据齐、说在播、位置却不走，只剩"解码器没出帧"
//                          这一种解释。
// 三条同时成立才判定，任何一条不满足都不动——宁可漏判（用户仍看到黑屏，与
// 改动前一样），也不能误判（把本来能放的视频踢去 ijk）。
export const STALL_FALLBACK_MS: number = 4000;

export function playbackStalled(
  playing: boolean, bufferedPercent: number, msSinceProgress: number
): boolean {
  return playing && bufferedPercent >= 100 && msSinceProgress >= STALL_FALLBACK_MS;
}

// 该不该走自动重试。**只有 transient 才重试**——这是本次改动的实质：
// 原来对所有错误码一视同仁地重试，于是"格式不支持"这种确定性失败也要先转几轮
// "重连中…"才报错，比直接失败更难受。
export function shouldAutoRetry(code: number, attemptsDone: number, maxAttempts: number): boolean {
  return classifyVideoError(code) === 'transient' && attemptsDone < maxAttempts;
}
