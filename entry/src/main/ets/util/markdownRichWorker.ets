import { MarkdownRichDraft, parseMarkdownRichDraft } from './markdownRichInput';

// Concurrent entry points may capture imports and arguments only. Keep the
// iterative parser helpers in their imported module, never this worker scope.
@Concurrent
export function parseMarkdownRichWorker(raw: string): MarkdownRichDraft {
  return parseMarkdownRichDraft(raw);
}
