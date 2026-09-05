import {
  KEY_POWER_CHAT_EFFECTS, KEY_POWER_SMOOTH_TRANSITIONS,
  powerFeatureEnabled, powerGroupAnimationDuration
} from '../store/AppSettings';

// 聊天页动效时长的省电/无障碍闸。从 ChatPage.ets 搬来（原
// `private chatEffectDuration(key, duration)`，方法体逐字不变，只把
// `this.reduceAnimations` 换成显式参数）。
//
// ChatPage 侧保留一个一行的 `private chatEffectDuration(key, duration)` 转发
// （传 `this.reduceAnimations`）：它有十余处调用点，本批不为了改调用点扩大 diff。
export function chatEffectDurationOf(reduceAnimations: boolean, key: string, duration: number): number {
  if (reduceAnimations || !powerFeatureEnabled(KEY_POWER_SMOOTH_TRANSITIONS)) {
    return 0;
  }
  return powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, key, duration);
}
