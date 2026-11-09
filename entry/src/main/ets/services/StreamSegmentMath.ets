// 分段时长 = 1000 / 2^scale 毫秒 (scale ∈ {0,1} → 1000 / 500)
export function segmentDurationMs(scale: number): number {
  return Math.floor(1000 / Math.pow(2, scale));
}

// time_offset 必须对齐到分段网格(分段起点为分段时长的整数倍)
export function quantizeToGrid(timestampMs: number, scale: number): number {
  const dur = segmentDurationMs(scale);
  return Math.floor(timestampMs / dur) * dur;
}

// 从 live-edge 回退 backSegments 段作为起播点,保证缓冲
export function startOffset(liveEdgeMs: number, scale: number, backSegments: number): number {
  const dur = segmentDurationMs(scale);
  return quantizeToGrid(liveEdgeMs, scale) - backSegments * dur;
}

export function nextTimeOffset(currentMs: number, scale: number): number {
  return currentMs + segmentDurationMs(scale);
}
