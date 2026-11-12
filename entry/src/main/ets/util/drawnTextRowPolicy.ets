// Screen readers deliberately retain native semantics (actions, selection, replies and media).
// Remove that fallback only after equivalent virtual accessibility nodes are verified.
import { AlbumGroup } from './collapseAlbums';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';


// Constant-time structural gate. Parsing/support checks live in the bounded
// source cache, never in build(). Structured richMessage blocks keep their UI.
export function drawnTextRowEligible(group: AlbumGroup, data: MessageBubbleRenderData,
  material: boolean, accessibility: boolean): boolean {
  const m = group.head;
  return !material && !accessibility && group.memberIds.length === 1 && m.contentType === 'text' &&
    m.text.length > 0 && m.text.length <= 16384 && m.translatedText === '' &&
    m.linkUrl === '' && m.linkTitle === '' && m.linkSiteName === '' &&
    m.linkDescription === '' && m.linkPhotoFileId === 0;
}
