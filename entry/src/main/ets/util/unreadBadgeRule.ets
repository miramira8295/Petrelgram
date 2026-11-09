// 文件夹/页签角标的统计规则（issue #155）。
// Telegram 的口径：数**全部**有未读消息的会话（静音的也算），颜色由"有没有未静音的"
// 决定——有就蓝，全是静音就灰。原来只数未静音的，一个文件夹全是静音频道时角标是 0。
export interface UnreadBadgeSource {
  unreadCount: number;
  muted: boolean;
}

export interface UnreadBadgeCounts {
  total: number;
  unmuted: number;
}

export function foldUnreadBadge(sources: UnreadBadgeSource[]): UnreadBadgeCounts {
  let total: number = 0;
  let unmuted: number = 0;
  for (const s of sources) {
    if (s.unreadCount <= 0) {
      continue;
    }
    total++;
    if (!s.muted) {
      unmuted++;
    }
  }
  return { total, unmuted };
}
