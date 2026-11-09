// 底部抽屉的尺寸。附件面板是两行快捷入口，媒体面板则要承载可滚动的
// 表情、贴纸和 GIF 网格，两者不再硬塞进同一个高度。
//
// 抽出来是因为这个数原先散在三处（AttachPanel 的 260、EmojiPanel 的 300、
// ChatPage 里各自的常量），各写各的迟早再次跑偏。改高度只改这里。

// 附件抽屉：上下留白各 14、两行、行距 6。
export const BOTTOM_DRAWER_HEIGHT: number = 260;

// 表情/贴纸/GIF 抽屉。312 能稳定放下 46 高的主分类条、44 高的表情包条，
// 同时给网格留出 222vp；不再为了迁就附件入口把可滚动内容压到一屏半。
export const EMOJI_DRAWER_HEIGHT: number = 312;

// 卡片距键盘区三边的留白。沿用表情面板当浮卡时的 calc(100% - 16vp)——左右
// 各 8；底部同样留 8，让卡片浮起来而不是糊在屏幕下沿。顶部不留：卡片上沿
// 贴着输入框，两者读起来是连着的。
export const DRAWER_INSET: number = 8;

// 抽屉顶部三段式主分类条。图标+文字始终完整展示，触控高度不低于 36vp。
export const EMOJI_TAB_BAR_HEIGHT: number = 46;

// 表情抽屉的内容区。
export const EMOJI_CONTENT_HEIGHT: number = EMOJI_DRAWER_HEIGHT - EMOJI_TAB_BAR_HEIGHT;

// 抽屉卡片下沿到屏幕底的距离：整条导航手势带（bottomSafe）都让出来，至少留
// DRAWER_INSET 让卡片浮起来。
//
// 原来是 min(12, bottomSafe / 2)，理由是「手势条本身只占安全区的一小条，全留
// 显得下面空」——但那一截是系统的手势识别区，卡片底部那条标签栏落进去，点
// 「表情 / 贴纸 / GIF」时就会误触小白条（issue #154）。输入框收起面板时留的
// 也是整条 bottomSafe（composerBottomGap），两处对齐。
export function drawerBottomInset(bottomSafe: number): number {
  return Math.max(DRAWER_INSET, Math.round(bottomSafe));
}
