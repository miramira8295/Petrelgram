// Independent navigation feedback settings; a zero/invalid intensity is never
// used as an implicit off switch. Enabling again preserves the chosen strength.
export const KEY_FOLDER_HAPTIC_ON: string = 'folderHapticOn';
export const KEY_DOCK_HAPTIC_ON: string = 'dockHapticOn';
export const KEY_FOLDER_HAPTIC_STRENGTH: string = 'folderHapticStrength';
export const KEY_DOCK_HAPTIC_STRENGTH: string = 'dockHapticStrength';
export const NAVIGATION_HAPTIC_DEFAULT: number = 40;

export function normalizeNavigationHapticStrength(value: number): number {
  return Number.isFinite(value) ? Math.max(1, Math.min(100, Math.round(value))) : NAVIGATION_HAPTIC_DEFAULT;
}
