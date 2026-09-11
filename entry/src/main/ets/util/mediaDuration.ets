// 媒体时长 h:mm:ss / m:ss。
//
// 从 MessageBubble.formatDuration 提出来：相册格子搬进 AlbumCellView 之后两边都
// 要用它，留在类里就只能复制一份。纯函数，零依赖。
export function formatMediaDuration(totalSeconds: number): string {
  const safeSeconds: number = Math.max(0, Math.floor(totalSeconds));
  const h: number = Math.floor(safeSeconds / 3600);
  const m: number = Math.floor((safeSeconds % 3600) / 60);
  const s: number = safeSeconds % 60;
  const mm: string = h > 0 ? `${m}`.padStart(2, '0') : `${m}`;
  const ss: string = `${s}`.padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}
