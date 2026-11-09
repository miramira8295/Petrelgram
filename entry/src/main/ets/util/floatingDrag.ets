// Pure math for dragging the live floating window. The overlay keeps the
// player anchored by layout (bottom-right) and moves it with a translation;
// these helpers keep that translation inside the visible bounds.

export interface FloatingDragAnchor {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface FloatingDragBounds {
  width: number;
  height: number;
  margin: number;
}

export interface FloatingDragPoint {
  x: number;
  y: number;
}

function clampAxis(
  translation: number, anchorStart: number, anchorSize: number,
  boundsSize: number, margin: number
): number {
  const min = margin - anchorStart;
  const max = boundsSize - margin - anchorSize - anchorStart;
  // When the window is larger than the available space, pin its start edge to
  // the margin instead of oscillating between impossible limits.
  if (max < min) { return min; }
  return Math.min(max, Math.max(min, translation));
}

export function clampFloatingTranslation(
  translateX: number, translateY: number,
  anchor: FloatingDragAnchor, bounds: FloatingDragBounds
): FloatingDragPoint {
  return {
    x: clampAxis(translateX, anchor.x, anchor.width, bounds.width, bounds.margin),
    y: clampAxis(translateY, anchor.y, anchor.height, bounds.height, bounds.margin)
  };
}

export function dragFloatingTranslation(
  startX: number, startY: number, offsetX: number, offsetY: number,
  anchor: FloatingDragAnchor, bounds: FloatingDragBounds
): FloatingDragPoint {
  return clampFloatingTranslation(startX + offsetX, startY + offsetY, anchor, bounds);
}
