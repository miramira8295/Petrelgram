// 「这一类动画此刻该不该动」的判据，从 TgsStickerView 里抽出来——原生渲染那支
// （TgsNativeStickerView）要用同一份，两边各写一遍迟早漂移，而漂移的表现是
// 「设置里关了动画，某一类贴纸还在动」这种没人会报的 bug。
import { ChatEnvMirror } from './chatEnvMirror';

export function tgsPowerSuspended(env: ChatEnvMirror, powerCategory: string): boolean {
  if (env.powerSaving || env.reduceAnim) {
    return true;
  }
  if (powerCategory === 'emojiPicker') {
    return !env.animatedEmoji;
  }
  if (powerCategory === 'emojiStatus' || powerCategory === 'emoji') {
    return !env.animatedEmoji || !env.emojiStatus;
  }
  if (powerCategory === 'emojiReaction') {
    return !env.animatedEmoji || !env.emojiReactions;
  }
  if (powerCategory === 'emojiChat') {
    return !env.animatedEmoji || !env.emojiChat;
  }
  return !env.stickers || !env.stickerAutoplay;
}
