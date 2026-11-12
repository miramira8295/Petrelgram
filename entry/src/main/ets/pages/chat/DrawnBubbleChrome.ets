import { UIContext } from '@kit.ArkUI';
import { MessageEntry, ReactionInfo } from '../../store/MessageEntry';
import { DrawnAlbumRect } from '../../util/drawnAlbumPolicy';
import { str, plural } from '../../util/strings';
import { COLOR_PRIMARY } from '../../util/theme';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { DrawnReactionLayouts, DrawnReactionPlan } from './DrawnReactionLayout';

export class DrawnChromeContent {
  forward: DrawnTextLine | null = null;
  comments: DrawnTextLine | null = null;
  avatarCount: number = 0;
  width: number = 0;
  reactionWidth: number = 0;
  hasReactions: boolean = false;
}
const EMPTY_DRAWN_CHROME: DrawnChromeContent = new DrawnChromeContent();

export class DrawnBubbleChrome {
  content: DrawnChromeContent;
  forwardRect: DrawnAlbumRect = { x: 0, y: 0, width: 0, height: 0 };
  commentsRect: DrawnAlbumRect = { x: 0, y: 0, width: 0, height: 0 };
  commentsTextX: number = 0;
  reactions: DrawnReactionPlan | null = null;
  reactionsX: number = 0;
  reactionsY: number = 0;
  constructor(content: DrawnChromeContent) { this.content = content; }
}

// Shared by text and albums. Incoming message snapshots may change for unrelated
// reasons; fixed fields + reaction array identity keep a warm hit O(1).
export class DrawnChromeLayouts {
  private forward: DrawnTextLineCache | null = null;
  private comments: DrawnTextLineCache | null = null;
  private reactions: DrawnReactionLayouts | null = null;
  private previous: DrawnChromeContent | null = null;
  private key: string = '';
  private reactionSource: ReactionInfo[] | null = null;

  prepare(ui: UIContext, msg: MessageEntry, isChannel: boolean, maxWidth: number,
    environment: string): DrawnChromeContent {
    const commentCount = isChannel ? msg.commentCount : 0;
    if (msg.forwardFrom === '' && commentCount === 0 && msg.reactions.length === 0) {
      // Do not allocate per-label caches/arrays for the common plain row.
      // Reuse from a decorated row also drops its old native paragraphs.
      if (this.previous !== null) {
        this.forward = null; this.comments = null; this.reactions = null;
        this.previous = null; this.reactionSource = null; this.key = '';
      }
      return EMPTY_DRAWN_CHROME;
    }
    const d = ui.vp2px(1);
    const avatars = commentCount > 0 ? Math.min(3, msg.commentReplierIds.length) : 0;
    const key = `${d}:${ui.fp2px(13)}:${maxWidth}:${environment}:${isChannel}:` +
      `${msg.forwardFrom}:${commentCount}:${avatars}`;
    if (this.previous !== null && this.key === key && this.reactionSource === msg.reactions) { return this.previous; }
    const p = new DrawnChromeContent();
    if (msg.forwardFrom !== '' && this.forward === null) { this.forward = new DrawnTextLineCache(); }
    if (commentCount > 0 && this.comments === null) { this.comments = new DrawnTextLineCache(); }
    p.forward = msg.forwardFrom !== '' && this.forward !== null ? this.forward.prepare(str('mb_forwarded_from', msg.forwardFrom),
      maxWidth * d, ui.fp2px(13), drawnColor(COLOR_PRIMARY), environment, true) : null;
    p.avatarCount = avatars;
    const avatarWidth = avatars > 0 ? 22 + (avatars - 1) * 14 + 6 : 0;
    p.comments = commentCount > 0 && this.comments !== null ? this.comments.prepare(plural('mb_comments_n', commentCount, commentCount),
      Math.max(1, (maxWidth - avatarWidth - 19) * d), ui.fp2px(13), drawnColor(COLOR_PRIMARY), environment, true) : null;
    if (msg.reactions.length > 0 && this.reactions === null) { this.reactions = new DrawnReactionLayouts(); }
    if (msg.reactions.length === 0) { this.reactions = null; }
    const reactionWidth = this.reactions !== null ? this.reactions.measure(ui, msg.reactions, maxWidth, !isChannel, environment) : 0;
    p.reactionWidth = reactionWidth;
    p.hasReactions = msg.reactions.length > 0;
    p.width = Math.min(maxWidth, Math.max(p.forward !== null ? p.forward.widthPx / d : 0,
      p.comments !== null ? p.comments.widthPx / d + avatarWidth + 19 : 0, reactionWidth));
    this.key = key; this.reactionSource = msg.reactions; this.previous = p; return p;
  }

  reactionFlow(width: number): DrawnReactionPlan {
    if (this.reactions === null) { throw new Error('reaction layout requested without reactions'); }
    return this.reactions.flow(width);
  }
}

// Append just the reaction/footer area. It never changes the body's paragraph.
// The timestamp uses the last chip row if it fits, otherwise a separate line.
export interface DrawnChromeFooter { bottom: number; footerY: number; }
export function placeChromeReactions(chrome: DrawnBubbleChrome, reactions: DrawnReactionPlan,
  x: number, y: number, width: number, footerWidth: number, footerHeight: number): DrawnChromeFooter {
  chrome.reactions = reactions; chrome.reactionsX = x; chrome.reactionsY = y + 8;
  const bottom = chrome.reactionsY + reactions.height;
  const fits = reactions.lastRight + 6 + footerWidth <= width;
  const footerY = fits ? bottom - Math.min(reactions.lastHeight, footerHeight) : bottom + 4;
  return { bottom: Math.max(bottom, footerY + footerHeight), footerY };
}

export function placeChromeComments(chrome: DrawnBubbleChrome, x: number, y: number, width: number,
  density: number): number {
  const text = chrome.content.comments;
  if (text === null) { return y; }
  const avatars = chrome.content.avatarCount;
  const height = Math.max(avatars > 0 ? 22 : 0, text.heightPx / density);
  chrome.commentsRect = { x, y: y + 6, width, height: height + 14 };
  chrome.commentsTextX = x + (avatars > 0 ? 22 + (avatars - 1) * 14 + 6 : 0);
  return y + 6 + height + 14;
}
