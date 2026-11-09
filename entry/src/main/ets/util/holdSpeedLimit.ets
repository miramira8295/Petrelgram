// Shared persisted preference; streaming keeps its separate network cap.
export const HOLD_SPEED_LIMIT_OPTIONS: number[] = [2, 3, 4, 6, 8, 16, 32];
export const HOLD_SPEED_LIMIT_DEFAULT: number = 32;

export function normalizeHoldSpeedLimit(value: number): number {
  return HOLD_SPEED_LIMIT_OPTIONS.indexOf(value) >= 0 ? value : HOLD_SPEED_LIMIT_DEFAULT;
}
