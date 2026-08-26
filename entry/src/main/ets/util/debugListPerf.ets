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

// 默认档位。**不要改这个值** —— 它就是 P4/P5 时期写死的那个 6。
export const LIST_CACHED_COUNT_DEFAULT: number = 6;

// 可选档位。A/B 的三档；顺序即界面上从左到右的顺序。
//
// 为什么下限是 4 而不是 2：P2 的 10:43 真机 trace 里，两行缓存被一次 90Hz
// 快速 fling 直接吃穿。4 是"还值得一测"的下界。
// 为什么上限是 8：cachedCount 越大，LazyForEach/Repeat 的预加载（trace 里的
// predict）要提前建的行越多 —— 而 P6 要治的正是 predict 占掉的那 1759ms。
// 8 已经是一屏短消息（10~16 行）的半屏往上，再大只是把重建成本前移。
export const LIST_CACHED_COUNT_OPTIONS: number[] = [4, 6, 8];

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
