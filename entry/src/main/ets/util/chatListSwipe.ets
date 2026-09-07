// 会话列表左右滑动作的唯一视觉规格。主列表与文件夹/归档列表分别持有自己的
// ListScroller，但按钮尺寸、文案、图标和颜色不应各复制一份。

export const CHAT_SWIPE_BUTTON_VP: number = 76;
export const CHAT_SWIPE_ACTION_HEIGHT: string = 'calc(100% - 6vp)';
export const CHAT_SWIPE_VERTICAL_GUTTER_VP: number = 3;
export const CHAT_SWIPE_RADIUS_VP: number = 16;
export const CHAT_SWIPE_TRIGGER_VP: number = 76;
// ArkUI 的长滑铺满动画固定为 400ms；动作延后一帧，避免业务刷新或主动收起截断它。
export const CHAT_SWIPE_COMMIT_DELAY_MS: number = 420;

// 长滑进入动作区后，ArkUI 会把 builder 顶层扩到整行并播放确认动画。两套列表
// 必须显式使用 Spring 才能越过普通按钮宽度进入该区域；顶层颜色与圆角由调用方
// 同节点承载，扩张时才不会露出子按钮的直角底色。
export const CHAT_SWIPE_EDGE_EFFECT: SwipeEdgeEffect = SwipeEdgeEffect.Spring;

export interface ChatSwipeActionVisual {
  symbol: string;
  background: string;
}

const MARK_READ: ChatSwipeActionVisual = {
  symbol: 'sys.symbol.checkmark_circle',
  background: '#3390EC'
};

const MARK_UNREAD: ChatSwipeActionVisual = {
  // circle_badge 不在 API 26 系统 Symbol 资源表里，真机会只剩文字。
  symbol: 'sys.symbol.circle',
  background: '#3390EC'
};

const MUTE: ChatSwipeActionVisual = {
  symbol: 'sys.symbol.bell_slash',
  background: '#8E8E93'
};

const UNMUTE: ChatSwipeActionVisual = {
  symbol: 'sys.symbol.bell',
  background: '#8E8E93'
};

const ARCHIVE: ChatSwipeActionVisual = {
  symbol: 'sys.symbol.archivebox',
  background: '#F09A37'
};

const UNARCHIVE: ChatSwipeActionVisual = {
  symbol: 'sys.symbol.archivebox',
  background: '#F09A37'
};

export function readSwipeVisual(unread: boolean): ChatSwipeActionVisual {
  return unread ? MARK_READ : MARK_UNREAD;
}

export function muteSwipeVisual(muted: boolean): ChatSwipeActionVisual {
  return muted ? UNMUTE : MUTE;
}

export function archiveSwipeVisual(archived: boolean): ChatSwipeActionVisual {
  return archived ? UNARCHIVE : ARCHIVE;
}
