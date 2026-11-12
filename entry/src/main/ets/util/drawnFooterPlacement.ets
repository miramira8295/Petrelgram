export interface DrawnFooterInput {
  maxWidthPx: number;
  bodyWidthPx: number;
  bodyHeightPx: number;
  lastLineRightPx: number;
  lastLineTopPx: number;
  chromeWidthPx: number;
  footerWidthPx: number;
  footerHeightPx: number;
  gapPx: number;
  bottomGapPx: number;
}

export interface DrawnFooterPlacement {
  widthPx: number;
  heightPx: number;
  footerYPx: number;
  inline: boolean;
}

// Body is already shaped at the maximum available width. Let the shell use the
// remaining width budget to place the time beside the last line, without
// reshaping the body. Only an over-budget footer needs its own row.
export function placeDrawnFooter(input: DrawnFooterInput): DrawnFooterPlacement {
  if (!Number.isFinite(input.maxWidthPx) || input.maxWidthPx <= 0 ||
    !Number.isFinite(input.bodyWidthPx) || input.bodyWidthPx < 0 ||
    !Number.isFinite(input.bodyHeightPx) || input.bodyHeightPx <= 0 ||
    !Number.isFinite(input.chromeWidthPx) || input.chromeWidthPx < 0 ||
    !Number.isFinite(input.footerWidthPx) || input.footerWidthPx <= 0 ||
    !Number.isFinite(input.footerHeightPx) || input.footerHeightPx <= 0 ||
    input.footerWidthPx > input.maxWidthPx || input.chromeWidthPx > input.maxWidthPx + 0.000001 ||
    !Number.isFinite(input.gapPx) || input.gapPx < 0 ||
    !Number.isFinite(input.bottomGapPx) || input.bottomGapPx < 0) {
    throw new Error('invalid drawn footer geometry');
  }
  const naturalWidth: number = Math.min(input.maxWidthPx,
    Math.ceil(Math.max(input.bodyWidthPx, input.chromeWidthPx, input.footerWidthPx)));
  const inlineWidth: number = input.lastLineRightPx + input.gapPx + input.footerWidthPx;
  const inline: boolean = Number.isFinite(input.lastLineRightPx) && input.lastLineRightPx >= 0 &&
    Number.isFinite(input.lastLineTopPx) && input.lastLineTopPx >= 0 &&
    input.lastLineTopPx < input.bodyHeightPx &&
    inlineWidth <= input.maxWidthPx;
  const width: number = inline
    ? Math.min(input.maxWidthPx, Math.ceil(Math.max(naturalWidth, inlineWidth))) : naturalWidth;
  const footerY: number = inline
    ? Math.max(input.lastLineTopPx, input.bodyHeightPx - input.footerHeightPx - input.bottomGapPx)
    : input.bodyHeightPx;
  return { widthPx: width, heightPx: Math.max(input.bodyHeightPx, footerY + input.footerHeightPx + input.bottomGapPx),
    footerYPx: footerY, inline: inline };
}
