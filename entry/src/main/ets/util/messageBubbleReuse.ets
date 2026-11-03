// 轻量纯文本渲染的**唯一判据**。
//
// 【这个文件只剩这一个函数】它原来有 396 行，里面还并排放着第二套复用键算法
// （messageBubbleReuseId / plainTextBubbleReuseId / canReuseMessageBubble …）。
// 那套算法生产侧零调用、只有测试在跑，而真正在用的复用键是 util/rowReuseId。
// 两套并存的结果是「改错函数」的风险——rowReuseId 的注释甚至把那个不存在的
// 消费者写成了既定事实。2026-11-02 删掉死的那半，只留真正被调用的这一条判据。
//
// 调用方：
//   · pages/chat/ChatTimelineSession（prepare 时算 lightweightPlainText）
//   · pages/chat/ChatTimelineHost（Repeat 决定 templateId）
// 两处必须用同一份判据，否则模板池和实际渲染树会错配。

import { MessageEntry } from '../store/MessageEntry';
import { isUnformattedPlainText } from './richText';

// Strict gate for the genuinely small renderer. Anything that needs the rich
// text tree, a preview/footer/keyboard, album semantics or completed translation
// stays on MessageBubble. Reply quotes, transient translation status and the
// ordinary group-chat chrome are intentionally allowed because they are common
// in the first visible screen and the lightweight renderer implements them.
//
// 【为什么是独立函数】完整版要一个 MessageBubbleReuseContext，而 Repeat 的
// .templateId() 回调为了拿它，原先要跑一遍 prepareMessageBubble()——那里面要
// 拼一条 25 段的 cacheKey 才去查缓存。首屏 JS profile：prepareMessageBubble
// 总计 605.8ms，其中 **284.9ms 是从 rowTemplateIdOf 进来的**。而真正被用到的
// 只有 lightweightPlainText 一个布尔，它用到的上下文字段又只有 memberCount /
// albumItemCount 两个计数，两者都能从 AlbumGroup 直接读。
export function canRenderLightweightPlainTextRow(
  msg: MessageEntry,
  memberCount: number,
  albumItemCount: number
): boolean {
  if (msg.contentType !== 'text' || msg.isUnsupportedMessage ||
    memberCount !== 1 || albumItemCount > 1) {
    return false;
  }
  if (!isUnformattedPlainText(msg.text, msg.textEntities) ||
    msg.forwardFrom !== '' || msg.reactions.length > 0 ||
    msg.inlineButtons.length > 0 || msg.commentCount > 0 ||
    msg.translatedText !== '') {
    return false;
  }
  return msg.linkUrl === '' && msg.linkSiteName === '' && msg.linkTitle === '' &&
    msg.linkDescription === '' && msg.linkDescriptionEntities.length === 0 &&
    msg.linkPhotoFileId === 0 && msg.linkPhotoPath === '' && msg.linkPreviewType === '';
}
