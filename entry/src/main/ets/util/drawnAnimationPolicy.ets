import { MessageEntry } from '../store/MessageEntry';
import { MessageBubbleRenderData } from '../pages/chat/ReusableMessageBubble';
import { ChatEnvMirror } from './chatEnvMirror';

// Fixed-field policies shared by the media island and click routing. Neither
// reads text/entities, scans a list nor allocates a playback candidate.
export function drawnAnimationPlaying(msg: MessageEntry, data: MessageBubbleRenderData,
  env: ChatEnvMirror, visible: boolean): boolean {
  return msg.contentType === 'video' && msg.isAnimation && msg.videoPath !== '' && visible &&
    env.appIsForeground && !data.animationPlaybackFailed && !data.animationPaused &&
    (data.animationForcePlay || (!env.powerSaving && !env.reduceAnim && env.autoplayGif));
}
export function drawnAnimationDownloadExpected(msg: MessageEntry, data: MessageBubbleRenderData,
  env: ChatEnvMirror): boolean {
  return msg.isAnimation && msg.videoFileId !== 0 && msg.videoPath === '' && !msg.videoFailed &&
    (data.animationForcePlay || (!env.powerSaving && !env.reduceAnim && env.autoplayGif));
}
