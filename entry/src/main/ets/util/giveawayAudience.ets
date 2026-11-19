import { TdObject } from '../tdkit/TdTypes';

// Immutable after parsing, shared by message clones. Byte/progress/state
// updates never rescan participant IDs or rebuild the content signature.
export interface GiveawayAudience {
  chatIds: number[];
  winnerUserIds: number[];
  signature: string;
}

function appendGiveawayIds(input: number[] | undefined, users: boolean, output: number[], seen: Set<number>): void {
  if (input === undefined) { return; }
  for (const id of input) {
    if (!Number.isSafeInteger(id) || (users ? id <= 0 : id === 0) || seen.has(id)) { continue; }
    seen.add(id); output.push(id);
  }
}

// TDLib's active giveaway carries boosted+additional chats; the public results
// carry the boosted chat and winner_user_ids. O(C+U) time/space, stable order.
// Service/completed/prize variants deliberately keep their current behavior.
export function giveawayAudienceOf(content: TdObject | undefined): GiveawayAudience | undefined {
  const kind = content?.['@type'];
  if (kind !== 'messageGiveaway' && kind !== 'messageGiveawayWinners') { return undefined; }
  const params = kind === 'messageGiveaway' ? content?.['parameters'] as TdObject | undefined : content;
  const boosted = params?.['boosted_chat_id'] as number | undefined;
  const chatIds: number[] = [], winnerUserIds: number[] = [];
  const seenChats = new Set<number>();
  if (boosted !== undefined && Number.isSafeInteger(boosted) && boosted !== 0) { seenChats.add(boosted); chatIds.push(boosted); }
  if (kind === 'messageGiveaway') {
    appendGiveawayIds(params?.['additional_chat_ids'] as number[] | undefined, false, chatIds, seenChats);
  } else {
    appendGiveawayIds(content?.['winner_user_ids'] as number[] | undefined, true, winnerUserIds, new Set<number>());
  }
  return { chatIds, winnerUserIds, signature: `c:${chatIds.join(',')}|u:${winnerUserIds.join(',')}` };
}
