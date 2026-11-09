// 全屏播放器的竖拖手势：左半屏调亮度、右半屏调音量。
//
// 【为什么是纯函数】两套播放引擎并存（ijk 的 StreamingVideoPlayer 和系统
// AVPlayer 的 AvVideoPlayer），手感必须一模一样——和 util/playerChrome 同一个
// 理由。判据错了很难在真机上看出来是哪一条错（"往上滑越滑越暗"这类），
// 所以逐条钉了单测。
//
// 【竖屏横屏都要成立】这里一律拿**传进来的实际宽高**算，不读窗口、不判方向。
// 转屏后调用方给的是新的宽高，比例自然跟着变，不需要任何方向分支。

// 【横拖调进度为什么没做】查看器里左右滑是**多媒体消息之间翻页**，同一块
// surface 上两件事必冲突（用户 2026-09-09："左滑和右滑对多媒体消息会有冲突，
// 去掉吧"）。所以手势层用 PanDirection.Vertical，横向手势压根不被认领，
// 翻页原样保留。进度仍然靠控制条的进度条和双击 ±15s。
export const GESTURE_ZONE_LEFT: string = 'left';    // 亮度
export const GESTURE_ZONE_RIGHT: string = 'right';  // 音量

// 认作"拖动"的最小位移（vp）。低于它不认——否则双击的两次落点之间那点抖动
// 会被当成拖动，双击 ±15s 就废了。
export const GESTURE_LOCK_VP: number = 12;


// 竖拖走完 0→1 需要划过的屏幕高度比例。满屏 1.0 太灵敏，0.6 的手感接近
// 系统播放器。
export const LEVEL_TRAVEL_RATIO: number = 0.6;


// 左右分区按**起手点**，不是当前点：手指从左半屏拖到右半屏，调的仍然是亮度。
// 正中间归右（音量），与双击 ±15s 的左右分区保持一致。
export function gestureZoneOf(startX: number, width: number): string {
  return startX < width / 2 ? GESTURE_ZONE_LEFT : GESTURE_ZONE_RIGHT;
}


// 竖拖 → 新的档位（0..1）。**向上是加**：屏幕坐标 y 向下为正，所以 dy 取负号。
export function levelAfterDrag(startLevel: number, dy: number, height: number): number {
  if (height <= 0) {
    return Math.max(0, Math.min(1, startLevel));
  }
  const travel: number = height * LEVEL_TRAVEL_RATIO;
  const next: number = startLevel - dy / travel;
  return Math.max(0, Math.min(1, next));
}
