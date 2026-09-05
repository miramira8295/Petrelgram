// ChatPage 的模块级调优常量。原本住在 pages/chat/ChatPage.ets 顶部（279–343 行），
// 按主题分组：滚动与跳转、贴纸飞入、复用池封顶、顶部卡片、首屏分级揭示、输入区
// 与键盘。搬到这里只是换了住处，值、名字、注释一字未动——注释里记着真机数字、
// 帧率折算和「为什么是这个值」，它们才是这些常量的正文。
//
// 引用了 ChatPage 内方法名的注释原样保留（例如 restoreScrollAnchor）。
// 两个例外没有搬进来：止血开关 APPEND_ANCHOR_RESTORE_BYPASSED 去了
// util/appendAnchor.ets（与它守护的判据 shouldHoldAppendAnchor 同文件），
// 临时探针常量 ANCHOR_AUDIT_DELAY_MS 随探针一并删除。
//
// 另有三段注释没有跟来：它们描述的常量早就搬走了，注释被留在 ChatPage 顶部成了
// 孤儿，贴在毫不相干的常量上方（"Composer geometry. These three…" 正贴着
// KEYBOARD_SETTLE_MS）。搬家是纠正这种错位的时机，所以各归各位了：
//   · 实时位置上报间隔 → services/LiveLocationService.ets 里已有等价原文，本处删除；
//   · cachedCount 取值理由 → util/debugListPerf.ets（值 LIST_CACHED_COUNT_DEFAULT 在那）；
//   · Composer geometry → pages/chat/ChatComposerInput.ets（三个常量在那）。

// Scroll-to-bottom FAB: beyond this many groups from the end, reload the newest
// page instead of scrolling row by row through the loaded history.
export const JUMP_RELOAD_THRESHOLD: number = 40;
// Grace period before an entered-from-global-search chat runs its in-chat search.
export const SEARCH_ENTRY_DELAY_MS: number = 400;
// 等上下文菜单收起再弹确认框：菜单是独立子窗口，收起过程中弹出的
// 对话框会挂死（Promise 既不 resolve 也不 reject）。
export const MENU_DISMISS_MS: number = 150;
export const NOW_SEC_TICK_MS: number = 30000;
export const STICKER_FLY_MS: number = 260;
export const STICKER_GHOST_SIDE: number = 92;

// 全局复用池按桶封顶的最小间隔。封顶本身只是遍历一个个位数长度的数组，但
// 每次给 maxCount 赋值都会让框架做一次异步清理，没必要在连续 fling 的每次
// 停手上都跑一遍。
export const REUSE_CAP_MIN_INTERVAL_MS: number = 1000;
export const PREPARED_MESSAGE_CACHE_LIMIT: number = 1024;

export const CHAT_HEADER_NAV_GUARD_MS: number = 700;
export const TOP_CARD_LOADING_DELAY_MS: number = 180;
export const TOP_CARD_ACTION_GUARD_MS: number = 650;
// A delayed frame callback cannot be drained again inside the same VSync. On
// the measured 90 Hz device, 12 ms crosses one 11.1 ms frame boundary and lets
// the row admitted by the previous callback complete layout before the next.
export const INITIAL_MESSAGE_RELEASE_DELAY_MS: number = 12;
// Do not flash a ready one-row timeline in the first instant of the destination
// push. Bottom landings now wait for a stable lower slice, so they need a much
// shorter floor than an unread anchor whose complete visible window is prepared.
export const INITIAL_TIMELINE_PRESENT_MIN_MS: number = 80;
export const INITIAL_BOTTOM_PRESENT_MIN_MS: number = 48;
// The data is already complete and anchored when these animations start. Only
// render transforms are staggered; no row is inserted or resized here.
export const INITIAL_TIMELINE_ROW_FADE_MS: number = 90;
export const INITIAL_TIMELINE_ROW_STAGGER_MS: number = 14;
export const INITIAL_TIMELINE_REVEAL_ROW_LIMIT: number = 8;
// Reveal only after real rows cover the complete visible message viewport.
// Older offscreen rows may continue staging after the page is visible, but
// visible placeholder replacement must not trigger repeated height correction.
// NavDestination.onShown is emitted near the beginning of a push, not when the
// spring has settled. This duration fences the first ready message publication
// and also remains the empty-timeline watchdog below. The trace shows onReady
// can lead the system page-switch animation by about 50-75 ms, so leave enough
// room for the measured ~600 ms transition plus a couple of render frames.
export const INITIAL_MESSAGE_TRANSITION_SETTLE_MS: number = 760;

// 系统键盘从请求到落定的大致时间。摁住播放器销毁队列用这个数——量到的
// 键盘弹出被拖到 1859ms，其中绝大部分是销毁占的主线程。
export const KEYBOARD_SETTLE_MS: number = 700;
// 跳转落地后多久才允许"用户自己滚回最新"的判定重新生效。
export const JUMP_LANDING_GRACE_MS: number = 900;
