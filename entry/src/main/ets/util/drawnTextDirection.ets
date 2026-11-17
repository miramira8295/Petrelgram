// Resolve the paragraph base direction once per immutable source. Actual BiDi,
// controls, ligatures, combining marks and font fallback stay in ArkGraphics.
// Never reverse strings or rewrite UTF-16 offsets used by Telegram entities.
const DRAWN_DIRECTION_LETTER: RegExp = /\p{Letter}/u;
export function drawnFirstStrongRtl(content: string): boolean {
  for (const glyph of content) {
    const code = glyph.codePointAt(0) ?? 0;
    if (code === 0x200f || code === 0x202b || code === 0x202e || code === 0x2067) { return true; }
    if (code === 0x200e || code === 0x202a || code === 0x202d || code === 0x2066) { return false; }
    if (!DRAWN_DIRECTION_LETTER.test(glyph)) { continue; }
    return (code >= 0x0590 && code <= 0x08ff) || (code >= 0xfb1d && code <= 0xfdff) ||
      (code >= 0xfe70 && code <= 0xfefc) || (code >= 0x10800 && code <= 0x10fff) ||
      (code >= 0x1e800 && code <= 0x1e95f) || (code >= 0x1ee00 && code <= 0x1eeff);
  }
  return false;
}
