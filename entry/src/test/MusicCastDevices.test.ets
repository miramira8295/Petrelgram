import { describe, expect, it } from '@ohos/hypium';
import {
  AudioOutputDevice, buildCastRows, castChipName, castDeviceName, castIsLocal, castTagKey,
  DEV_BLUETOOTH_A2DP, DEV_BLUETOOTH_SCO, DEV_DEFAULT, DEV_EARPIECE, DEV_REMOTE_CAST, DEV_SPEAKER,
  DEV_WIRED_HEADSET, MusicCastRow
} from '../main/ets/util/musicCastDevices';

// 音频流转面板的设备行（2026-09-18，音乐中心）。
//
// 设备来自系统（services/AudioOutputDevices），这一层只做映射，所以能单测：
// 类型 → 标签键、名字兜底、当前设备高亮、同一台设备的多个类型只出现一行。

function device(id: number, deviceType: number, displayName: string, name: string): AudioOutputDevice {
  return { id: id, deviceType: deviceType, displayName: displayName, name: name };
}

export default function musicCastDevicesTest() {
  describe('MusicCastDevices', () => {
    it('tag key per device type', 0, () => {
      expect(castTagKey(DEV_SPEAKER)).assertEqual('mc_dev_speaker');
      expect(castTagKey(DEV_WIRED_HEADSET)).assertEqual('mc_dev_wired');
      expect(castTagKey(DEV_BLUETOOTH_A2DP)).assertEqual('mc_dev_bluetooth');
      expect(castTagKey(DEV_REMOTE_CAST)).assertEqual('mc_dev_cast');
      // 没见过的类型不能返回空串——界面会拿它去查资源。
      expect(castTagKey(9999)).assertEqual('mc_dev_other');
    });

    it('local devices are not cast targets', 0, () => {
      expect(castIsLocal(DEV_SPEAKER)).assertTrue();
      expect(castIsLocal(DEV_EARPIECE)).assertTrue();
      expect(castIsLocal(DEV_DEFAULT)).assertTrue();
      expect(castIsLocal(DEV_BLUETOOTH_A2DP)).assertFalse();
    });

    it('name falls back displayName -> name -> tag', 0, () => {
      expect(castDeviceName(device(1, DEV_SPEAKER, 'Sound X', 'speaker'), '扬声器')).assertEqual('Sound X');
      // 蓝牙设备名要蓝牙权限才给，本应用没申请，所以空串必须能兜住。
      expect(castDeviceName(device(2, DEV_BLUETOOTH_A2DP, '  ', 'FreeBuds'), '蓝牙')).assertEqual('FreeBuds');
      expect(castDeviceName(device(3, DEV_BLUETOOTH_A2DP, '', ''), '蓝牙')).assertEqual('蓝牙');
    });

    it('rows mark the active device and dedupe by id', 0, () => {
      const devices: AudioOutputDevice[] = [
        device(11, DEV_SPEAKER, '本机扬声器', ''),
        device(12, DEV_BLUETOOTH_A2DP, 'FreeBuds Pro', ''),
        // 同一台蓝牙耳机的第二条（SCO），id 相同，不该多出一行。
        device(12, DEV_BLUETOOTH_SCO, 'FreeBuds Pro', '')
      ];
      const rows: MusicCastRow[] = buildCastRows(devices, 12, new Map<string, string>());
      expect(rows.length).assertEqual(2);
      expect(rows[0].active).assertFalse();
      expect(rows[0].descKey).assertEqual('mc_cast_available');
      expect(rows[1].active).assertTrue();
      expect(rows[1].descKey).assertEqual('mc_cast_current');
      expect(rows[1].tagKey).assertEqual('mc_dev_bluetooth');
    });

    it('unknown active id highlights nothing', 0, () => {
      const rows: MusicCastRow[] = buildCastRows(
        [device(11, DEV_SPEAKER, '本机扬声器', '')], -1, new Map<string, string>());
      expect(rows.length).assertEqual(1);
      // 猜一个高亮比不高亮更糟：用户会以为选错了设备。
      expect(rows[0].active).assertFalse();
    });

    it('chip shows the device name only when audio left the phone', 0, () => {
      const speaker: AudioOutputDevice[] = [device(11, DEV_SPEAKER, '本机扬声器', '')];
      expect(castChipName(speaker, 11)).assertEqual('');
      const buds: AudioOutputDevice[] = [device(12, DEV_BLUETOOTH_A2DP, 'FreeBuds Pro', '')];
      expect(castChipName(buds, 12)).assertEqual('FreeBuds Pro');
      // 当前设备不在列表里（刚拔掉）：退回默认文案。
      expect(castChipName(buds, 99)).assertEqual('');
    });
  });
}
