// 简介页（群组 / 个人）的玻璃外观。
//
// 内容装进毛玻璃卡片。（设计稿里还有一张会漂移的渐变壁纸，实测铺到会话列表
// 上光斑太抢戏、把行整个吃掉，已撤掉。）
// 卡片本身沿用 overlayMaterial 那套（材质可用就上沉浸光感，否则退回模糊 +
// 降级底色），所以这里只提供尺寸、留白和背景，不重复造玻璃。
//
// 两个页面共用：数值散在两处迟早跑偏，而它们必须看起来是同一个页面。

// 卡片圆角。设计里三档：整块列表 26、方格 22、药丸取半高。
export const GLASS_RADIUS_CARD: number = 26;
export const GLASS_RADIUS_TILE: number = 22;
export const GLASS_RADIUS_CHIP: number = 14;

// 页面左右留白。设计是 14，比原来的 12 稍宽，让卡片圆角透出更多壁纸。
export const GLASS_PAGE_PAD: number = 14;
// 卡片之间的间距。
export const GLASS_GAP: number = 13;

// 卡片投影。比原来那层 4px 的浅影厚，玻璃才浮得起来。
export const GLASS_SHADOW_RADIUS: number = 32;
export const GLASS_SHADOW_COLOR: string = '#2A5A6EAA';
export const GLASS_SHADOW_Y: number = 12;
