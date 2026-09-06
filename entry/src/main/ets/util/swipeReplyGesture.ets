// 左滑回复的几何常量与边缘判据。
//
// **为什么是共用文件**：这套手势有两个实现——MessageBubble（媒体/复杂消息）
// 与 LightweightPlainTextBubble（纯文本，聊天里最常见的一类）。两边原本各自
// 定义了一份 SWIPE_REPLY_MAX / SWIPE_REPLY_TRIGGER，加边缘死区时就要出现第三、
// 第四份。这类"两处必须一致"的重复迟早漂移，而漂移的后果是静默的：
// 一种气泡有死区、另一种没有，用户只会觉得"有时候误触有时候不误触"。

// 左滑最多能拖多远，以及触发回复的阈值（都是负数，向左为负）。
export const SWIPE_REPLY_MAX: number = -56;
export const SWIPE_REPLY_TRIGGER: number = -40;

// 窗口左右两侧各留一条不响应左滑回复的带。
//
// 【为什么要有】系统的返回手势是从窗口左右边缘往内滑，而左滑回复挂的是
// distance 只有 8vp 的 PanGesture——边缘往内滑的那一下会被两边同时认领：
// 想返回的变成消息跟着走一段，想回复的有时把页面退了。群里反馈的误触就是这个。
//
// 24vp 的依据：系统边缘手势的热区通常在十几到二十 vp 量级，留一条比它略宽的带，
// 让边缘起手的滑动干净地归系统。代价是"从最边上开始的左滑回复"不再生效——
// 但那本来就是最容易和返回冲突的起手方式，让给系统是对的。
//
// 这个数很容易调：还有误触就调大，反馈"左滑不好用了"就调小。
export const SWIPE_REPLY_EDGE_DEAD_ZONE: number = 24;

// 这一次按下是不是落在窗口边缘的死区里。
//
// 【必须在 TouchType.Down 那一刻判一次，整个手势期间沿用】手指从边缘滑进来
// 之后 windowX 就离开死区了，逐帧重判会让手势滑到一半突然"复活"。
//
// 用窗口宽而不是物理屏宽：分栏/自由窗口下要挡的是**窗口**边缘。
// 调用方传的是 chatEnv.screenWidthVp，而它存的正是 windowRect.width
// （见 EntryAbility 的写入点）。
//
// windowWidth <= 0 时只挡左边：宽度还没就位（首帧）时宁可少挡，
// 也不要用一个错的宽度去挡右边——那会把整行都算成边缘。
export function isEdgeSwipeStart(x: number, windowWidth: number): boolean {
  if (x <= SWIPE_REPLY_EDGE_DEAD_ZONE) {
    return true;
  }
  return windowWidth > 0 && x >= windowWidth - SWIPE_REPLY_EDGE_DEAD_ZONE;
}
