// TextArea 排版后的几何信息，单位统一为 vp。旧文本/宽度的测量不能沿用。
export interface ComposerLayoutMeasurement {
  text: string;
  widthVp: number;
  probeLineVp: number;
  contentHeightVp: number;
  lines: number;
}

export function composerMeasuredHeight(
  sample: ComposerLayoutMeasurement | undefined,
  text: string, widthVp: number, probeLineVp: number, maxLines: number
): number {
  if (sample === undefined || text === '' || sample.text !== text ||
    !Number.isFinite(widthVp) || widthVp <= 0 ||
    !Number.isFinite(probeLineVp) || probeLineVp <= 0 ||
    !Number.isFinite(sample.widthVp) || Math.abs(sample.widthVp - widthVp) > 0.5 ||
    !Number.isFinite(sample.probeLineVp) || Math.abs(sample.probeLineVp - probeLineVp) > 0.01 ||
    !Number.isFinite(sample.lines) || sample.lines < 1 ||
    !Number.isFinite(sample.contentHeightVp) || sample.contentHeightVp < 0 ||
    !Number.isFinite(maxLines) || maxLines < 1) {
    return 0;
  }
  const visibleLines: number = Math.min(sample.lines, maxLines);
  // 四行以内保留完整文字区域。超过上限按实测平均行高限制，仍由 TextArea 滚动。
  // 某些首帧内容矩形尚为零时，真实行数仍能纠正估算漏行。
  return Math.max(visibleLines * probeLineVp,
    sample.contentHeightVp * visibleLines / sample.lines);
}
