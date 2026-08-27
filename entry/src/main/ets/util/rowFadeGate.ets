// 首屏逐条淡入的放行闸。
//
// ChatPage 的 Repeat 行包装上挂着一条 .animation()，负责首屏那一波逐条淡入
// （opacity / translate / scale 从 masked、initialDeferred 的值滑到常态）。
// 问题在于它是**常驻**修饰器：它前置的三个属性每次 rerender 都重新求值
// （translate / scale 还是新的对象字面量），于是任何一次 ChatPage 整体
// rerender 都会开出一个 90ms 的隐式动画上下文，把那一帧本该瞬间生效的布局
// 变化拉成 90ms 的滑动——用户看到的就是「列表上下抖动」而不是瞬跳，滚动
// 位移也被反复变化的布局吃掉。
//
// 真机 trace：duration:90 全程 71 次 / 495.2ms，最慢的三帧（96–103ms）全部是
// CustomNodeUpdate ChatPage → ExecuteRerender → JSAnimation → duration:90 →
// FlushLayoutTask → Measure[List] 30–37ms，且**全部落在滑动之外**。
//
// 办法：给这条动画加一个时间戳闩。masked 或还有行处在 initialDeferred 期间
// 持续续期；揭示之后再放行一个窗口，让那一波淡入跑完；窗口之外 duration 和
// delay 都给 0，常驻上下文随之失效（与既有的 chatTgsScrollActive 同一个手法）。
//
// 窗口取 420ms：一波淡入最长是 stagger 上限（7 × 14ms = 98ms）加一段淡入
// （90ms），两者都还要乘上「动效强度」的倍率，420ms 留了足够的余量；而它
// 只需要在 opacity 翻转的那一帧是开着的，动画一旦起跑就不受闩影响。
export const INITIAL_ROW_FADE_WINDOW_MS: number = 420;

// masked 期间恒放行——续期由调用方负责（它才拿得到 this）。
// armedAt 为 0 表示这条聊天还没有过任何一次首屏揭示，一律不放行。
export function rowFadeAnimationActive(masked: boolean, now: number, armedAt: number): boolean {
  if (masked) {
    return true;
  }
  if (armedAt <= 0) {
    return false;
  }
  return now - armedAt <= INITIAL_ROW_FADE_WINDOW_MS;
}

// ── 从「常驻 .animation() + duration 0」改成「一次性 transition」──────────
//
// 上面那道闩本来是给消息行上那条常驻 `.animation()` 用的：窗口外把 duration
// 和 delay 都给 0，让它"看起来"失效。真机 trace 说这不够——`JSAnimation
// duration:0` 一直在。只要修饰器还挂在那儿，每一次普通 rerender 都会进一次
// 动画上下文；给 0 省掉的只是动画本身，省不掉上下文。本会话在气泡上验过两次
// （02f50cf / 3193982 / 8d1bfb1：换位置、给 0 都挡不住，摘掉修饰器才有效）。
//
// 所以行上换成 `.transition()`。官方对它的触发条件只列了两条（API 参考"组件内
// 转场 (transition)"）：
//   1. 组件插入或删除时（if 条件改变、ForEach 新增删除组件）；
//   2. 组件 visibility 属性在可见与不可见之间改变时。
// 一次普通的属性更新两条都不沾，因此不会为 rerender 建动画上下文——这正是这
// 一改要的性质。
//
// 代价是"关掉"的写法变了：不能再靠把 duration 给 0，得整个换成
// TransitionEffect.IDENTITY，否则滚动中新建的每一行都会淡入一次（官方 FAQ
// faqs-arkui-1136 记的就是这个现象：LazyForEach 的列表上滑也触发 transition）。
export interface RowFadeTransition {
  // false = 该挂 TransitionEffect.IDENTITY，一点效果都不要。
  enabled: boolean;
  duration: number;
  delay: number;
}

// scrollActive：chatTgsScrollActive，滑动中一律不做入场动画（原判据照搬）。
// armed：rowFadeAnimationActive 的结果（首屏窗口内）。
export function rowFadeTransition(
  scrollActive: boolean, armed: boolean, duration: number, delay: number
): RowFadeTransition {
  if (scrollActive || !armed) {
    return { enabled: false, duration: 0, delay: 0 };
  }
  return { enabled: true, duration: duration, delay: delay };
}
