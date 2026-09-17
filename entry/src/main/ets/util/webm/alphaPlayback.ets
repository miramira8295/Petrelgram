// 透明贴纸帧序列的播放节律（纯函数，宿主上可测）。播放本体见
// pages/common/AlphaWebmStickerView。

// 拿不到时长时按 Telegram 视频贴纸规范的 30fps。
const ALPHA_DEFAULT_FPS: number = 30;
const ALPHA_MAX_FPS: number = 60;

// 这段帧序列自身的帧率——共享时钟（util/stickerFrameClock）按它请求刷新频率。
// 抽过帧的（frameStep 2/3）帧数少、时长不变，算出来就是 15/10，时钟跟着降，不白刷。
export function alphaClipFps(frameCount: number, durationMs: number): number {
  if (frameCount <= 0 || durationMs <= 0) {
    return ALPHA_DEFAULT_FPS;
  }
  const fps: number = Math.round(frameCount * 1000 / durationMs);
  return Math.min(ALPHA_MAX_FPS, Math.max(1, fps));
}

// 此刻该显示第几帧：最后一个呈现时刻 <= elapsedMs 的那一帧。
// 按时刻查表而不是"每拍前进一帧"：抽过帧的序列保留了原始时间戳，这样时长不变。
export function alphaFrameIndexAt(timesMs: number[], elapsedMs: number): number {
  let index: number = 0;
  for (let i = 0; i < timesMs.length; i++) {
    if (timesMs[i] <= elapsedMs) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}
