// 消息行外壳（ReusableMessageBubble，@ReusableV2）的**全局复用池**接线。
//
// 这个模块做两件事，都是「默认复用池做不到、全局池才有」的那一半：
//   1. 判定当前设备走不走全局池（API 26 起）；
//   2. 给每个 reuseId 分桶算一个 maxCount 上限，并把它套到活着的桶上。
//
// 池本身在**哪里**声明，不在这里 —— 装饰器参数是编译期的，写在 ChatPage.ets
// 的池宿主组件上（见那边 ChatPagePoolHost 的注释）。这里只放能脱离 UI 单测
// 的纯逻辑，外加一层薄薄的运行时封装。
//
// ── 双路径 ────────────────────────────────────────────────────────────────
// 全局复用池是 API 26 起的能力，而本仓 compatibleSdkVersion 是 6.0.0(20)。
// 形状照抄 util/overlayMaterial.ets：一个 `xxxWinsAt(apiVersion)` 纯函数 +
// 一个模块级常量把设备版本喂进去，调用点全部在这个常量之后。
//
// 并且**绝不在模块级解引用任何 API 26 才有的东西**。overlayMaterial 的文件头
// 记着 1.3.6 就是这么挂的：把 uiMaterial.ImmersiveStyle 提成模块级常量之后，
// 低版本设备上模块一加载就抛，整个应用启动即崩。这里的对应物是池宿主组件
// 上那份装饰器配置：编译产物里它是**类字段初始化器**
// （`__reusePool__Internal = __ReusePool__Internal.create(...)`），只在构造
// 函数里跑，所以「类定义存在」不等于「碰过 API 26」——真正的闸门是那条
// `if (globalReusePoolAvailable())` 决定要不要 new 它。
//
// IReusePool / IReusableInfo 只出现在**类型位置**，编译期就被抹掉，不会在低
// 版本设备上产生一次运行时取值；下面碰 getReusableInfo / maxCount 的两个函数
// 都要求调用方先拿到一个 IReusePool，而那只有全局池在的时候才拿得到。

import { deviceInfo } from '@kit.BasicServicesKit';
import { IReusableInfo, IReusePool } from '@kit.ArkUI';

// 全局复用池的起始版本（官方《全局复用：集中化的组件回收与复用》：
// 「全局复用池功能从 API 版本 26.0.0 开始支持」）。
const GLOBAL_REUSE_POOL_API: number = 26;

// IReusableInfo.maxCount 的硬边界，官方注明「默认值：100，最大值：200，
// 最小值：0。赋值超出范围时，取最接近的最大值或最小值」。写在这里是为了让
// 推导函数自己夹住，而不是指望框架替我们兜。
export const REUSE_BUCKET_MAX_COUNT_CEILING: number = 200;

// 我们自己的下限。0 是合法值，但它的语义是「清空这个桶」——推导结果绝不该
// 落到那里去，否则一次算错就等于把复用整条关掉。给一个哪怕最小的视口也够用
// 的地板。
export const REUSE_BUCKET_MAX_COUNT_FLOOR: number = 8;

// 一行消息在竖直方向上能有多矮。取 34 不是拍脑袋：initialMessageStage.ets 的
// initialMessagePlaceholderHeight() 枚举了每种内容形状的估高，其中最矮的一支
// 是系统服务提示（contentType === 'system'，body = 34）。用**最矮**的那一支
// 去除视口高度，得到的是「一屏最多能塞下多少行」的上界，这正是封顶需要的方向：
// 上限估高了只是多留几个空实例，估低了会把还要用的实例赶出池子。
export const MIN_MESSAGE_ROW_HEIGHT_VP: number = 34;

// 与 overlayMaterial.materialWinsAt 同形：判定规则单独成纯函数，好让它在没有
// 设备的情况下被单测钉住。
export function globalReusePoolWinsAt(apiVersion: number): boolean {
  return apiVersion >= GLOBAL_REUSE_POOL_API;
}

// deviceInfo 是设备常量，官方建议读一次而不是每帧读。
const poolAvailable: boolean = globalReusePoolWinsAt(deviceInfo.sdkApiVersion);

export function globalReusePoolAvailable(): boolean {
  return poolAvailable;
}

// 一屏最多能容纳多少行。listHeightVp 传视口高度（用整屏高度也成立——那只是
// 更保守的上界），minRowHeightVp 传最矮那种行的高度。
export function messageRowViewportRows(listHeightVp: number, minRowHeightVp: number): number {
  if (!(listHeightVp > 0) || !(minRowHeightVp > 0)) {
    return 1;
  }
  return Math.max(1, Math.ceil(listHeightVp / minRowHeightVp));
}

// 每个 reuseId 分桶的缓存上限。
//
// 治的是官方点名的那条「缓存池溢出：短时间内产生大量待回收项，超出缓存容量
// → 旧实例被丢弃，新项仍需重建」。默认池根本没有这个旋钮；全局池的
// IReusableInfo.maxCount 有，默认 100。
//
// 为什么是 viewportRows + 2 * cachedCount，而不是别的数：
//   同一时刻**挂在树上**的行，最多就是「可视窗口的行」加「List 在可视区上下
//   各预建的 cachedCount 行」。一次 fling 最坏的情形是这一整批全部滚出去、
//   全部落进池子，而它们理论上可能全属于同一个 reuseId 分桶（比如整段都是
//   同一形状的纯文本）。所以这个数就是「一个桶在一次最坏回收潮里可能收到的
//   实例数」的上界。
//   - 比它小 ⇒ 潮水没退就开始丢实例，正是要治的那条溢出；
//   - 比它大 ⇒ 纯粹是空实例占内存，而 shared 池会跨会话累积（官方使用限制
//     原话：「回收的组件可能会累积。使用 maxCount 来控制内存使用」）。
//
// 注意这是**每桶**的上限，不是全池的。medium 档的 rowReuseId 取值空间很大，
// 但只有真正出现过的分桶才会被建出来，实际活着的桶是个位数量级。
export function reuseBucketMaxCount(viewportRows: number, cachedCount: number): number {
  const rows: number = Math.max(0, Math.floor(viewportRows));
  const cached: number = Math.max(0, Math.floor(cachedCount));
  const raw: number = rows + 2 * cached;
  if (raw < REUSE_BUCKET_MAX_COUNT_FLOOR) {
    return REUSE_BUCKET_MAX_COUNT_FLOOR;
  }
  if (raw > REUSE_BUCKET_MAX_COUNT_CEILING) {
    return REUSE_BUCKET_MAX_COUNT_CEILING;
  }
  return raw;
}

// 从 getReusableInfo() 的返回值里挑出「需要改」的那些桶。
//
// 单独成函数是因为返回值有三种形状（单个 / 数组 / undefined），而这段判断是
// 全局池接线里唯一容易写错、又完全能脱离设备验证的部分。
//
// 只回传 maxCount 与目标不一致的桶：每次滚动停下都无条件写一遍 maxCount 是
// 白付，而且给 maxCount 赋值会触发框架的异步清理。
export function bucketsNeedingCap(
  info: IReusableInfo[] | IReusableInfo | undefined,
  target: number
): IReusableInfo[] {
  if (info === undefined) {
    return [];
  }
  const all: IReusableInfo[] = Array.isArray(info) ? info : [info];
  const out: IReusableInfo[] = [];
  for (let i = 0; i < all.length; i++) {
    const one: IReusableInfo = all[i];
    if (one !== undefined && one !== null && one.maxCount !== target) {
      out.push(one);
    }
  }
  return out;
}

// 把上限套到所有活着的桶上。
//
// getReusableInfo(comp) 不带 reuseId 时，返回的是「每个 count 为正、或
// maxCount 非默认的 reuseId」各一条，外加一条 reuseId: undefined。也就是说
// 它枚举的正好是**真的存了东西的桶**——没被用过的分桶不占内存，也就不需要封顶。
export function capReuseBuckets(
  pool: IReusePool,
  component: Function,
  target: number
): number {
  const pending: IReusableInfo[] = bucketsNeedingCap(pool.getReusableInfo(component), target);
  for (let i = 0; i < pending.length; i++) {
    pending[i].maxCount = target;
  }
  return pending.length;
}
