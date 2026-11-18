import { PollOptionInfo } from './formatMsgContent';

// O(K) expected, preserving caller order; reject fractional/non-finite IDs.
export function pollVoteIds(ids: number[], count: number): number[] {
  const seen = new Set<number>();
  const result: number[] = [];
  for (const id of ids) {
    if (Number.isInteger(id) && id >= 0 && id < count && !seen.has(id)) {
      seen.add(id); result.push(id);
    }
  }
  return result;
}

// O(N), with O(1) expected membership. Keep text/entity references and untouched
// options. The prior array remains a valid immutable rollback snapshot.
export function pollVoteOptions(options: PollOptionInfo[], selected: ReadonlySet<number>, pending: boolean): PollOptionInfo[] {
  let result: PollOptionInfo[] | null = null;
  for (let i = 0; i < options.length; i++) {
    const option = options[i], chosen = selected.has(i);
    const isChosen = pending ? option.isChosen : chosen;
    const isBeingChosen = pending && chosen;
    if (option.isChosen === isChosen && option.isBeingChosen === isBeingChosen) { continue; }
    if (result === null) { result = options.slice(); }
    result[i] = { text: option.text, entities: option.entities, voterCount: option.voterCount,
      votePercentage: option.votePercentage, isChosen, isBeingChosen };
  }
  return result ?? options;
}
