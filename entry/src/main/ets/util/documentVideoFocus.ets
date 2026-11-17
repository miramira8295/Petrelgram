// User-started embedded videos share one active owner. Starting another stops
// the previous one before mounting a new player. O(1), no scan of message rows.
let stopActive: (() => void) | null = null;
export function claimDocumentVideo(stop: () => void): () => void {
  const previous = stopActive;
  stopActive = stop;
  if (previous !== null && previous !== stop) { previous(); }
  return (): void => { if (stopActive === stop) { stopActive = null; } };
}
