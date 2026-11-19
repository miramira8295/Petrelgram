import { TdObject } from '../tdkit/TdTypes';
import { ReactionInfo } from '../store/MessageEntry';

export interface ReactionSender { id: number; user: boolean; key: string; }

// TDLib provides at most three recent senders. Bound even malformed input;
// never fetch a member list to decorate a chip. Stable order prevents swaps.
export function parseReactionSenders(raw: TdObject[] | undefined): ReactionSender[] {
  const result: ReactionSender[] = [];
  if (raw === undefined) { return result; }
  const seen: Set<string> = new Set();
  for (let i = 0; i < Math.min(3, raw.length); i++) {
    const sender = raw[i], type = sender['@type'];
    const user = type === 'messageSenderUser';
    if (!user && type !== 'messageSenderChat') { continue; }
    const id = (sender[user ? 'user_id' : 'chat_id'] as number | undefined) ?? 0;
    if (!Number.isSafeInteger(id) || (user ? id <= 0 : id === 0)) { continue; }
    const key = `${user ? 'u' : 'c'}${id}`;
    if (seen.has(key)) { continue; }
    seen.add(key); result.push({ id, user, key });
  }
  result.sort((a: ReactionSender, b: ReactionSender): number => a.id - b.id || (a.user ? 1 : 0) - (b.user ? 1 : 0));
  return result;
}

export function reactionTotal(reactions: ReactionInfo[]): number {
  let total = 0;
  for (const reaction of reactions) { total += reaction.count; }
  return total;
}

// Android: private chats may show peer avatars regardless of other chips;
// groups use avatars only while the message total is <=3. Require the complete
// identities so we never hide a larger/anonymous count behind partial avatars.
export function reactionAvatarCount(reaction: ReactionInfo, total: number, channel: boolean, privateChat: boolean): number {
  if (channel || reaction.areTags || reaction.isPaid || (!privateChat && total > 3) ||
    reaction.count < 1 || reaction.count > 3 || reaction.recentSenders?.length !== reaction.count) { return 0; }
  return reaction.count;
}
export function reactionAvatarWidth(count: number): number { return count > 0 ? 23 + (count - 1) * 16 : 0; }
