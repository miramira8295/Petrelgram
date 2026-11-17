import { AlbumCell } from './packAlbumRows';

// Physical rectangles for Telegram Android GroupedMessages' 2/3/4 special
// cases (21f7d109). RecyclerView spanSize/leftSpanOffset are not pixel bounds.
// Adapt to the allocated vp width and 2vp gutters; cap minimum widths on narrow
// panes and fill the left column so no RecyclerView-only spacer leaks into UI.
// Constant work, at most four cells. Null selects Android's general algorithm.
export function androidSmallAlbumGeometry(ratios: number[], width: number): AlbumCell[][] | null {
  if (ratios.length < 2 || ratios.length > 4 || width <= 6 || !Number.isFinite(width)) { return null; }
  const r: number[] = [];
  let sum = 1;
  for (const raw of ratios) {
    const ratio = Number.isFinite(raw) && raw > 0 ? raw : 1;
    if (ratio > 2) { return null; }
    r.push(ratio); sum += ratio;
  }
  const gap = 2;
  const hMax = width * 814 / 800;
  const minWidth = Math.min(120, (width - gap) * 0.4);
  const minHeight = Math.min(100, hMax / 3);
  const cells: AlbumCell[] = [];
  const add = (idx: number, x: number, y: number, w: number, h: number): void => {
    cells.push({ idx, x, y, width: w, height: h });
  };
  const wide = (ratio: number): boolean => ratio > 1.2;
  const square = (ratio: number): boolean => ratio >= 0.8 && ratio <= 1.2;
  if (r.length === 2) {
    if (wide(r[0]) && wide(r[1]) && sum / 2 > 1.4 * 800 / 814 && r[0] - r[1] < 0.2) {
      const h = Math.min(width / r[0], width / r[1], (hMax - gap) / 2);
      add(0, 0, 0, width, h); add(1, 0, h + gap, width, h);
    } else {
      const available = width - gap;
      let left = available / 2;
      if (!(wide(r[0]) && wide(r[1])) && !(square(r[0]) && square(r[1]))) {
        const right = Math.max(available * 0.4, available / r[0] / (1 / r[0] + 1 / r[1]));
        left = Math.max(minWidth, available - right);
      }
      const right = available - left;
      const h = Math.min(hMax, left / r[0], right / r[1]);
      add(0, 0, 0, left, h); add(1, left + gap, 0, right, h);
    }
  } else if (r.length === 3 && r[0] < 0.8) {
    const bottom = Math.min((hMax - gap) / 2, r[1] * width / (r[2] + r[1]));
    const top = hMax - gap - bottom;
    const right = Math.max(minWidth, Math.min((width - gap) / 2, bottom * r[2], top * r[1]));
    const left = width - gap - right;
    add(0, 0, 0, left, hMax);
    add(1, left + gap, 0, right, top); add(2, left + gap, top + gap, right, bottom);
  } else if (r.length === 3 || wide(r[0])) {
    const top = Math.min(width / r[0], hMax * 0.66);
    add(0, 0, 0, width, top);
    if (r.length === 3) {
      const w = (width - gap) / 2;
      const h = Math.max(minHeight, Math.min(w / r[1], w / r[2], hMax - top - gap));
      add(1, 0, top + gap, w, h); add(2, w + gap, top + gap, w, h);
    } else {
      const available = width - gap * 2;
      const natural = available / (r[1] + r[2] + r[3]);
      const minimum = Math.min(minWidth, available / 3);
      let left = Math.max(minimum, Math.min(available * 0.4, natural * r[1]));
      let right = Math.max(minimum, available * 0.33, natural * r[3]);
      let middle = available - left - right;
      const middleMinimum = Math.min(58, available / 3);
      if (middle < middleMinimum) {
        const difference = middleMinimum - middle;
        left -= difference / 2; right -= difference / 2; middle = middleMinimum;
      }
      const h = Math.max(minHeight, Math.min(natural, hMax - top - gap));
      add(1, 0, top + gap, left, h);
      add(2, left + gap, top + gap, middle, h);
      add(3, left + middle + gap * 2, top + gap, right, h);
    }
  } else {
    const right = Math.min((width - gap) * 0.6,
      Math.max(minWidth, hMax / (1 / r[1] + 1 / r[2] + 1 / r[3])));
    const left = width - gap - right;
    const available = hMax - gap * 2;
    const top = Math.min(available * 0.33, Math.max(Math.min(120, available / 3), right / r[1]));
    const middle = Math.min(available * 0.33, Math.max(Math.min(120, available / 3), right / r[2]));
    add(0, 0, 0, left, hMax);
    add(1, left + gap, 0, right, top);
    add(2, left + gap, top + gap, right, middle);
    add(3, left + gap, top + middle + gap * 2, right, available - top - middle);
  }
  // A transport batch, not a horizontal row. Explicit coordinates are consumed
  // only by the drawn grid; legacy fixed row slots never request this mode.
  return [cells];
}
