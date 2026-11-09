import { BreakpointType } from './layoutBreakpoint';

// 页面边距：卡片外沿离屏幕边（官方多设备适配规格 SPEC-07，2026-09-23 用户定）。
//
// 【同应用不同页面一致】手机上统一 12：联系人、设置、「我的」本来就是 12，
// 个人资料 / 群资料从 14 收到 12。**首页会话卡片例外，保留 6**——那是 09-18 有意
// 收窄、换卡片内四周 8vp 均匀留白的结果（见 util/listCardGeometry）。
// 【同应用不同端】按系统横向断点加宽：折叠屏展开（md）+4，平板（lg 起）+8。
// 不分栏的大屏页面另有限宽居中（util/contentWidth），这里只管卡片离内容区边缘多远。
//
// P0「左边距 ≤ 屏宽 20%」：最大的 20vp 放在最窄的 lg 窗口 840vp 上也只有 2.4%。

export const PAGE_MARGIN_PHONE_VP: number = 12;
export const HOME_CARD_MARGIN_PHONE_VP: number = 6;

const PAGE_MARGIN: BreakpointType<number> = new BreakpointType<number>(
  PAGE_MARGIN_PHONE_VP, PAGE_MARGIN_PHONE_VP + 4, PAGE_MARGIN_PHONE_VP + 8);
const HOME_CARD_MARGIN: BreakpointType<number> = new BreakpointType<number>(
  HOME_CARD_MARGIN_PHONE_VP, HOME_CARD_MARGIN_PHONE_VP + 4, HOME_CARD_MARGIN_PHONE_VP + 8);

export function pageMarginVp(widthBp: number): number {
  return PAGE_MARGIN.getValue(widthBp);
}

export function homeCardMarginVp(widthBp: number): number {
  return HOME_CARD_MARGIN.getValue(widthBp);
}
