import { str } from './strings';
import {
  DC_KIND_APK, DC_KIND_AUDIO, DC_KIND_FILE, DC_KIND_PHOTO, DC_KIND_VIDEO, DC_KIND_VOICE
} from './downloadCenterModel';

// 下载中心的类型名：页签标题、没有真名的条目的标题。
export function dcKindLabel(kind: string): string {
  if (kind === DC_KIND_VIDEO) {
    return str('dc_tab_video');
  }
  if (kind === DC_KIND_PHOTO) {
    return str('dc_tab_photo');
  }
  if (kind === DC_KIND_AUDIO) {
    return str('dc_tab_audio');
  }
  if (kind === DC_KIND_FILE) {
    return str('dc_tab_file');
  }
  if (kind === DC_KIND_VOICE) {
    return str('dc_tab_voice');
  }
  if (kind === DC_KIND_APK) {
    return str('dc_tab_apk');
  }
  return str('dc_tab_all');
}
