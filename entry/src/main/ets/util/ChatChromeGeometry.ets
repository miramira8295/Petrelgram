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

export interface ChatChromeGeometryInput {
  topSafe: number;
  searchMode: boolean;
  pinnedVisible: boolean;
  liveVisible: boolean;
  loadingVisible: boolean;
}

export function chatTopBannerRows(input: ChatChromeGeometryInput): number {
  let rows: number = 0;
  if (input.pinnedVisible) {
    rows++;
  }
  if (input.liveVisible) {
    rows++;
  }
  // 加载态只在没有已确认内容时占一行。
  if (rows === 0 && input.loadingVisible) {
    rows = 1;
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

export function chatChromeHeight(input: ChatChromeGeometryInput): number {
  const header: number = input.searchMode
    ? CHAT_SEARCH_HEADER_BASE_HEIGHT : CHAT_HEADER_BASE_HEIGHT;
  return Math.max(0, input.topSafe) + header + chatTopBannerHeight(input);
}
