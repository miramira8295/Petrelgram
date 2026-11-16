import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';
import { drawnChromeTextSupported } from './drawnPlainTextPolicy';
import { DrawnRouteReason } from './drawnRouteMetrics';

export function drawnRowChromeReason(group: AlbumGroup, data: MessageBubbleRenderData, role: string): DrawnRouteReason {
  const m = group.head;
  if (m.forwardFrom !== '' && !drawnChromeTextSupported(m.forwardFrom)) { return DrawnRouteReason.ChromeForward; }
  if (data.isGroup && !m.isOutgoing && group.showSenderName && m.senderName !== '') {
    if (!drawnChromeTextSupported(m.senderName)) { return DrawnRouteReason.ChromeSender; }
    if (!drawnChromeTextSupported(m.senderTag || role)) { return DrawnRouteReason.ChromeRole; }
  }
  if (m.replyToMessageId !== 0) {
    if (!drawnChromeTextSupported(m.replySenderName)) { return DrawnRouteReason.ChromeReplySender; }
    if (!drawnChromeTextSupported(m.replyText)) { return DrawnRouteReason.ChromeReplyText; }
  }
  return DrawnRouteReason.Drawn;
}
