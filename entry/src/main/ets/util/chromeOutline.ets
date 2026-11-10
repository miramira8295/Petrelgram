// 聊天页「悬浮件」的外描边：顶栏胶囊（返回 / 身份 / 菜单）、底部输入卡与附件/麦克风钮、
// 顶栏下那张浮卡（操作条 + 置顶条 + 直播条共用）。
//
// 历史：暗色下一直是 1px 白线，亮色下把宽度写成了 0（等于没有描边），亮色里这些
// 半透明玻璃块边缘发虚、和背景糊在一起。
//
// 现在的口径（2026-11-10 定稿）：**单一 1px 线，按主题取色**
//   · 亮色：白线 #33FFFFFF —— 浅壁纸上是"玻璃高光"，深壁纸上是亮边
//   · 暗色：灰线 #5CC0C0C0 —— 中性灰比纯黑/纯白都稳；2026-11-10 提亮一档
//     （原 #4D9E9E9E 在深壁纸上偏暗、几乎读不出边界），提的是灰的亮度与不透明度各一点
// 用 border 而不是 outline：这几处的 clip 与 border 是同一条圆角边界，换 outline
// 会多一圈画在裁剪之外；1px 内缩在暗色下已经跑了很多版本，亮色沿用不会带来位移。
export interface ChromeOutline {
  width: number;
  color: ResourceColor;
  style: BorderStyle;
}

const OUTLINE_DARK: string = '#5CC0C0C0';
const OUTLINE_LIGHT: string = '#33FFFFFF';

export function chromeOutline(appDark: boolean): ChromeOutline {
  return { width: 1, color: appDark ? OUTLINE_DARK : OUTLINE_LIGHT, style: BorderStyle.Solid };
}
