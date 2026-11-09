// 会话底部那一层浮块的统一几何。
//
// 底部这个位置会轮流住着好几样东西：输入框、会话内搜索的计数与翻页、加入频道/
// 解除静音/机器人「开始」这类状态条。它们原来各写各的宽高圆角，有的按内容收紧、
// 有的整条铺满屏幕，同一个位置的东西宽度随状态跳来跳去
// （用户 2026-09-08：「统一样式包裹内容即可，不需要横向一整个屏幕」）。
//
// 常量放在这里而不是各自文件里，是为了改一处就全跟着变——分散写死过一次，
// 结果就是上面那种参差。
//
// **材质不在这里**：玻璃一律走 plainGlassFill / plainBackdropBlur /
// hdsVisualEffect 那三件套，它们本来就吃设置里的「样式强度 / 关闭」
// （关掉时回落实色 + 模糊 0，厚度走 thicknessOffset）。这个文件只管几何。

// 胶囊高度。圆角取它的一半，成为纯圆端。
export const BOTTOM_PILL_HEIGHT: number = 44;

// 左右内边距。内容按它收紧，不铺满。
export const BOTTOM_PILL_PADDING: number = 16;

// 浮块之间的横向间距（比如计数胶囊和两颗翻页圆钮之间）。
export const BOTTOM_PILL_GAP: number = 8;

export function bottomPillRadius(): number {
  return BOTTOM_PILL_HEIGHT / 2;
}
