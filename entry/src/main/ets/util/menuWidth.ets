// 下拉菜单该多宽。
//
// 【为什么需要算】菜单宽度原来是写死的 176，那个数是**按中文六个字手算**出来的：
// 左右内边距 16×2 + 图标 19 + 图标与文字间距 14 + 最长中文标签 6 字 ×16 ≈ 161，
// 再留 15 的余量。两个问题：
//   ① 拉丁语系里最长的那几条（Updating notifications）在 176 甚至 224 上都会折行；
//   ② 加一个尾部箭头（子菜单的 ▸）就多占 28，六个字立刻放不下——用户实测
//      「添加到文件夹」折行了。
//
// ArkUI 这边没有"父容器按最宽的孩子撑开、其余孩子拉伸对齐"的现成写法能安全用在
// promptAction.openMenu 的 ComponentContent 上（菜单尺寸在弹出那一刻量定，
// 内部再变高变宽都不会重新量，这一点在 ChatHeaderMenuParams.panel 上有实测记录）。
// 所以宽度必须在**构建之前**算出来。
//
// 这是个**估算**，不是精确排版：按字符类别给经验宽度，宁可宽一点也不折行。
// 纯函数，可单测。

// 单个字符的经验宽度（fontSize 16）。
const CJK_W: number = 16;      // 中日韩：全角，约等于字号
const WIDE_W: number = 13;     // 大写拉丁 / 数字：偏宽
const NARROW_W: number = 8;    // 小写拉丁与其余：偏窄

// 行的固定开销：左右内边距 16×2 + 图标 19 + 图标与文字间距 14。
export const MENU_ROW_CHROME: number = 16 * 2 + 19 + 14;
// 尾部箭头（子菜单指示）占的宽：箭头 14 + 它与文字的间距 14。
export const MENU_TRAILING_CHEVRON: number = 14 + 14;

// 上下限。下限保住原来的观感（短菜单不至于窄成一条），上限防止某个语言
// 的超长标签把菜单撑到整屏。
export const MENU_MIN_W: number = 176;
export const MENU_MAX_W: number = 280;

function charWidth(code: number): number {
  // CJK 统一表意文字 + 假名 + 谚文 + 全角标点，全部按全角算。
  if ((code >= 0x2E80 && code <= 0xA4CF) || (code >= 0xAC00 && code <= 0xD7A3) ||
    (code >= 0xF900 && code <= 0xFAFF) || (code >= 0xFF00 && code <= 0xFF60)) {
    return CJK_W;
  }
  // 大写拉丁与数字
  if ((code >= 0x41 && code <= 0x5A) || (code >= 0x30 && code <= 0x39)) {
    return WIDE_W;
  }
  return NARROW_W;
}

export function textWidth(label: string): number {
  let w: number = 0;
  for (let i = 0; i < label.length; i++) {
    w += charWidth(label.charCodeAt(i));
  }
  return w;
}

// 菜单宽度 = 最宽的一行 + 固定开销，夹在上下限之间。
// hasChevron 为真表示菜单里**存在**带尾部箭头的行——箭头只占那一行，但宽度是
// 整个菜单共用的，所以按最坏情况留。
export function menuWidthFor(labels: string[], hasChevron: boolean = false): number {
  let widest: number = 0;
  for (const label of labels) {
    const w: number = textWidth(label);
    if (w > widest) {
      widest = w;
    }
  }
  const raw: number = Math.ceil(widest) + MENU_ROW_CHROME +
    (hasChevron ? MENU_TRAILING_CHEVRON : 0);
  if (raw < MENU_MIN_W) {
    return MENU_MIN_W;
  }
  return raw > MENU_MAX_W ? MENU_MAX_W : raw;
}
