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

export function systemMaterialOff(level: number): boolean {
  return normalizeSystemMaterial(level) === THICKNESS_OFF;
}

// 聊天浮层在未启用系统材质时的兜底底色：
//   · 关闭档（THICKNESS_OFF）→ 纯色不透明 surface（无透明度实体）；
//   · APP 默认档（SYSTEM_MATERIAL_APP_DEFAULT）→ 原有的半透明 chat_overlay。
export function chatPlainFill(level: number): Resource {
  return systemMaterialOff(level) ? $r('app.color.surface') : $r('app.color.chat_overlay');
}

@ObservedV2
export class SystemMaterialState {
  @Trace level: number = SYSTEM_MATERIAL_DEFAULT;

  get chatEnabled(): boolean {
    return chatMaterialEnabled(this.level);
  }

  get isOff(): boolean {
    return systemMaterialOff(this.level);
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
