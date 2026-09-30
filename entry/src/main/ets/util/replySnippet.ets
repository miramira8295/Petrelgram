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
  // 以下都可选：有名字就先说名字（#211 第 1 条，见 typedSnippet）。
  fileName?: string;        // 文件/音乐的原始文件名（MessageEntry.videoFileName）
  audioTitle?: string;
  audioPerformer?: string;
  isAnimation?: boolean;    // GIF 走视频管线，contentType 也是 'video'
  pollQuestion?: string;
  contactName?: string;
  venueTitle?: string;
  gameTitle?: string;
}

// 按内容类型给说法，和首页会话列表的预览对齐（同一条消息两处说同一句话）。
// 没有对应类型时返回空串，由调用方落到通用兜底。
//
// 【为什么要有这一段】原来第 3 档只认图片、视频、付费媒体、语音，文件、音乐、
// 投票、位置……一律落到「媒体消息」——用户反馈（#211 第 1 条）「气泡内都叫媒体
// 消息」，引用一份文件看不出是文件。
function typedSnippet(m: ReplySnippetInput): string {
  const fileName: string = (m.fileName ?? '').trim();
  if (m.contentType === 'file') {
    return fileName !== '' ? fileName : str('preview_file');
  }
  if (m.contentType === 'audio') {
    const title: string = (m.audioTitle ?? '').trim();
    const performer: string = (m.audioPerformer ?? '').trim();
    if (title !== '') {
      return performer !== '' ? `${performer} – ${title}` : title;
    }
    return fileName !== '' ? fileName : str('preview_music');
  }
  if (m.contentType === 'video' && (m.isAnimation ?? false)) {
    return str('preview_gif');
  }
  if (m.contentType === 'videoNote') {
    return str('preview_video_note');
  }
  if (m.contentType === 'poll') {
    const q: string = (m.pollQuestion ?? '').trim();
    return q !== '' ? `📊 ${q}` : str('preview_poll');
  }
  if (m.contentType === 'contact') {
    const name: string = (m.contactName ?? '').trim();
    return name !== '' ? `👤 ${name}` : str('preview_contact');
  }
  if (m.contentType === 'venue' || m.contentType === 'location') {
    const venue: string = (m.venueTitle ?? '').trim();
    return venue !== '' ? `📍 ${venue}` : str('preview_location');
  }
  if (m.contentType === 'game') {
    const game: string = (m.gameTitle ?? '').trim();
    return game !== '' ? `🎮 ${game}` : str('preview_game');
  }
  return '';
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
  const typed: string = typedSnippet(m);
  if (typed !== '') {
    return typed;
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
