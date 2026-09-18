import { audio } from '@kit.AudioKit';
import { AudioOutputDevice } from '../util/musicCastDevices';
import { logE } from '../util/log';

// 音频输出设备的取数（2026-09-18，音乐中心的「音频流转」面板）。
//
// 只做两件事：列出**可用的媒体输出设备**、报出**当前正在用的那一个**，并在两者
// 变化时回调。映射成面板的行在 util/musicCastDevices（纯函数、有单测）。
//
// 【为什么这里不负责「切设备」】公共接口里没有「把本应用的音频改到某台设备上」
// 这一条：AudioRoutingManager 的选路是系统 UI 的事，AudioSessionManager 的
// setMediaOutputDevice 只能在「内置扬声器 / 系统默认」之间切、且 API 26 才有。
// 真正能投到音箱、智慧屏上的只有系统的流转选择器（AVCastPicker），所以面板里
// 列出来的设备是**状态**，切换交给面板底部那颗 AVCastPicker。

const RENDERER_INFO: audio.AudioRendererInfo = {
  usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
  rendererFlags: 0
};

export type AudioOutputListener = () => void;

function toDevice(d: audio.AudioDeviceDescriptor): AudioOutputDevice {
  return {
    id: d.id,
    deviceType: d.deviceType as number,
    displayName: d.displayName ?? '',
    name: d.name ?? ''
  };
}

class AudioOutputDevices {
  private routing: audio.AudioRoutingManager | null = null;
  private listeners: Set<AudioOutputListener> = new Set<AudioOutputListener>();
  private watching: boolean = false;

  private manager(): audio.AudioRoutingManager | null {
    if (this.routing !== null) {
      return this.routing;
    }
    try {
      this.routing = audio.getAudioManager().getRoutingManager();
    } catch (e) {
      logE(`AudioOutputDevices.getRoutingManager failed: ${e}`);
      this.routing = null;
    }
    return this.routing;
  }

  // 可用的媒体输出设备。取不到一律返回空数组——面板据此显示「没有可用设备」，
  // 而不是把一个异常抛到界面上。
  devices(): AudioOutputDevice[] {
    const routing: audio.AudioRoutingManager | null = this.manager();
    if (routing === null) {
      return [];
    }
    try {
      const list: audio.AudioDeviceDescriptors =
        routing.getAvailableDevices(audio.DeviceUsage.MEDIA_OUTPUT_DEVICES);
      return list.map(toDevice);
    } catch (e) {
      logE(`AudioOutputDevices.getAvailableDevices failed: ${e}`);
      return [];
    }
  }

  // 当前输出设备的 id；-1 = 不知道（面板据此一行都不高亮，见 buildCastRows）。
  activeId(): number {
    const routing: audio.AudioRoutingManager | null = this.manager();
    if (routing === null) {
      return -1;
    }
    try {
      const list: audio.AudioDeviceDescriptors =
        routing.getPreferredOutputDeviceForRendererInfoSync(RENDERER_INFO);
      return list.length > 0 ? list[0].id : -1;
    } catch (e) {
      logE(`AudioOutputDevices.getPreferredOutputDevice failed: ${e}`);
      return -1;
    }
  }

  // 插拔耳机、连上音箱、系统里切了输出——三件事都要让面板跟着变。
  subscribe(listener: AudioOutputListener): () => void {
    this.listeners.add(listener);
    this.startWatch();
    return (): void => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0) {
        this.stopWatch();
      }
    };
  }

  private startWatch(): void {
    const routing: audio.AudioRoutingManager | null = this.manager();
    if (routing === null || this.watching) {
      return;
    }
    try {
      routing.on('availableDeviceChange', audio.DeviceUsage.MEDIA_OUTPUT_DEVICES,
        (): void => { this.notify(); });
      routing.on('preferOutputDeviceChangeForRendererInfo', RENDERER_INFO,
        (): void => { this.notify(); });
      this.watching = true;
    } catch (e) {
      logE(`AudioOutputDevices.watch failed: ${e}`);
    }
  }

  private stopWatch(): void {
    const routing: audio.AudioRoutingManager | null = this.manager();
    if (routing === null || !this.watching) {
      return;
    }
    try {
      routing.off('availableDeviceChange');
      routing.off('preferOutputDeviceChangeForRendererInfo');
    } catch (e) {
      logE(`AudioOutputDevices.unwatch failed: ${e}`);
    }
    this.watching = false;
  }

  private notify(): void {
    this.listeners.forEach((listener: AudioOutputListener): void => {
      try {
        listener();
      } catch (e) {
        logE(`AudioOutputDevices listener failed: ${e}`);
      }
    });
  }
}

const instance: AudioOutputDevices = new AudioOutputDevices();

export function audioOutputDevices(): AudioOutputDevices {
  return instance;
}
