// 分页落地后怎么把锚点行按回原位：一次 scrollBy，还是全量 scrollToIndex。
//
// 【为什么要分两级】
// 原来无论如何都走 `scrollToIndex(idx, false, START)` 再补一次 scrollBy。
// scrollToIndex 会让 List 从指定下标开始重新测量——真机 Frame trace 里
// `ScrollToIndex(index=9)` 出现 3 次，对应录制中最大的 3 个尖峰。而分页复位的
// 绝大多数情形下，锚点行**根本没离开可见区**：maintainVisibleContentPosition
// 已经把它按住了个大概，我们要补的只是几个 vp 的残差。这种情况下把新旧 y 一
// 减、走一次 scrollBy 就够，完全不用惊动重测。
//
// 只有锚点行真的滑出了显示区（getItemRect 取不到有效矩形）才回退到旧路径。
//
// 【getItemRect 对不在显示区的下标返回什么】
// 出处：HarmonyOS 文档 FAQ/UI框架/UI界面/判断滚动与滑动容器组件的子组件是否可见
// （faqs-arkui-572）——"其参数 index 必须是当前显示区域显示的子组件的索引值，
// 否则视为非法值。**非法值返回的大小和位置均为 0**。"同篇给的判法是"判断其
// 属性 x、y、width、height 的值是否均不为 0，否则不可见"。
//
// 这里不照抄"四个都不为 0"：正常停在视口顶端的那一行 y 就是 0，x 在单列列表
// 里恒为 0，照抄会把它误判成不可见。取 width/height 两维即可——一个真实渲染
// 出来的消息行不可能是零宽零高。
//
// SDK 声明（component/scroll.d.ts, getItemRect）另标了 401 / 100004 两个
// BusinessError，所以调用点仍要 try/catch；抓到异常时按"非法"处理，也就是传
// 一份全 0 的矩形进来。ChatPage 里既有的 flashAtIndex / syncFlashRect 就是这
// 个写法（try/catch + height <= 0 视为无效），这里保持一致。

export const ANCHOR_RESTORE_DELTA: string = 'delta';
export const ANCHOR_RESTORE_FALLBACK: string = 'fallback';

// getItemRect 返回值里我们用得上的三维。ChatPage 把 RectResult 摘成这个结构再
// 传进来，纯函数因此不依赖 ArkUI 类型，单测能直接跑。
export interface AnchorRectSnapshot {
  width: number;
  height: number;
  y: number;
}

// 全 0 = 框架对非法下标的返回值，也是调用点抓到异常时该传的东西。
export const INVALID_ANCHOR_RECT: AnchorRectSnapshot = { width: 0, height: 0, y: 0 };

export interface AnchorRestorePlan {
  // ANCHOR_RESTORE_DELTA：只 scrollBy(0, dy)，不碰 scrollToIndex。
  // ANCHOR_RESTORE_FALLBACK：走旧路径 scrollToIndex(START) + scrollBy(0, dy)。
  mode: string;
  // 要交给 scrollBy 的纵向位移，单位 vp。dy 为 0 表示这一步可以整个省掉。
  dy: number;
}

export interface PrependAnchorCaptureInput {
  didInitialScroll: boolean;
  anchorIndexFresh: boolean;
  olderPageGrowth: boolean;
}

// API 20+ List normally preserves Repeat.virtualScroll insertions outside the
// visible area, but media albums are a counterexample on current devices. An
// older page can keep the old first row's key unchanged, or merge members into
// that album so its old identity disappears altogether; Repeat then relays out
// several very tall rows and moves the visible window. Therefore the reliable
// signal is the store transaction itself: an `older` publication that grew the
// raw message window. The caller preserves movement made after capture
// separately and subtracts only the layout/data displacement.
export function shouldCapturePrependAnchor(input: PrependAnchorCaptureInput): boolean {
  return input.didInitialScroll && input.anchorIndexFresh && input.olderPageGrowth;
}

// onDidScroll/onWillScroll report a positive offset when content moves upward.
// The same row's y therefore decreases by that offset. Anchor correction runs
// asynchronously after a page publication, so its target must include every
// user-originated scroll frame that happened since the row was sampled.
export function anchorYAfterUserScroll(
  capturedY: number, userOffsetAtCapture: number, userOffsetNow: number
): number {
  return capturedY - (userOffsetNow - userOffsetAtCapture);
}

// 小于半个 vp 的残差不值得发一次滚动指令：它在屏幕上不可见，却会白白走一遍
// 滚动管线（并可能顺带触发一轮 onDidScroll）。既有代码里 `itemY < -0.5` 用的
// 也是这个阈值。
const ANCHOR_RESTORE_EPSILON: number = 0.5;

// rect：**发布并完成一次布局之后**重新量到的锚点行矩形。
// itemY：调用方在**发布之前**记下的、同一行相对列表的 y。
//
// 【dy 的符号】
// scrollBy(0, dy) 的 dy 为正 = 向内容末尾方向滚 = 内容整体上移 = 行的 y 变小。
// 目标是把行从当前的 rect.y 挪回 itemY，于是
//
//     itemY = rect.y - dy   ⇒   dy = rect.y - itemY
//
// 这不是猜的：旧路径 `scrollToIndex(idx, false, START)` 之后行的 y 恰好是 0，
// 紧跟的那句是 `if (itemY < -0.5) scrollBy(0, -itemY)`——把 rect.y = 0 代进上
// 式正好得到 dy = -itemY，与旧代码逐字吻合。所以 delta 这一支在 rect.y = 0 时
// 退化成旧行为，符号方向由既有的、真机验证过的代码背书。
export function planAnchorRestore(rect: AnchorRectSnapshot, itemY: number): AnchorRestorePlan {
  if (rect.width > 0 && rect.height > 0) {
    const dy: number = rect.y - itemY;
    return {
      mode: ANCHOR_RESTORE_DELTA,
      dy: Math.abs(dy) < ANCHOR_RESTORE_EPSILON ? 0 : dy
    };
  }
  // 行已经不在显示区：没有"新 y"可减，只能让 List 重新定位到它。scrollToIndex
  // (START) 之后 rect.y = 0，代进上式就是 dy = -itemY。
  //
  // 这里**逐字保留**旧代码的那道 `itemY < -0.5` 单边判断：只补"行被卷到视口
  // 顶上方"这一侧。itemY 为正（行的顶边落在视口顶下方）时旧代码什么都不做，
  // 回退路径不是这次要改的东西，不顺手改它的行为。delta 那一支才需要双向，
  // 因为它减的是两个都可能为正的实测 y。
  if (itemY < -ANCHOR_RESTORE_EPSILON) {
    return { mode: ANCHOR_RESTORE_FALLBACK, dy: -itemY };
  }
  return { mode: ANCHOR_RESTORE_FALLBACK, dy: 0 };
}

// 量不到锚点时，隔一帧再量几次。
//
// 【为什么必须重试——2026-08-29 真机日志里的天然 A/B】
// 同一台设备、同一个人、同一份导出日志跨了两个构建，分界干净（前半只有
// retry/fallback，后半只有 give-up）：
//   · 有重试的前半（ca5bde9）：60 次复位 = attempt=0 量到 47 + 重试后量到 11
//     + 兜底 2，**一次都没有落空**；
//   · 只量一次的后半（ecce2fd）：31 次复位 = 量到 9 + **放弃 22，占 71%**。
// 用户正是在后半段报「刚点进新频道动一动就跳了好几下，进来看的消息也找不到
// 了」：一次向上翻页连着灌进 6 页 30 行，六次前插的补偿**全部放弃**。
//
// ecce2fd 当初的依据是另一场会话「attempt=0 成功 83/90」，据此认定「能量到时
// 没用、量不到时有害」。但那批样本来自较轻的场景；本场后半 attempt=0 只成功
// 9/31（29%）。媒体重的频道排版更慢，setTimeout(0) 那一刻新快照往往还没排完
// 版，getItemRect 必然返回全 0——这正是 ca5bde9 当初查明的现象。所以「只量
// 一次」在这类频道里等于「大多数时候什么都不补」。
//
// 【兜底不恢复】ca5bde9 已证实 scrollToIndex(START) 按 List 顶端对齐、没算
// contentStartOffset 那段顶栏留白，会把视口整体往下推——那才是真正把视口挪走
// 的动作。它在前半段也只占 2/60。所以这里只恢复重试，重试用尽仍量不到就放弃。
//
// 【已知残留】重试量到的 dy 混着这一帧里发生的一切，前半段出现过 dy=1396
// （dOff=3812）这种大额修正。相比「71% 的前插零补偿」这是更小的害，但不是没有
// 代价。真正的解法是拿到「排版完成」的回调（inspector 的 layout 观察者）在那
// 一刻量一次，不必猜帧——留作后续。
export const ANCHOR_RESTORE_ATTEMPTS: number = 3;
export const ANCHOR_RESTORE_RETRY_MS: number = 16;

// 量到了（delta）就不再重试；量不到且还有次数就再来一次。
export function shouldRetryAnchorRestore(mode: string, attempt: number): boolean {
  return mode !== ANCHOR_RESTORE_DELTA && attempt + 1 < ANCHOR_RESTORE_ATTEMPTS;
}
