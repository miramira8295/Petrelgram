// Pack album media into stable Telegram-style mosaic rows. Cell widths still
// respect source ratios, but extreme portraits/panoramas are clamped so a last
// row can never become an enormous tower or a paper-thin strip.

export interface AlbumCell {
  idx: number;
  width: number;
  height: number;
}

// 越界时顶替真实格子的空格子。0×0 意味着它什么都不画，而 idx = -1 让
// AlbumCellView 里那几个 `group.photoXxx[idx] ?? 兜底` 自然落到兜底分支上。
// **只读**，全应用共用这一个实例，谁都不许改它的字段。
export const EMPTY_ALBUM_CELL: AlbumCell = { idx: -1, width: 0, height: 0 };

// 按行列取格子的**全函数**版本：越界返回 EMPTY_ALBUM_CELL，绝不返回 undefined。
//
// 【为什么渲染侧不能直接写 rows[r][c]】MessageBubble.albumGrid 是固定槽位，每个
// 槽位外面包着一层 `if (rows[r].length > c)`。行复用时 ArkUI 会对**已经存在的**
// 子组件重跑它的 paramsLambda 把新参数推进去，却**不会**重新求值那些 if。于是一行
// 原本画三行相册的气泡被复用去画一张图的消息时，残留槽位仍按旧的行列去索引已经
// 换成新相册的 rows：
//   · rows[2] 不存在 → 对 undefined 取 .length / [0]，抛
//     "Cannot load property of null or undefined"；
//   · 行在、列不在 → cell 成了 undefined → AlbumCellView.idx() 的 this.cell.idx
//     抛 "Cannot read property idx of undefined"。
// 这两条是崩溃上报里排第一的那一类（1.4.5 起 46 条，栈顶恒为
// paramsLambda ← aboutToReuseInternal）。守卫本身保留——正常构建那一趟它仍然是
// 对的，也仍然决定建不建节点；这里只是让索引变成全函数，复用期间那一帧不至于
// 把进程带走。
export function albumCellAt(rows: AlbumCell[][], row: number, col: number): AlbumCell {
  if (!Number.isInteger(row) || row < 0 || row >= rows.length) {
    return EMPTY_ALBUM_CELL;
  }
  const cells: AlbumCell[] = rows[row];
  return Number.isInteger(col) && col >= 0 && col < cells.length ? cells[col] : EMPTY_ALBUM_CELL;
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
