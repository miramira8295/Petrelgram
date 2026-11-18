import { PollOptionInfo } from './formatMsgContent';

export interface PollSelectionSummary {
  chosenIds: number[];
  texts: string[];
  pending: boolean;
}

// A single linear pass per options snapshot, shared by all option cells.
export function summarizePollOptions(options: PollOptionInfo[]): PollSelectionSummary {
  const chosenIds: number[] = [], texts: string[] = [];
  let pending: boolean = false;
  for (let i = 0; i < options.length; i++) {
    const option = options[i];
    if (option.isChosen) { chosenIds.push(i); }
    if (option.isBeingChosen) { pending = true; }
    texts.push(option.text);
  }
  return { chosenIds, texts, pending };
}

function samePollNumbers(a: number[], b: number[]): boolean {
  if (a.length !== b.length) { return false; }
  for (let i = 0; i < a.length; i++) { if (a[i] !== b[i]) { return false; } }
  return true;
}
function samePollTexts(a: string[], b: string[]): boolean {
  if (a.length !== b.length) { return false; }
  for (let i = 0; i < a.length; i++) { if (a[i] !== b[i]) { return false; } }
  return true;
}

// Local unsent choices survive unrelated vote-count updates. Reset only for a
// new owner/content, authoritative selection change, request completion/error,
// or closure. Retains only the previous snapshot, not a history of messages.
export class PollDraftSync {
  private rowId: number = -1;
  private pollId: string = '';
  private previous: PollSelectionSummary | null = null;
  private pending: boolean = false;
  private error: string = '';
  private closed: boolean = false;

  update(rowId: number, pollId: string, current: PollSelectionSummary,
    pending: boolean, error: string, closed: boolean): boolean {
    const previous = this.previous;
    const reset = this.rowId !== rowId || this.pollId !== pollId || previous === null ||
      !samePollTexts(previous.texts, current.texts) || !samePollNumbers(previous.chosenIds, current.chosenIds) ||
      (this.pending && !pending) || this.error !== error || this.closed !== closed;
    this.rowId = rowId; this.pollId = pollId; this.previous = current;
    this.pending = pending; this.error = error; this.closed = closed;
    return reset;
  }
}
