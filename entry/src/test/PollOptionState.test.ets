import { describe, expect, it } from '@ohos/hypium';
import { PollOptionStateInput, pollOptionState } from '../main/ets/util/pollOptionState';

function answer(): PollOptionStateInput {
  return { isQuiz: true, resultsVisible: true, correctOptionId: -1,
    optionCount: 3, index: 0, chosen: true, selected: true, submitting: false };
}

export default function pollOptionStateTest() {
  describe('PollOptionState', () => {
    it('accepted_answer_without_revealed_key_is_not_wrong', 0, () => {
      const input: PollOptionStateInput = answer();
      expect(pollOptionState(input)).assertEqual('selected');
      input.correctOptionId = 0;
      expect(pollOptionState(input)).assertEqual('correct');
    });
    it('wrong_answer_and_unchosen_correct_answer_have_distinct_marks', 0, () => {
      const input: PollOptionStateInput = answer();
      input.correctOptionId = 1;
      expect(pollOptionState(input)).assertEqual('wrong');
      input.index = 1; input.chosen = false; input.selected = false;
      expect(pollOptionState(input)).assertEqual('correct');
      input.index = 2;
      expect(pollOptionState(input)).assertEqual('neutral');
    });
    it('quiz_draft_and_request_in_flight_are_not_verdicts', 0, () => {
      const input: PollOptionStateInput = answer();
      input.chosen = false; input.resultsVisible = false; input.correctOptionId = 0;
      expect(pollOptionState(input)).assertEqual('selected');
      input.submitting = true;
      expect(pollOptionState(input)).assertEqual('pending');
    });
    it('invalid_answer_ids_do_not_mark_selected_answer_wrong', 0, () => {
      const input: PollOptionStateInput = answer();
      for (const id of [-1, 3, 100, 0.5, Number.NaN]) {
        input.correctOptionId = id;
        expect(pollOptionState(input)).assertEqual('selected');
      }
    });
    it('closed_unanswered_quiz_reveals_only_the_correct_option', 0, () => {
      const input: PollOptionStateInput = answer();
      input.chosen = false; input.selected = false;
      expect(pollOptionState(input)).assertEqual('neutral');
      input.correctOptionId = 0;
      expect(pollOptionState(input)).assertEqual('correct');
    });
    it('regular_poll_selection_is_not_quiz_correctness', 0, () => {
      const input: PollOptionStateInput = answer();
      input.isQuiz = false; input.correctOptionId = 1;
      expect(pollOptionState(input)).assertEqual('vote');
      input.selected = false; input.chosen = false;
      expect(pollOptionState(input)).assertEqual('neutral');
    });
    it('authoritative_answer_wins_over_lingering_pending_state', 0, () => {
      const input: PollOptionStateInput = answer();
      input.submitting = true; input.correctOptionId = 0;
      expect(pollOptionState(input)).assertEqual('correct');
      input.correctOptionId = 2;
      expect(pollOptionState(input)).assertEqual('wrong');
    });
  });
}
