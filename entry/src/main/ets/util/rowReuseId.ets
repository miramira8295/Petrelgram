import { MessageEntry } from '../store/MessageEntry';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';

// Reuse-pool key for the ReusableMessageBubble shell, ordered by how coarsely
// it splits the pool into buckets. Coarser levels give higher hit rates but
// mix more shapes into one pool; finer levels isolate shapes more precisely
// at the cost of more pools (each with fewer spare nodes to hand back).
// Which level actually performs best on this list is an open question for a
// later task (P2 Task 3) — this file only makes the level a parameter so that
// measurement can be done without touching call sites again.
export type ReuseIdLevel = 'coarse' | 'medium' | 'fine';

type MediaKind = 'none' | 'photo' | 'video' | 'sticker' | 'file' | 'other';

// Whether the row's build() picks the lightweight plain-text renderer or the
// full MessageBubble tree — the single largest structural fork in the row.
// See ReusableMessageBubble.build().
function coarseBucket(data: MessageBubbleRenderData): string {
  return data.lightweightPlainText ? 'plain' : 'rich';
}

// showAvatar/showSenderName in MessageBubble are run-position flags carried
// on AlbumGroup (see collapseAlbums.ets), not on a single MessageEntry, and
// this function only receives the entry plus the render data — so there is no
// exact field to read here. What follows is a structural proxy: it answers
// "does this row's branch that CAN hold an avatar column exist at all"
// (MessageBubble.ets ~3439: `if (isGroup && !isOutgoing) { ... }`), not the
// exact per-run on/off flag. That's coarser than the real prop (it doesn't
// distinguish first/last-of-run within a group), but it is still a genuine
// structural fork: private-chat and outgoing rows never have this branch at
// all, group incoming rows always do.
function hasAvatarBranch(data: MessageBubbleRenderData, msg: MessageEntry): boolean {
  return data.isGroup && !msg.isOutgoing;
}

// Same substitution as hasAvatarBranch, for the sender-name line
// (MessageBubble.ets ~3494: `if (isGroup && !isOutgoing && senderName !== '' &&
// showSenderName)`). showSenderName itself is unavailable here for the same
// reason, so this checks only the preconditions that are visible from a
// single MessageEntry.
function hasSenderNameBranch(data: MessageBubbleRenderData, msg: MessageEntry): boolean {
  return data.isGroup && !msg.isOutgoing && msg.senderName !== '';
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

function mediumBucket(data: MessageBubbleRenderData, msg: MessageEntry): string {
  const avatar: string = hasAvatarBranch(data, msg) ? 'avatar' : 'no-avatar';
  const senderName: string = hasSenderNameBranch(data, msg) ? 'sender' : 'no-sender';
  const reply: string = hasReplyBlock(msg) ? 'reply' : 'no-reply';
  const forward: string = hasForwardHeader(msg) ? 'forward' : 'no-forward';
  const reactions: string = hasReactionBar(msg) ? 'reactions' : 'no-reactions';
  return `${coarseBucket(data)}:${avatar}:${senderName}:${reply}:${forward}:${reactions}`;
}

// contentType values are enumerated from every `contentType === '...'` check
// in the codebase (store/MessageEntry.ets, pages/chat, util). Mapping choices
// that are not a literal file-kind match:
// - 'system' / 'hidden' fold into 'none': they render centered service pills
//   with no media slot, structurally closer to a medialess text row than to
//   any of the four media buckets.
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
    case 'text':
    case 'system':
    case 'hidden':
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

function fineBucket(data: MessageBubbleRenderData, msg: MessageEntry): string {
  return `${mediumBucket(data, msg)}:${mediaKind(msg)}`;
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
export function rowReuseId(data: MessageBubbleRenderData, msg: MessageEntry, level: ReuseIdLevel): string {
  if (level === 'coarse') {
    return coarseBucket(data);
  }
  if (level === 'medium') {
    return mediumBucket(data, msg);
  }
  return fineBucket(data, msg);
}
