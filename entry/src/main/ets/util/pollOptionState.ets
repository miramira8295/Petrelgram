// Quiz correctness comes only from a revealed, valid answer id. A selected
// answer and a vote percentage are not evidence of correctness.
export interface PollOptionStateInput {
  isQuiz: boolean;
  resultsVisible: boolean;
  correctOptionId: number;
  optionCount: number;
  index: number;
  chosen: boolean;
  selected: boolean;
  submitting: boolean;
}

export function pollOptionState(input: PollOptionStateInput): string {
  const revealed: boolean = input.isQuiz && input.resultsVisible &&
    Number.isInteger(input.correctOptionId) && input.correctOptionId >= 0 &&
    input.correctOptionId < input.optionCount;
  if (revealed && input.index === input.correctOptionId) { return 'correct'; }
  if (revealed && input.chosen) { return 'wrong'; }
  if (input.selected) {
    if (input.submitting) { return 'pending'; }
    return input.isQuiz ? 'selected' : 'vote';
  }
  return 'neutral';
}
