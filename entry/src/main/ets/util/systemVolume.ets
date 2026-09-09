// 系统音量：手势层的 0..1 与设备的整数档位之间的换算。
//
// 【为什么是系统音量而不是播放器音量】改播放器自己的音量（AVPlayer.setVolume /
// ijk 的 setVolume）在听感上也能大能小，但那是**另一个增益**——和硬件音量键
// 各调各的，用户按一下音量键就发现两者对不上（用户 2026-09-09：「音量和我按钮
// 的音量还不同步」）。
//
// 【怎么改的系统音量】AudioManager.setVolume 需要 ACCESS_NOTIFICATION_POLICY
// 且已废弃，废弃说明里点名的替代品是 **AVVolumePanel**（@ohos.multimedia.
// avVolumePanel，API 12）：那是个组件，给它的 volumeLevel 赋值就会设置设备音量，
// 不需要任何权限。读取用 AudioVolumeManager.getVolumeByStream（API 20，
// 本工程 compatibleSdkVersion 正是 20），不需要权限。
//
// 【亮度为什么做不到同样的事】@ohos.brightness 根本不在普通应用 SDK 里，
// 系统亮度改不了。窗口亮度（window.setWindowBrightness）是唯一的路，
// 见 util/screenBrightness。

// 比例（0..1）→ 设备档位（整数）。
export function volumeLevelFor(fraction: number, minLevel: number, maxLevel: number): number {
  if (maxLevel <= minLevel) {
    return minLevel;
  }
  const f: number = Math.max(0, Math.min(1, fraction));
  return Math.round(minLevel + f * (maxLevel - minLevel));
}

// 设备档位 → 比例（0..1）。范围退化时返回 0，别让 HUD 出现 NaN。
export function fractionOf(level: number, minLevel: number, maxLevel: number): number {
  if (maxLevel <= minLevel) {
    return 0;
  }
  const clamped: number = Math.max(minLevel, Math.min(maxLevel, level));
  return (clamped - minLevel) / (maxLevel - minLevel);
}
