// Pack album media into stable Telegram-style mosaic rows. Cell widths still
// respect source ratios, but extreme portraits/panoramas are clamped so a last
// row can never become an enormous tower or a paper-thin strip.

export interface AlbumCell {
  idx: number;
  width: number;
  height: number;
}

const CELL_GAP: number = 2;

// 渲染侧给相册留的固定行槽位数（见 MessageBubble.albumGrid —— 它刻意不用
// ForEach）。Telegram 相册上限 10 张，presets 最多排到 4 行；fallback 分支每行
// 也最多 3 格。6 是留给意外的余量，不是策略。
export const ALBUM_ROW_SLOTS: number = 6;
// 一行最多几格（presets 与 fallback 都是 3）。
export const ALBUM_ROW_MAX_CELLS: number = 3;

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function rowSizes(total: number): number[] {
  if (total <= 0) {
    return [];
  }
  const presets: number[][] = [
    [], [1], [2], [1, 2], [2, 2], [2, 3], [3, 3],
    [2, 2, 3], [2, 3, 3], [3, 3, 3], [2, 2, 3, 3]
  ];
  if (total < presets.length) {
    return presets[total];
  }
  const sizes: number[] = [];
  let remain = total;
  while (remain > 0) {
    if (remain === 4) {
      sizes.push(2, 2);
      break;
    }
    sizes.push(Math.min(3, remain));
    remain -= Math.min(3, remain);
  }
  return sizes;
}

export function packAlbumRows(ratios: number[], targetWidth: number): AlbumCell[][] {
  const rows: AlbumCell[][] = [];
  const sizes = rowSizes(ratios.length);
  let index = 0;
  for (const count of sizes) {
    const available = Math.max(1, targetWidth - CELL_GAP * (count - 1));
    const weights: number[] = [];
    let weightSum = 0;
    for (let i = 0; i < count; i++) {
      const raw = ratios[index + i] > 0 ? ratios[index + i] : 1;
      const weight = clamp(raw, 0.65, 1.8);
      weights.push(weight);
      weightSum += weight;
    }
    const minHeight = count === 1 ? 132 : (count === 2 ? 105 : 90);
    const maxHeight = count === 1 ? 188 : (count === 2 ? 165 : 140);
    const height = clamp(available / Math.max(0.1, weightSum), minHeight, maxHeight);
    const row: AlbumCell[] = [];
    let usedWidth = 0;
    for (let i = 0; i < count; i++) {
      const width = i === count - 1
        ? available - usedWidth
        : Math.round(available * weights[i] / weightSum);
      row.push({ idx: index + i, width, height });
      usedWidth += width;
    }
    rows.push(row);
    index += count;
  }
  return rows;
}
