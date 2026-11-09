// 富文本表格的列宽（issue: 表格整块不显示）。
//
// 【为什么不量文本，而是估算】RichMessageView.blocks() 每次 build 都重新解析
// 一遍块，表格若再按格调一次 measureTextSize，就是每帧一把同步测量。这里用
// 估算换掉测量：列宽只要**各行一致、看着合理**就够了，差几个像素不影响可读性，
// 而估算是纯函数、测得住、零渲染开销。
//
// 【为什么必须有列宽这个概念】表格是「一列 Column 装若干 Row」画出来的，
// 行与行之间没有任何天然对齐关系——不给每格钉死同一个列宽，第二行的边界
// 就不会落在第一行的边界上，看着就不是一张表。
export const TABLE_CELL_PAD_VP: number = 20;   // 单元格左右内边距合计
export const TABLE_COL_MIN_VP: number = 48;
// 上限是必须的：一个长句子能把某一列撑到几千 vp，横滑几屏才看得完。
// 超过上限的单元格在格子内部换行。
export const TABLE_COL_MAX_VP: number = 200;

// 半角字符相对字号的平均宽度。0.55 是拉丁文常见的经验值（等宽字体接近 0.6，
// 比例字体因为 i/l/空格拉低平均，取 0.55 略保守——宁可略宽也不要截断）。
const NARROW_RATIO: number = 0.55;

// 一个**码元**占几个字号宽。三档，不是两档：
//   1.0  宽字符（CJK / 全角 / 谚文），以及代理对的**高位**；
//   0    代理对的低位——一个 emoji 由高低两个码元组成，低位再计一次宽就把它
//        算成了一个汉字加半个字母（真机上这条最早写成 false = 0.55，
//        '😀' 估出 1.55 个字号，被用例抓到）；
//   0.55 其余（拉丁、数字、标点）。
function charWidthFactor(code: number): number {
  if (code >= 0xD800 && code <= 0xDBFF) {
    return 1;
  }
  if (code >= 0xDC00 && code <= 0xDFFF) {
    return 0;
  }
  const wide: boolean = (code >= 0x1100 && code <= 0x115F) ||   // 谚文字母
    (code >= 0x2E80 && code <= 0xA4CF) ||        // CJK 部首 … 彝文
    (code >= 0xAC00 && code <= 0xD7A3) ||        // 谚文音节
    (code >= 0xF900 && code <= 0xFAFF) ||        // CJK 兼容
    (code >= 0xFE30 && code <= 0xFE4F) ||        // CJK 兼容形式
    (code >= 0xFF00 && code <= 0xFF60) ||        // 全角
    (code >= 0xFFE0 && code <= 0xFFE6);
  return wide ? 1 : NARROW_RATIO;
}

export function textWidthEstimate(text: string, fontSize: number): number {
  if (text === '' || fontSize <= 0) {
    return 0;
  }
  let units: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    units += charWidthFactor(text.charCodeAt(i));
  }
  return units * fontSize;
}

// 每列多宽。rows 是逐行的单元格文本，行长可以不齐（缺的格按 0 宽算）。
export function tableColumnWidths(rows: string[][], fontSize: number,
  min: number = TABLE_COL_MIN_VP, max: number = TABLE_COL_MAX_VP,
  pad: number = TABLE_CELL_PAD_VP): number[] {
  let columns: number = 0;
  for (const row of rows) {
    if (row.length > columns) {
      columns = row.length;
    }
  }
  const widths: number[] = [];
  for (let c: number = 0; c < columns; c++) {
    let widest: number = 0;
    for (const row of rows) {
      if (c >= row.length) {
        continue;
      }
      const w: number = textWidthEstimate(row[c], fontSize);
      if (w > widest) {
        widest = w;
      }
    }
    const withPad: number = widest + pad;
    widths.push(Math.round(Math.max(min, Math.min(max, withPad))));
  }
  return widths;
}

// 内容总宽。渲染侧据此判断「要不要能横滑」——不超过气泡宽度时不该出现滚动，
// 否则会和气泡自己的左滑回复抢手势。
export function tableContentWidth(widths: number[]): number {
  let total: number = 0;
  for (const w of widths) {
    total += w;
  }
  return total;
}
