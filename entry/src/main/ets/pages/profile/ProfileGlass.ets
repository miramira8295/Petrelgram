// 群组与个人资料页共用的几何参数。卡片填充与气泡使用同一透明度方案，
// 卡片本身不附加模糊或阴影；头像框保留独立装饰。

// 卡片圆角。设计里三档：整块列表 26、方格 22、药丸取半高。
export const GLASS_RADIUS_CARD: number = 26;
export const GLASS_RADIUS_TILE: number = 22;
export const GLASS_RADIUS_CHIP: number = 14;

// 页面左右留白原来是这里的 GLASS_PAGE_PAD = 14；2026-09-23 按 SPEC-07 与其他页面统一成
// 手机 12（大屏按断点加宽），改用 util/pageMargin.pageMarginVp。
// 卡片之间的间距。
export const GLASS_GAP: number = 13;

// 仅供头像外框使用的装饰投影，不应用于资料卡片。
export const GLASS_SHADOW_RADIUS: number = 12;
export const GLASS_SHADOW_COLOR: string = '#2A5A6EAA';
export const GLASS_SHADOW_Y: number = 4;
