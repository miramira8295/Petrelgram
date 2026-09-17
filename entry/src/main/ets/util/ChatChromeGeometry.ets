// 聊天页顶部悬浮区域的固定几何。
//
// 标题文字、头像加载态等内容变化不能再反过来改变 List 的
// contentStartOffset；只有模式、系统安全区和置顶/直播横幅这些真正的结构变化
// 才能改变顶部占位。

export const CHAT_HEADER_BASE_HEIGHT: number = 58;
export const CHAT_SEARCH_HEADER_BASE_HEIGHT: number = 62;
export const CHAT_TOP_BANNER_ROW_HEIGHT: number = 54;
export const CHAT_TOP_BANNER_DIVIDER_HEIGHT: number = 0.5;
export const CHAT_TOP_BANNER_BOTTOM_GAP: number = 2;
// 论坛话题横条（2026-09-16）：标题行下面那条可横向滚的话题胶囊。
// 取 36 与首页文件夹横条的 FOLDER_BAR_HEIGHT 一致——两处是同一种控件，
// 高度不该各编一个数字。
export const CHAT_TOPIC_BAR_HEIGHT: number = 36;

export interface ChatChromeGeometryInput {
  topSafe: number;
  searchMode: boolean;
  pinnedVisible: boolean;
  liveVisible: boolean;
  // 会话操作条（issue #201 第 8 条）。可选：老调用点不传就是没有。
  actionBarVisible?: boolean;
  // 论坛话题横条（2026-09-16）。同样可选：非论坛会话不传，顶栏高度与以前逐像素一致。
  topicBarVisible?: boolean;
}

export function chatTopBannerRows(input: ChatChromeGeometryInput): number {
  let rows: number = 0;
  if (input.pinnedVisible) {
    rows++;
  }
  if (input.liveVisible) {
    rows++;
  }
  if (input.actionBarVisible ?? false) {
    rows++;
  }
  return rows;
}

export function chatTopBannerHeight(input: ChatChromeGeometryInput): number {
  const rows: number = chatTopBannerRows(input);
  if (rows === 0) {
    return 0;
  }
  return rows * CHAT_TOP_BANNER_ROW_HEIGHT +
    (rows - 1) * CHAT_TOP_BANNER_DIVIDER_HEIGHT + CHAT_TOP_BANNER_BOTTOM_GAP;
}

// 话题横条占多高。它**不是 banner 行**：banner 每行恒 54 且带分隔线，而横条更矮、
// 常驻、自己横向滚，所以单列一项而不是挤进 chatTopBannerRows。
export function chatTopicBarHeight(input: ChatChromeGeometryInput): number {
  return (input.topicBarVisible ?? false) ? CHAT_TOPIC_BAR_HEIGHT : 0;
}

export function chatChromeHeight(input: ChatChromeGeometryInput): number {
  const header: number = input.searchMode
    ? CHAT_SEARCH_HEADER_BASE_HEIGHT : CHAT_HEADER_BASE_HEIGHT;
  return Math.max(0, input.topSafe) + header +
    chatTopicBarHeight(input) + chatTopBannerHeight(input);
}
