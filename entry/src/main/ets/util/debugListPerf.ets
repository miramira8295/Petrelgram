// 调试项：聊天详情页 List 的 cachedCount 档位。
//
// 【为什么存在】P6 要在真机上对 cachedCount 做 4 / 6 / 8 三档 A/B。在这个开关
// 之前，换一档意味着改常量 → 编译 → 装机 → 应用回到会话列表 → 重新进会话 →
// 抓取，一轮十几分钟，而且装机后应用停在会话列表（不是原来那个会话），很容易
// 把"重新进会话"这一步漏掉、结果测的是列表。这个开关把这一整圈换成点两下。
//
// 【它不改变现状】默认值恒为 6，与写死常量的时期逐字节等价。这不是一个行为
// 开关，是一个让测量变便宜的开关；标定结束后要么把结论写死回常量、要么连同
// 这个文件一起删掉（删除清单见文件末尾）。
//
// 【键名前缀】debug 前缀是刻意的：AppSettings 里其余的键都是用户设置，这一个
// 不是，它不出现在任何面向用户的设置页，只出现在设置 → 日志与诊断的调试角落。

// AppStorage / Preferences 的键。debug 前缀表明它不是用户设置。
export const KEY_DEBUG_LIST_CACHED: string = 'debugListCachedCount';

// 默认档位。2026-09-10 由 6 抬到 8（档位表里已验证过的上限）。
//
// 【为什么这次可以抬】原来的理由是"cachedCount 越大 predict 要提前建的行越多"，
// 那时向上翻页每一页都要手动补位，预建得多反而把成本堆在同一帧。现在前插已经
// 是纯插入（见 util/collapseAlbums 的 RunHeadHints），发布也不再等松手——预建
// 的行越多，惯性途中需要现建的就越少，方向反过来了。
// 再往上（10+）要先放宽 LIST_CACHED_COUNT_OPTIONS，且未经标定，暂不做。
//
// 这个值为什么是静态的（原注释留在 ChatPage.ets 顶部成了孤儿，2026-09-05 瘦身
// 批 B1 搬到这里，因为值住在这一行）：固定预建两行，不再用状态变量从 1 延迟涨
// 到 4——后者会在进页面约 450ms 后让整个可见消息区重跑 build，Insight 里对应两次
// 约 25ms 的帧峰值。A short-message viewport commonly contains 10-16 rows;
// HarmonyOS long-list guidance recommends keeping roughly half a viewport ready.
// Keep this static so changing the value never invalidates every visible row.
// 2026-09-20 曾降到 4，**2026-09-21 改回 8。别再降**。
//
// 【当初为什么降】相册一行 6–9 张位图，RGBA_8888 下每张 625KB，8 档要 120–180 张，
// 而图片预算只有 48MiB ≈ 80 张——可视窗口本身就超预算。
//
// 【为什么这个理由不成立了】同一轮里相册格改成了 RGB_565（625KB → 312KB，见
// pixelCache.PixelRequest.opaque），图片预算又从 48MiB 抬到 68MiB（向贴纸缓存
// 借闲置额度，见 util/nativePixelArbiter）。容量从 ~80 格变成 ~223 格，8 档要的
// 120–180 张早就装得下。
//
// 【为什么必须改回来 —— 两份 Frame 录制对照】降到 4 之后行重建明显变多，按秒归一化：
//                       predict 建项      BuildRecycle 行重建     卡顿率
//   09-20 19:17（8 档）   49.1/s (33% 墙钟)   39.9/s              19.6%
//   09-21 10:13（4 档）   61.2/s (43% 墙钟)   53.9/s               9.7%
// 卡顿率减半是 565 / 共享预算 / 垫底色带来的，和这个数无关；而两个 churn 指标
// 同向变差 25%–35%，只有这一处改动能解释。窗口越小，行掉出去再回来的次数越多，
// 每回来一次就重走一遍取图——那段空窗就是用户报的"相册图片闪一下"。
//
// 2026-09-10 由 6 抬到 8 的原始理由仍然成立：前插改成纯插入、发布不再等松手之后，
// 预建得多意味着惯性途中现建得少。
//
// 调试项仍然提供 4/6/8 三档（LIST_CACHED_COUNT_OPTIONS），要试别的档从那里走。
export const LIST_CACHED_COUNT_DEFAULT: number = 8;

// 可选档位。A/B 的三档；顺序即界面上从左到右的顺序。
//
// 为什么下限是 4 而不是 2：P2 的 10:43 真机 trace 里，两行缓存被一次 90Hz
// 快速 fling 直接吃穿。4 是"还值得一测"的下界。
// 为什么上限是 8：cachedCount 越大，LazyForEach/Repeat 的预加载（trace 里的
// predict）要提前建的行越多 —— 而 P6 要治的正是 predict 占掉的那 1759ms。
// 8 已经是一屏短消息（10~16 行）的半屏往上，再大只是把重建成本前移。
export const LIST_CACHED_COUNT_OPTIONS: number[] = [4, 6, 8];

// 【别再试：把 Repeat 模板缓存调大治不了 churn —— 2026-09-21 实测】
//
// 曾经把五个 `.template(..., {cachedCount})` 从 8/10/8/10/8 统一抬到
// LIST_CACHED_COUNT_DEFAULT*2+6 = 22，理由是 trace 里三个数几乎相等、像是
// 「Repeat.IdleTask 拆 → 下一帧重建」的乒乓：
//     IdleTask 635 / RemoveNode 652 / CREATED_NEW_NODE 655（10.25s）
// 改完再录一份，四项指标**纹丝不动**（按秒归一化）：
//     predict 61.4→61.0 | BuildRecycle 58.3→56.4 | 新建 63.9→62.4 | 拆 63.6→61.9
//
// 原因：`.virtualScroll({ reusable: false })` 下 Repeat **不维护复用池**，而
// template 的 cachedCount 管的正是那个池的大小——参数被忽略。这 ~60 次/秒的
// 拆建是 reusable:false 的固有行为（基线 2026-09-20 也有 51.8 次/秒），不是
// 配置错误。要动它只能动 reusable，而那是承重墙（见 ChatPage 那段长注释：
// 开 true 会让消息重复回来）。

// 边界校验。落盘的值、AppStorage 里的值、以及未来可能出现的旧版本残留值都要
// 过这一关：不在候选档位里的一律当默认档，绝不把一个野值交给 List。
//
// 刻意**不**做"就近取整到最近的档位"：那会把一个明显错误的值悄悄变成一个看起来
// 合理的值，标定时读到的就是假数据。宁可回默认档，因为默认档是可辨认的。
export function normalizeListCachedCount(value: number | undefined | null): number {
  if (value === undefined || value === null) {
    return LIST_CACHED_COUNT_DEFAULT;
  }
  if (!Number.isFinite(value)) {
    return LIST_CACHED_COUNT_DEFAULT;
  }
  return LIST_CACHED_COUNT_OPTIONS.indexOf(value) >= 0 ? value : LIST_CACHED_COUNT_DEFAULT;
}

// 非组件代码的读取口（组件用 @StorageProp 订阅，才能在切档时重新求值）。
export function listCachedCount(): number {
  return normalizeListCachedCount(AppStorage.get<number>(KEY_DEBUG_LIST_CACHED));
}

// ── 删除清单（标定结束后） ────────────────────────────────────────────
// 1. 本文件；
// 2. AppSettings.ets 里 KEY_DEBUG_LIST_CACHED 的 import / 初始化两处；
// 3. ChatPage.ets：ChatPageChrome 的 @StorageProp、ChatPage 的 @Param
//    listCachedCount、以及三处 this.listCachedCount 改回常量；
// 4. DiagnosticsPage.ets 里的 listCachedCard() 及其 import；
// 5. 资源里的 diag_list_cached / diag_list_cached_sub 两个键（base + 19 语言）。

