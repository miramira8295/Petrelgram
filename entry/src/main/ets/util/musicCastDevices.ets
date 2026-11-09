// 音频流转面板的设备模型（2026-09-18，音乐中心）。
//
// 设备是真的：来自 audio.AudioRoutingManager.getAvailableDevices(MEDIA_OUTPUT_DEVICES)，
// 取数在 services/AudioOutputDevices，这里只做「设备描述符 → 面板一行」的纯映射，可单测。
//
// 【为什么行文案是键不是字】和 musicTrackModel 同一条规矩：纯函数不读资源。
// 设备类型标签（听筒/扬声器/有线耳机/蓝牙/投播）由界面 str() 出来。
//
// 【蓝牙设备名可能是空的】name/address 要 ohos.permission.USE_BLUETOOTH 才给，
// 本应用没有申请（只为了显示一个名字去要蓝牙权限不划算）。所以名字按
// displayName → name → 类型标签 逐级兜底，绝不会出现空行。

// audio.DeviceType 的取值。这里重抄一份而不是 import，是为了让单测不依赖 @kit.AudioKit
// （单测跑在纯 ArkTS 环境里，见 local-tests-skip-main-sources）。
export const DEV_EARPIECE: number = 1;
export const DEV_SPEAKER: number = 2;
export const DEV_WIRED_HEADSET: number = 3;
export const DEV_WIRED_HEADPHONES: number = 4;
export const DEV_BLUETOOTH_SCO: number = 7;
export const DEV_BLUETOOTH_A2DP: number = 8;
export const DEV_USB_HEADSET: number = 22;
export const DEV_REMOTE_CAST: number = 24;
export const DEV_REMOTE_DAUDIO: number = 29;
export const DEV_DEFAULT: number = 1000;

export interface AudioOutputDevice {
  id: number;
  deviceType: number;
  // 系统给的显示名，可能是空串。
  displayName: string;
  name: string;
}

export interface MusicCastRow {
  id: number;
  // 左侧小方块里的类型标签（资源键）。
  tagKey: string;
  // 已经兜过底的设备名，不会是空串。
  name: string;
  // 副标题的资源键：当前输出 / 可用。
  descKey: string;
  active: boolean;
}

const TAG_KEYS: Map<number, string> = new Map([
  [DEV_EARPIECE, 'mc_dev_earpiece'],
  [DEV_SPEAKER, 'mc_dev_speaker'],
  [DEV_WIRED_HEADSET, 'mc_dev_wired'],
  [DEV_WIRED_HEADPHONES, 'mc_dev_wired'],
  [DEV_BLUETOOTH_SCO, 'mc_dev_bluetooth'],
  [DEV_BLUETOOTH_A2DP, 'mc_dev_bluetooth'],
  [DEV_USB_HEADSET, 'mc_dev_usb'],
  [DEV_REMOTE_CAST, 'mc_dev_cast'],
  [DEV_REMOTE_DAUDIO, 'mc_dev_remote']
]);

export function castTagKey(deviceType: number): string {
  return TAG_KEYS.get(deviceType) ?? 'mc_dev_other';
}

// 本机的三种（听筒/扬声器/系统默认）不是「流转目标」，播放页那颗胶囊上不该显示它们的名字。
export function castIsLocal(deviceType: number): boolean {
  return deviceType === DEV_EARPIECE || deviceType === DEV_SPEAKER || deviceType === DEV_DEFAULT;
}

export function castDeviceName(device: AudioOutputDevice, fallback: string): string {
  const display: string = device.displayName.trim();
  if (display !== '') {
    return display;
  }
  const name: string = device.name.trim();
  return name !== '' ? name : fallback;
}

// 面板的行。activeId < 0 表示还不知道当前输出（取数失败），那就一行都不高亮，
// 而不是瞎点一个——用户看到「都没亮」至少知道是未知，看到点错的那个会以为坏了。
export function buildCastRows(
  devices: AudioOutputDevice[], activeId: number, nameFallbacks: Map<string, string>
): MusicCastRow[] {
  const seen: Set<number> = new Set<number>();
  const rows: MusicCastRow[] = [];
  devices.forEach((device: AudioOutputDevice): void => {
    // 同一台设备可能以两个类型出现（蓝牙耳机的 A2DP 与 SCO 各一条），按 id 去重。
    if (seen.has(device.id)) {
      return;
    }
    seen.add(device.id);
    const tagKey: string = castTagKey(device.deviceType);
    rows.push({
      id: device.id,
      tagKey: tagKey,
      name: castDeviceName(device, nameFallbacks.get(tagKey) ?? ''),
      descKey: device.id === activeId ? 'mc_cast_current' : 'mc_cast_available',
      active: device.id === activeId
    });
  });
  return rows;
}

// 播放页那颗胶囊的文案：正在走本机就显示「流转」，走外部设备就显示设备名。
// 返回空串表示用默认文案（调用方 str('mc_cast')）。
export function castChipName(devices: AudioOutputDevice[], activeId: number): string {
  const active: AudioOutputDevice | undefined =
    devices.find((d: AudioOutputDevice): boolean => d.id === activeId);
  if (active === undefined || castIsLocal(active.deviceType)) {
    return '';
  }
  return castDeviceName(active, '');
}
