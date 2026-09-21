import { NATIVE_PIXEL_CACHE_MAX_BYTES } from './NativePixelBudget';

// 图片位图缓存向透明贴纸缓存借用闲置额度。
//
// 【为什么 —— 2026-09-20 真机定位】原来两边各自钉死：图片 48MiB、贴纸 32MiB，
// 合计 80MiB 压在设备采样的 100MiB NativeBinding 警戒线下。问题是这两笔钱几乎
// 从不同时花：纯图片会话里贴纸那 32MiB 整个空着，而图片这边正被撑爆——相册一格
// 319x490 就是 625KB（改 RGB_565 之后 312KB），48MiB 装不下可视窗口要的
// 120–180 格，滚一下就把马上要用的图淘汰掉，滚回来重解码，表现为"图片闪一下"。
// 实测 blank=705 / hit=195，淘汰数随滚动单调涨到 264，缓存恒定贴在 48.0MiB。
//
// 【为什么只有图片这一侧是动态的】贴纸那套（多帧条目、引用计数、clip）有好几处
// 准入与回收点，改动面大而收益小——它本来就没到过自己的线。单向借用已经能拿到
// 全部收益，而且不变式更好证：
//     image ≤ TOTAL − max(alphaUsed, ALPHA_FLOOR)
//   ⇒ image + alphaUsed ≤ TOTAL            （alphaUsed ≥ ALPHA_FLOOR 时取等）
//   ⇒ image + alphaUsed ≤ IMAGE_CAP + ALPHA_FLOOR < TOTAL  （alphaUsed 更小时）
// 两种情况都压在 TOTAL 之下，而贴纸侧完全不用改。
//
// 【已知的瞬时越界】图片算完限额之后贴纸才长——图片下一次插入按新数回收就收敛，
// 越界幅度不超过一次插入的大小。
//
// 【已知的代价】图片会话切到贴纸会话时，贴纸要先把图片挤出去才拿得到空间，
// 那一下会有一次回吐（图片重解码）。已知并接受。

// 给贴纸留的地板：借得再多也不能把它压到这条线以下。
export const ALPHA_FLOOR_BYTES: number = 12 * 1024 * 1024;

// 钉住的位图（pin / pinBounded）额外获准占用的份额，**不挤占可淘汰预算**。
//
// 【为什么要单开一格 —— 2026-09-21】钉住的条目 evictDownTo 跳过不回收，所以它们
// 每多一个字节，可淘汰的内容就少一个字节。真机 [Fmt] 读数：聊天壁纸一张
// 1316x2832 就是 **14.9MB**（占当时 68MiB 预算的 21%），再加上有上限的头像钉
// （48 张 × 约 100KB ≈ 4.8MB）——内容缓存实际只剩 48MiB 上下，而它本该有 68。
// 同一天给 AvatarView 补上 pinBounded 之后这块还会再涨，不单开就是越挤越死。
//
// 12MiB 的来历：壁纸改按 RGB_565 解码后约 7.4MB（见 ChatBackdrop 的 opaque），
// 加上头像钉的 4.8MB，正好压在这条线下。**超出的部分不再享受豁免**——
// 钉住的东西无限增长时，多出来的照样从可淘汰预算里扣，不会把真实内存顶穿。
export const PINNED_ALLOWANCE_BYTES: number = 12 * 1024 * 1024;

// 图片**可淘汰**部分的天花板。总量 = 它 + 钉住的份额，仍然压在
// NATIVE_PIXEL_CACHE_MAX_BYTES − 贴纸地板 之内，所以这次改动**不抬高真实内存**，
// 只是把"谁被挤"这件事从内容改成了明确划出来的一格。
export const IMAGE_CAP_BYTES: number =
  NATIVE_PIXEL_CACHE_MAX_BYTES - ALPHA_FLOOR_BYTES - PINNED_ALLOWANCE_BYTES;

// 纯函数，便于回归测试：给定总线与贴纸此刻的实际占用，图片能用多少字节。
//
// ceilingBytes 是调用方自己那一侧的上限（内存压力下会被收紧），最终取两者的小者。
export function sharedImageLimit(
  totalBytes: number, alphaUsedBytes: number, ceilingBytes: number = IMAGE_CAP_BYTES
): number {
  const total: number = Math.max(0, Math.floor(totalBytes));
  const reserved: number = Math.max(Math.max(0, Math.floor(alphaUsedBytes)), ALPHA_FLOOR_BYTES);
  const free: number = total - reserved;
  const ceiling: number = Math.max(0, Math.min(IMAGE_CAP_BYTES, Math.floor(ceilingBytes)));
  return Math.max(0, Math.min(ceiling, free));
}

// ---- 运行期接线 ----
//
// 贴纸那边向这里报数，但两个模块**不互相 import**：pixelCache 是 util 层、
// AlphaStickerStore 是 service 层，直接引会把层次倒过来，也容易成环。
// 没注册过就当 0——纯图片会话里贴纸模块根本不会被加载，图片自然拿到全部额度。

let alphaUsedGetter: () => number = (): number => 0;
// 内存压力下由生命周期回调收紧。目前 NativePixelBudget 的 pressuredNativePixelBudget
// 全项目零调用，那套还没接上，属于另一笔待办；这里先保持满额。
let sharedTotalBytes: number = NATIVE_PIXEL_CACHE_MAX_BYTES;

export function registerAlphaPixelUsage(getter: () => number): void {
  alphaUsedGetter = getter;
}

export function setSharedPixelTotal(bytes: number): void {
  sharedTotalBytes = Math.max(0, Math.min(NATIVE_PIXEL_CACHE_MAX_BYTES, Math.floor(bytes)));
}

// 图片缓存每次插入前问一次：贴纸此刻占了多少，我就能用剩下的。
//
// pinnedBytes 是当前钉住的字节数：其中不超过 PINNED_ALLOWANCE_BYTES 的部分额外
// 放行（不挤占可淘汰预算），超出的部分照旧从预算里扣。
export function imagePixelLimitNow(ceilingBytes: number, pinnedBytes: number = 0): number {
  const base: number = sharedImageLimit(sharedTotalBytes, alphaUsedGetter(), ceilingBytes);
  const exempt: number = Math.max(0, Math.min(Math.floor(pinnedBytes), PINNED_ALLOWANCE_BYTES));
  return base + exempt;
}
