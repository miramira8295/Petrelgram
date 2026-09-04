// 回复条上那行摘要：引用一条消息时，第二行显示什么。
//
// 优先级是有讲究的，而且前两档和后面不是一回事：
//   0. 贴纸单独排在最前 —— 见下面那段"为什么贴纸要插队"；
//   1. 消息自己的文字（含图片说明）——有就用，最贴近用户看到的内容；
//   2. placeholderLabel——业务侧已经算好的占位描述（如"已删除的消息"），
//      它比按类型硬猜更准；
//   3. 剩下的才按内容类型给一个通用词。
//
// 抽出来是因为第 3 档里 paidMedia 会根据有没有解锁给两种词，而这条分支埋在
// 一串同构的 if 中间，很容易在加新类型时被顺手抹平。
//
// 返回 str() 的结果：宿主单测没装文案源时 str() 原样返回 key，断言因此落在
// "选了哪条文案"上。

import { str } from './strings';

export interface ReplySnippetInput {
  text: string;
  placeholderLabel: string;
  contentType: string;
  paidMediaLocked: boolean;
}

export function replySnippetOf(m: ReplySnippetInput): string {
  // 【为什么贴纸要插队】**贴纸的 text 字段装的是它的 emoji，不是用户写的文字**
  // （formatMsgContent 的 stickerMsgContent：`text: fallbackEmoji`）。落到下面
  // 那条"有文字就用文字"里，回复条上就只剩一个光秃秃的 🤣，读者根本不知道被
  // 引用的是张贴纸（issue #191）。
  //
  // 这里刻意推翻了之前的判断——旧注释写的是"连贴纸都让位，虽然贴纸的 text
  // 通常是那个 emoji"，把 emoji 当成了有信息量的文字。用户反馈说明不是。
  //
  // 文案和首页会话列表对齐（formatPreview 的 messageSticker 分支用的就是这两
  // 条），两处显示同一句话。
  if (m.contentType === 'sticker') {
    const emoji: string = m.text.trim();
    return emoji !== '' ? str('preview_sticker_emoji', emoji) : str('preview_sticker');
  }
  if (m.text.trim() !== '') {
    return m.text;
  }
  if (m.placeholderLabel.trim() !== '') {
    return m.placeholderLabel;
  }
  if (m.contentType === 'photo') {
    return str('storage_photo');
  }
  if (m.contentType === 'video') {
    return str('storage_video');
  }
  if (m.contentType === 'paidMedia') {
    // 没解锁时不能剧透内容，只说"付费媒体"。
    return m.paidMediaLocked ? str('paid_media') : str('cp_unlocked_media');
  }
  if (m.contentType === 'voice') {
    return str('ns_voice_message');
  }
  return str('cp_media_message');
}
