import { THICKNESS_DEFAULT, THICKNESS_OFF, THICKNESS_ULTRA_THICK } from './materialTuning';

// App default preserves the app's surface-specific styles and plain chat chrome.
// Explicit thickness applies to both color modes and opts chat chrome in.
export const SYSTEM_MATERIAL_APP_DEFAULT: number = -4;
export const KEY_SYSTEM_MATERIAL: string = 'systemMaterialLevel';
export const SYSTEM_MATERIAL_DEFAULT: number = SYSTEM_MATERIAL_APP_DEFAULT;

export function normalizeSystemMaterial(level: number): number {
  return Number.isFinite(level) && Number.isInteger(level) &&
    level >= SYSTEM_MATERIAL_APP_DEFAULT && level <= THICKNESS_ULTRA_THICK
    ? level : SYSTEM_MATERIAL_DEFAULT;
}

export function chatMaterialEnabled(level: number): boolean {
  const normalized: number = normalizeSystemMaterial(level);
  return normalized !== SYSTEM_MATERIAL_APP_DEFAULT && normalized !== THICKNESS_OFF;
}

@ObservedV2
export class SystemMaterialState {
  @Trace level: number = SYSTEM_MATERIAL_DEFAULT;

  get chatEnabled(): boolean {
    return chatMaterialEnabled(this.level);
  }
}

export const systemMaterialState: SystemMaterialState = new SystemMaterialState();

// AppSettings owns persistence; all consumers see one shared selection.
export function applySystemMaterial(level: number): void {
  const normalized: number = normalizeSystemMaterial(level);
  if (systemMaterialState.level !== normalized) { systemMaterialState.level = normalized; }
  AppStorage.setOrCreate(KEY_SYSTEM_MATERIAL, normalized);
}

export function systemMaterialThickness(): number {
  const level: number = normalizeSystemMaterial(AppStorage.get<number>(KEY_SYSTEM_MATERIAL) ?? SYSTEM_MATERIAL_DEFAULT);
  return level === SYSTEM_MATERIAL_APP_DEFAULT ? THICKNESS_DEFAULT : level;
}
