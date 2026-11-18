// Screen readers use DrawnRowAccessibility virtual targets alongside the same paint plan.
import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';


// Constant-time structural gate. Parsing/support checks live in the bounded
// source cache, never in build(). Structured content uses its own block compiler.
export function drawnTextRowEligible(group: AlbumGroup, data: MessageBubbleRenderData,
  _material: boolean, _accessibility: boolean): boolean {
  const m = group.head;
  if (group.memberIds.length === 1 && (m.contentType === 'file' || m.contentType === 'audio' || m.contentType === 'voice' || m.contentType === 'contact' || m.contentType === 'location' || m.contentType === 'venue' || m.contentType === 'poll' || m.contentType === 'videoNote' || m.contentType === 'dice' || m.contentType === 'game' || m.contentType === 'paidMedia' || m.contentType === 'gift' || m.contentType === 'giveaway' || m.contentType === 'sticker' || m.contentType === 'emoji' || m.contentType === 'customEmoji')) { return m.text.length <= 16384; }
  if (group.memberIds.length === 1 && m.contentType === 'richMessage') { return (m.richBlocks?.length ?? 0) > 0; }
  return group.memberIds.length === 1 && m.contentType === 'text' &&
    (m.text.length > 0 || m.linkUrl !== '') && m.text.length <= 16384;
}
