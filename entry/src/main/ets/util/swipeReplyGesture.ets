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

// 右滑进多选，与左滑回复镜像对称（都是正数，向右为正）。
//
// 数值刻意与左滑取同样的量级：两个方向的手感应当一致，用户不需要记两套距离。
//
// **为什么右滑不需要"已在多选态"的守卫**：多选态下 ChatPage 给整行挂的是
// HitTestMode.BLOCK_DESCENDANTS，气泡自己的手势根本收不到事件。守卫写在
// 气泡里反而是第二份真源。
export const SWIPE_SELECT_MAX: number = 56;
export const SWIPE_SELECT_TRIGGER: number = 40;

// 窗口左右两侧各留一条不响应左滑回复的带。
//
// 【为什么要有】系统的返回手势是从窗口左右边缘往内滑，而左滑回复挂的是
// distance 只有 8vp 的 PanGesture——边缘往内滑的那一下会被两边同时认领：
// 想返回的变成消息跟着走一段，想回复的有时把页面退了。群里反馈的误触就是这个。
//
// 【当前 36vp，2026-09-06 从 24 上调】第一版取 24（比系统边缘手势热区的
// 十几到二十 vp 略宽），真机试下来仍有误触，按反馈加大 50%。
//
// 代价是"从最边上开始的左滑回复"不再生效，而且这条带越宽，代价越明显——
// 36vp 在 360vp 宽的窗口上是左右各 10%，也就是**整行两侧各一成的区域不再响应
// 左滑回复**。若之后有人反馈"左滑变难触发了"，这就是原因，往回调即可。
//
// 这个数很容易调：还有误触就调大，反馈"左滑不好用了"就调小。
export const SWIPE_REPLY_EDGE_DEAD_ZONE: number = 36;

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
