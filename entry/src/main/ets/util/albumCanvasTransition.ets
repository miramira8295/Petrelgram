// Synchronous action handoff only. No retained message IDs, timer or cross-page
// event. ChatPage already forwards onMediaTap synchronously to the viewer.
let albumCanvasOpening: number | null = null;

export function withAlbumCanvasTransition(messageId: number, open: () => void): void {
  const previous = albumCanvasOpening;
  albumCanvasOpening = messageId;
  try { open(); } finally { albumCanvasOpening = previous; }
}

export function albumCanvasTransitionFor(messageId: number): boolean {
  return albumCanvasOpening === messageId;
}
