// 底部抽屉的尺寸。附件和表情共用一个高度——两者在同一个位置轮流出现，
// 高度不同的话来回切换会跳一下。
//
// 抽出来是因为这个数原先散在三处（AttachPanel 的 260、EmojiPanel 的 300、
// ChatPage 里各自的常量），各写各的迟早再次跑偏。改高度只改这里。

// 抽屉卡片的高度。260 由附件面板定：上下留白各 14、两行、行距 6。
export const BOTTOM_DRAWER_HEIGHT: number = 260;

// 卡片距键盘区三边的留白。沿用表情面板当浮卡时的 calc(100% - 16vp)——左右
// 各 8；底部同样留 8，让卡片浮起来而不是糊在屏幕下沿。顶部不留：卡片上沿
// 贴着输入框，两者读起来是连着的。
export const DRAWER_INSET: number = 8;

// 表情抽屉底部那条「表情 / 贴纸 / GIF」标签条的高度。内容区是抽屉高度减掉它。
//
// 59 是它当浮卡（300 高）时的尺寸。抽屉压到 260 之后，这条 + 包切换条 44 +
// 搜索框 42 一共吃掉 145，真正的表情网格只剩 115——标签条自己就显得过大。
// 44 够放下"图标 + 文字 + 选中下划线"三层，且和包切换条同高。
export const EMOJI_TAB_BAR_HEIGHT: number = 44;

// 表情抽屉的内容区。抽屉压到 260 之后这里是 201，比当浮卡时（241）少一行。
export const EMOJI_CONTENT_HEIGHT: number = BOTTOM_DRAWER_HEIGHT - EMOJI_TAB_BAR_HEIGHT;
