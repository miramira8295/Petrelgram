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

interface AlbumCanvasAnchorHandoff {
  messageId: number;
  release: () => void;
  accepted: boolean;
}
let albumAnchorOpening: AlbumCanvasAnchorHandoff | null = null;

// A measured, temporary native source can use the viewer's existing shared
// element path. Ownership crosses the synchronous open boundary exactly once.
export function withAlbumCanvasAnchor(messageId: number, release: () => void, open: () => void): boolean {
  const previous = albumAnchorOpening;
  const handoff: AlbumCanvasAnchorHandoff = { messageId, release, accepted: false };
  albumAnchorOpening = handoff;
  try { open(); return handoff.accepted; }
  finally { albumAnchorOpening = previous; }
}

export function takeAlbumCanvasAnchor(messageId: number): (() => void) | null {
  const handoff = albumAnchorOpening;
  if (handoff === null || handoff.messageId !== messageId || handoff.accepted) { return null; }
  handoff.accepted = true;
  return handoff.release;
}
