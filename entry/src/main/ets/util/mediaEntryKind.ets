import { MessageEntry } from '../store/MessageEntry';

// 全屏查看器的"这条消息算不算图/视频"判据。从 ChatPage.ets 搬来（原
// `mediaEntryIsPhoto`/`mediaEntryIsVideo`，方法体一字未改）——它们一个字都不读
// `this`，留在页面里只是白占行数。

export function mediaEntryIsPhoto(entry: MessageEntry): boolean {
  return entry.contentType === 'photo' ||
    (entry.contentType === 'paidMedia' && !entry.paidMediaLocked &&
      entry.paidMediaKind === 'photo');
}

export function mediaEntryIsVideo(entry: MessageEntry): boolean {
  // 圆形视频不进全屏查看器——它在气泡里原地播放（见 MessageBubble）。
  return entry.contentType === 'video' ||
    (entry.contentType === 'paidMedia' && !entry.paidMediaLocked &&
      entry.paidMediaKind === 'video');
}
