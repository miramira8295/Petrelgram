// 聊天页「悬浮件」的外描边：顶栏胶囊（返回 / 身份 / 菜单）与底栏（输入框、操作条）。
//
// 历史：暗色下一直是 1px 白 20% 的描边，亮色下把宽度写成了 0（即"没有描边"），
// 于是亮色里这些半透明玻璃块只剩底+模糊，边缘发虚、和背景糊在一起。
// 这里统一成两边都有 1px 细线，只是颜色按主题取：
//   · 暗色：白 20%，提亮轮廓（与底色同向，不会显脏）
//   · 亮色：黑 10%，压出边界（比纯灰更贴近玻璃的分界感，也不会抢字色）
//
// 用 border 而不是 outline：这五处的圆角裁剪（clip）本来就跟 border 同一条
// 边界，换成 outline 会多出一圈描边在裁剪之外；1px 内缩在暗色下已经跑了很久，
// 亮色沿用同一条，不会带来新的位移。
export const CHROME_OUTLINE_WIDTH: number = 1;
const OUTLINE_DARK: string = '#33FFFFFF';
const OUTLINE_LIGHT: string = '#3D000000';

export interface ChromeOutline {
  width: number;
  color: ResourceColor;
  style: BorderStyle;
}

export function chromeOutline(appDark: boolean): ChromeOutline {
  return {
    width: CHROME_OUTLINE_WIDTH,
    color: appDark ? OUTLINE_DARK : OUTLINE_LIGHT,
    style: BorderStyle.Solid
  };
}
