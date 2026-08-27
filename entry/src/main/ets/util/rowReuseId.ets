import { MessageEntry } from '../store/MessageEntry';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';
import { AlbumGroup } from './collapseAlbums';

// Reuse-pool key for the ReusableMessageBubble shell, ordered by how coarsely
// it splits the pool into buckets. Coarser levels give higher hit rates but
// mix more shapes into one pool; finer levels isolate shapes more precisely
// at the cost of more pools (each with fewer spare nodes to hand back).
// Which level actually performs best on this list is an open question for a
// later task (P2 Task 3) — this file only makes the level a parameter so that
// measurement can be done without touching call sites again.
export type ReuseIdLevel = 'coarse' | 'medium' | 'fine';

type MediaKind = 'none' | 'photo' | 'video' | 'sticker' | 'file' | 'other' | 'system' | 'hidden';

// The three-way top-level fork MessageBubble.build() (~3401-3416) makes
// before anything else: 'hidden' renders a zero-height empty node, 'system'
// renders a centered service pill with no avatar/bubble/time layer at all,
// and everything else renders the full message-row tree. These three trees
// share nothing, so this has to be checked before any of the finer switches
// below make sense. See docs/superpowers/specs/2026-08-26-p2-state-audit.md,
// P0-5 (~257-261), which spells this exact three-way split out as the spec.
type ContentKind = 'hidden' | 'system' | 'normal';

// Whether the row's build() picks the lightweight plain-text renderer or the
// full MessageBubble tree — the single largest structural fork in the row.
// The real condition (ReusableMessageBubble.build() ~224) is
// `data.lightweightPlainText && group.head.translatedText === ''`, not
// data.lightweightPlainText alone: a lightweight-eligible row that has
// picked up a translation still falls through to the full MessageBubble
// tree, so translatedText has to be part of even the coarse split — leaving
// it out mixes a genuinely lightweight row with a full-tree row into the
// same 'plain' bucket.
function coarseBucket(data: MessageBubbleRenderData, group: AlbumGroup): string {
  const lightweight: boolean = data.lightweightPlainText && group.head.translatedText === '';
  return lightweight ? 'plain' : 'rich';
}

function contentKind(msg: MessageEntry): ContentKind {
  if (msg.contentType === 'hidden') {
    return 'hidden';
  }
  if (msg.contentType === 'system') {
    return 'system';
  }
  return 'normal';
}

// showAvatar/showSenderName are the real per-row structural flags, computed
// once per row in collapseAlbums.ets (~290-292) as "last row of a same-sender
// run" / "first row of a same-sender run" respectively. They gate whether
// MessageBubble.ets renders the avatar column (~3439) and the sender-name
// line (~3494) at all, so they belong in the reuseId at the same granularity
// LazyForEach already uses for its row key: collapseAlbums.ets:292 encodes
// them into AlbumGroup.key ('A'/'a' + 'N'/'n') for exactly this reason — a
// key that tells rows apart while reuseId lumps them together is the
// structural-mismatch failure mode the diagnostics doc warns about.
function hasAvatarBranch(group: AlbumGroup): boolean {
  return group.showAvatar;
}

// The real condition (MessageBubble.ets:3494, LightweightPlainTextBubble.ets
// :640-641) is `isGroup && !isOutgoing && senderName !== '' && showSenderName`
// — group.showSenderName alone is the run-position half of that, but a row
// with showSenderName=true and an empty senderName (channel posts, anonymous
// admins) renders no name node at all and must not share a bucket with a row
// that does render one.
function hasSenderNameBranch(group: AlbumGroup): boolean {
  return group.showSenderName && group.head.senderName !== '';
}

// msg.isOutgoing is not a style difference: MessageBubble.ets flips which
// child comes first in the tail Row depending on direction (incoming ~3471-
// 3475: tail before the bubble; outgoing ~3610-3614: tail after), and
// LightweightPlainTextBubble.ets mirrors it at ~633-636 / ~675-679. It also
// gates whether a trailing statusIcon() node exists at all (outgoing only).
// This is independent of, and additive to, group.showAvatar — a group's
// avatar-column existence (MessageBubble.ets ~3439: `isGroup && !isOutgoing`)
// already depends on isOutgoing too, but direction still has to be tracked
// on its own because it also reorders/adds nodes on rows where the avatar
// branch doesn't even apply (private chats, and outgoing rows in general).
function isOutgoingBranch(group: AlbumGroup): boolean {
  return group.head.isOutgoing;
}

// MessageBubble.ets:1075-1079 useDirectPlainText()'s hasLinkPreview() input:
// a single Text node vs. a Column -> content() -> multi-level ForEach tree
// whenever any of these five fields is non-empty/non-zero. Copied verbatim
// from that definition, not reinvented.
function hasLinkPreview(msg: MessageEntry): boolean {
  return msg.linkUrl !== '' || msg.linkSiteName !== '' ||
    msg.linkTitle !== '' || msg.linkDescription !== '' ||
    msg.linkPhotoFileId !== 0;
}

// AlbumGroup.dateLabel is '' unless this row is the first of a new day, in
// which case MessageBubble.ets (~3420) inserts a centered date-pill Text
// above the bubble — an extra node that changes the row's child count/shape.
function hasDateSeparator(group: AlbumGroup): boolean {
  return group.dateLabel !== '';
}

// data.showUnreadDivider (MessageBubbleRenderData) mirrors the same-named
// context field ChatPage computes per row (prepareMessageBubble, ~1020-1021:
// true when the row's message ids include the chat's first-unread id).
// MessageBubble.ets (~3427) renders a centered "unread" pill above the bubble
// when set — another node the reuseId must track, same reasoning as the date
// separator.
function hasUnreadDivider(data: MessageBubbleRenderData): boolean {
  return data.showUnreadDivider;
}

function hasReplyBlock(msg: MessageEntry): boolean {
  return msg.replyToMessageId !== 0;
}

function hasForwardHeader(msg: MessageEntry): boolean {
  return msg.forwardFrom !== '';
}

function hasReactionBar(msg: MessageEntry): boolean {
  return msg.reactions.length > 0;
}

// translatedText ('' = no translation, see MessageEntry.ets:111-115) is the
// single largest structural fork this row can take: ReusableMessageBubble.
// build() (~215) routes to LightweightPlainTextBubble only when
// `data.lightweightPlainText && group.head.translatedText === ''` — a
// translated row always falls through to the full MessageBubble tree, a
// bigger subtree swap than any of the switches above. translationActive (the
// chat-level translation toggle) is deliberately excluded: it is constant
// across every row in one chat, so it can never cause a same-scroll pool
// mismatch the way a per-row flag can.
function hasTranslation(msg: MessageEntry): boolean {
  return msg.translatedText !== '';
}

function mediumBucket(data: MessageBubbleRenderData, group: AlbumGroup): string {
  const msg: MessageEntry = group.head;
  const content: string = contentKind(msg);
  const avatar: string = hasAvatarBranch(group) ? 'avatar' : 'no-avatar';
  const senderName: string = hasSenderNameBranch(group) ? 'sender' : 'no-sender';
  const outgoing: string = isOutgoingBranch(group) ? 'out' : 'in';
  const reply: string = hasReplyBlock(msg) ? 'reply' : 'no-reply';
  const forward: string = hasForwardHeader(msg) ? 'forward' : 'no-forward';
  const reactions: string = hasReactionBar(msg) ? 'reactions' : 'no-reactions';
  const dateSep: string = hasDateSeparator(group) ? 'date' : 'no-date';
  const unread: string = hasUnreadDivider(data) ? 'unread' : 'no-unread';
  const translated: string = hasTranslation(msg) ? 'translated' : 'no-translated';
  const linkPreview: string = hasLinkPreview(msg) ? 'link-preview' : 'no-link-preview';
  // 裸表情/贴纸/圆形视频没有气泡面：不上玻璃、不画轮廓、不带尾巴。它们和文本行
  // 共池时，一个带玻璃轮廓+尾巴的文本行被复用去画表情，.background() 里那条
  // 轮廓路径不跟着刷新，表情就套着一圈边框（真机报的「表情/贴纸带边框」）。
  // mediaKind 只在 fine 档进 key，medium 档得自己分开这两类面。
  const surface: string = isBareSurface(msg) ? 'bare' : 'bubble';
  return `${coarseBucket(data, group)}:${content}:${avatar}:${senderName}:${outgoing}` +
    `:${reply}:${forward}:${reactions}:${dateSep}:${unread}:${translated}:${linkPreview}:${surface}`;
}

// 与 MessageBubble.isBareEmoji() 同一份判据（外加 dice，它同样没有气泡面）。
function isBareSurface(msg: MessageEntry): boolean {
  return msg.contentType === 'emoji' || msg.contentType === 'sticker'
    || msg.contentType === 'customEmoji' || msg.contentType === 'videoNote'
    || msg.contentType === 'dice';
}

// contentType values are enumerated from every `contentType === '...'` check
// in the codebase (store/MessageEntry.ets, pages/chat, util). Mapping choices
// that are not a literal file-kind match:
// - 'system' / 'hidden' each get their own MediaKind (NOT folded into
//   'none'): contentKind() above already routes them to a completely
//   different top-level tree (an empty node / a centered service pill), and
//   mediaKind must not paper back over that split by lumping them in with a
//   plain text row's 'none' — a Column().height(0) and a full text bubble
//   share nothing.
// - 'text' is the genuine no-media case and keeps 'none'.
// - 'customEmoji', 'dice', 'emoji' fold into 'sticker': all three render
//   through the same animated-sticker-shaped surface (see MessageStore.ets
//   customEmoji-to-sticker promotion and DiceBubble.ets).
// - 'voice' folds into 'file': both are a download/playback row built the
//   same shape as a generic file card, distinct from a picture or video.
// - Everything else without a clear file-kind match (contact, location,
//   venue, poll, game, paidMedia, gift, giveaway, richMessage, storyContent*,
//   'other', and any future/unsupported type) falls into 'other' rather than
//   being given a bespoke bucket, per the task's requested five-way split.
function mediaKind(msg: MessageEntry): MediaKind {
  switch (msg.contentType) {
    case 'system':
      return 'system';
    case 'hidden':
      return 'hidden';
    case 'text':
      return 'none';
    case 'photo':
      return 'photo';
    case 'video':
    case 'videoNote':
      return 'video';
    case 'sticker':
    case 'customEmoji':
    case 'dice':
    case 'emoji':
      return 'sticker';
    case 'file':
    case 'audio':
    case 'voice':
      return 'file';
    default:
      return 'other';
  }
}

function fineBucket(data: MessageBubbleRenderData, group: AlbumGroup): string {
  return `${mediumBucket(data, group)}:${mediaKind(group.head)}`;
}

// Structure-only reuse-pool key for the ReusableMessageBubble shell. Message
// id, text content, timestamps, sender id and any other value that varies
// with content but not with row structure must never enter this id: doing so
// turns every row into a one-entry pool and defeats reuse entirely (see the
// warning on messageBubbleReuseId in messageBubbleReuse.ets).
//
// This is deliberately a different, coarser function than
// messageBubbleReuseId in messageBubbleReuse.ets. That one buckets on ~20
// dimensions for a different consumer and is documented (per the official
// component-reuse guidance) as too fine-grained to use as the pool key here:
// an overly specific reuseId starves every pool of spare nodes and performs
// worse than no reuse at all. rowReuseId stays deliberately coarse and
// adjustable (coarse/medium/fine) so the right granularity can be measured
// instead of assumed.
//
// Takes the whole AlbumGroup (not just its head MessageEntry) because the
// avatar/sender-name/date-separator flags this function needs are per-row
// properties collapseAlbums.ets computes on the group, not on the message
// itself — see hasAvatarBranch/hasSenderNameBranch/hasDateSeparator above.
export function rowReuseId(data: MessageBubbleRenderData, group: AlbumGroup, level: ReuseIdLevel): string {
  if (level === 'coarse') {
    return coarseBucket(data, group);
  }
  if (level === 'medium') {
    return mediumBucket(data, group);
  }
  return fineBucket(data, group);
}
