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
//
// hostPages（F-6）：上面这段推导的前提是「**一个**页面的最坏回收潮」，而池是
// shared 的——平板分栏之下左右两栏各有一个 ChatPage 同时服务，两页并存时这个
// 上限是**低估**的，低估的后果正是要治的那条溢出。所以按当前活着的宿主页面数
// 放大。默认 1 让所有既有调用点（和单测）语义不变。
export function reuseBucketMaxCount(
  viewportRows: number, cachedCount: number, hostPages: number = 1): number {
  const rows: number = Math.max(0, Math.floor(viewportRows));
  const cached: number = Math.max(0, Math.floor(cachedCount));
  const pages: number = Math.max(1, Math.floor(hostPages));
  const raw: number = (rows + 2 * cached) * pages;
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

// ── 活着的分桶总数上限 + 最久未用淘汰（F-6）──────────────────────────────
//
// 【为什么每桶封顶还不够】
// reuseBucketMaxCount 给的是**每桶**上限（约 35）。但 REUSE_ID_LEVEL = 'medium'
// 的 rowReuseId 取值空间约 3000 个桶，**桶数本身没有上界**；而池是 shared 的，
// 只要 Navigation 栈上还压着任意一个会话页就不销毁。会话 A→B→C 逛下来，各自
// 的形状分桶全部累积——P5 之前的默认池是随页面销毁的，这条累积是新引入的。
// 官方使用限制原话：「只要拥有组件类的任何实例存在，池就会持续存在……回收的
// 组件可能会累积。使用 maxCount 来控制内存使用」。maxCount 是唯一的旋钮，
// 所以「淘汰一个桶」只能表达成「把它的 maxCount 写成 0」。
//
// 【为什么 24】
// medium 档的 12 个维度里，多数在一个会话内是常量（isGroup / isChannel /
// 大多数行的 isOutgoing 与 contentKind），一个会话真正出现的形状是个位数到
// 十几个。24 给两三个会话的余量；超过它的必然是逛过之后留下的旧会话形状，
// 正是要淘汰的那些。
export const REUSE_LIVE_BUCKET_LIMIT: number = 24;

// 框架默认值（官方：IReusableInfo.maxCount「默认值：100」）。把 maxCount 写回
// 它有一个额外作用：官方对 getReusableInfo 的定义是「为**每个 count 为正、或
// maxCount 非默认值**的 reuseId 各返回一条」，所以一个已清空的桶写回默认值之后
// 就**彻底退出枚举**，不再占我们这边的账。
export const REUSE_BUCKET_DEFAULT_MAX_COUNT: number = 100;

// 一次封顶要写的一笔。分成「算」和「写」两步，是为了让整段判断脱离设备单测。
export interface ReuseBucketWrite {
  info: IReusableInfo;
  maxCount: number;
}

export interface ReuseCapPlan {
  writes: ReuseBucketWrite[];
  // 新的「最近用过」表。不原地改传进来的那份，调用方拿返回值替换。
  lastSeen: Map<string, number>;
}

// 淘汰是**两趟**完成的，因为 maxCount 的清理是异步的（官方：「count 通常
// <= maxCount，清理异步发生，短时间内允许更大」）：
//   第 1 趟：选中最久未用的桶，maxCount ← 0（框架开始丢掉里面的实例）；
//   第 2 趟：看到 maxCount === 0 且 count === 0，说明清干净了，maxCount ← 100
//            （框架默认值）——桶就此退出枚举，也重新具备缓存能力，下次真用到
//            它时会重新出现、重新被封顶。
// 中间态（maxCount === 0 但 count > 0）什么都不写，等下一趟。
//
// 这样每个桶每趟最多写一次 maxCount，不会出现「写 0 又立刻写回 target」那种
// 会被异步清理合并掉的成对赋值。
export function planReuseBuckets(
  info: IReusableInfo[] | IReusableInfo | undefined,
  target: number,
  lastSeen: Map<string, number>,
  nowMs: number,
  limit: number
): ReuseCapPlan {
  const empty: ReuseCapPlan = { writes: [], lastSeen: new Map<string, number>() };
  if (info === undefined) {
    return empty;
  }
  const all: IReusableInfo[] = Array.isArray(info) ? info : [info];
  const writes: ReuseBucketWrite[] = [];
  const seen: Map<string, number> = new Map<string, number>();
  const keep: IReusableInfo[] = [];

  for (let i = 0; i < all.length; i++) {
    const one: IReusableInfo = all[i];
    if (one === undefined || one === null) {
      continue;
    }
    const id: string | undefined = one.reuseId;
    if (id === undefined) {
      // 「没有 reuseId」的那一条，官方说它恒在。它不参与桶数统计，照常封顶。
      if (one.maxCount !== target) {
        writes.push({ info: one, maxCount: target });
      }
      continue;
    }
    if (one.maxCount === 0) {
      // 已被淘汰。清干净了就交还默认值（并退出枚举），没清干净就再等一趟。
      if (one.count === 0) {
        writes.push({ info: one, maxCount: REUSE_BUCKET_DEFAULT_MAX_COUNT });
      }
      continue;
    }
    if (one.count > 0) {
      seen.set(id, nowMs);
    } else {
      const before: number | undefined = lastSeen.get(id);
      seen.set(id, before !== undefined ? before : 0);
    }
    keep.push(one);
  }

  // 超出上限的部分按「最近一次存过东西」的时间从旧到新淘汰。从未存过东西的
  // 桶（时间戳 0）排在最前面——它们本来就是空的，淘汰它们只是让账面干净。
  const capped: number = Math.max(0, Math.floor(limit));
  if (keep.length > capped) {
    keep.sort((a: IReusableInfo, b: IReusableInfo): number => {
      const ta: number = seen.get(a.reuseId ?? '') ?? 0;
      const tb: number = seen.get(b.reuseId ?? '') ?? 0;
      return ta - tb;
    });
  }
  const surviving: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < keep.length; i++) {
    const one: IReusableInfo = keep[i];
    const id: string = one.reuseId ?? '';
    if (keep.length > capped && i < keep.length - capped) {
      writes.push({ info: one, maxCount: 0 });
      continue;
    }
    surviving.set(id, seen.get(id) ?? 0);
    if (one.maxCount !== target) {
      writes.push({ info: one, maxCount: target });
    }
  }
  return { writes, lastSeen: surviving };
}

// 把上限套到所有活着的桶上，并把桶数压回上限之内。
//
// getReusableInfo(comp) 不带 reuseId 时，返回的是「每个 count 为正、或
// maxCount 非默认的 reuseId」各一条，外加一条 reuseId: undefined。
//
// 「最近用过」表挂在模块级而不是页面上：池是 shared 的，跨会话页共用同一份池，
// 账也必须是同一本。它的大小被 REUSE_LIVE_BUCKET_LIMIT 夹住（每趟只留存活的
// 那些），不会自己长大。
let bucketLastSeen: Map<string, number> = new Map<string, number>();

export function capReuseBuckets(
  pool: IReusePool,
  component: Function,
  target: number
): number {
  const plan: ReuseCapPlan = planReuseBuckets(
    pool.getReusableInfo(component), target, bucketLastSeen, Date.now(),
    REUSE_LIVE_BUCKET_LIMIT);
  bucketLastSeen = plan.lastSeen;
  for (let i = 0; i < plan.writes.length; i++) {
    plan.writes[i].info.maxCount = plan.writes[i].maxCount;
  }
  return plan.writes.length;
}

// ── 并存的宿主页面数（F-6 的另一半）──────────────────────────────────────
//
// shared 池同时服务所有活着的 ChatPage（平板分栏左右两栏、Navigation 栈上先后
// 压着的两份）。每桶上限的推导前提是「一个页面的最坏回收潮」，所以这里数一数
// 实际有几个，喂给 reuseBucketMaxCount 放大。
//
// 计数只增减，不持有任何页面引用；漏减一次的后果是上限估高（多留几个空实例），
// 方向和整段推导一致——估高只是白占一点内存，估低会把还要用的实例赶出池子。
let liveHostPages: number = 0;

export function retainMessageReuseHost(): void {
  liveHostPages++;
}

export function releaseMessageReuseHost(): void {
  liveHostPages = Math.max(0, liveHostPages - 1);
}

// 至少 1：capMessageReuseBuckets 是从页面里调的，那一刻本页必然活着。
export function messageReuseHostCount(): number {
  return Math.max(1, liveHostPages);
}
