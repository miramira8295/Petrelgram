import { describe, expect, it } from '@ohos/hypium';
import { ReplySnippetInput, replySnippetOf } from '../main/ets/util/replySnippet';

function entry(
  text: string, placeholderLabel: string, contentType: string, paidMediaLocked: boolean
): ReplySnippetInput {
  return { text: text, placeholderLabel: placeholderLabel,
    contentType: contentType, paidMediaLocked: paidMediaLocked };
}

// 宿主单测里没装文案源，str() 原样返回 key——断言落在"选了哪条文案"上。
export default function replySnippetTest() {
  describe('replySnippet', () => {
    it('有文字就用文字，压过一切类型判断', 0, () => {
      expect(replySnippetOf(entry('你好', '', 'text', false))).assertEqual('你好');
      // 图片说明也算文字：比"图片"两个字有信息量。
      expect(replySnippetOf(entry('海边', '', 'photo', false))).assertEqual('海边');
      // 贴纸是例外，见下面那条单独的用例。
    });

    it('只有空白字符不算有文字', 0, () => {
      expect(replySnippetOf(entry('   ', '', 'photo', false))).assertEqual('storage_photo');
      expect(replySnippetOf(entry('\n', '', 'video', false))).assertEqual('storage_video');
    });

    it('占位描述排第二，压过按类型硬猜', 0, () => {
      expect(replySnippetOf(entry('', '已删除的消息', 'photo', false)))
        .assertEqual('已删除的消息');
      // 但压不过真正的文字。
      expect(replySnippetOf(entry('还在', '已删除的消息', 'photo', false))).assertEqual('还在');
      // 空白的占位描述同样不算。
      expect(replySnippetOf(entry('', '  ', 'voice', false))).assertEqual('ns_voice_message');
    });

    // issue #191：贴纸的 text 装的是它的 emoji，不是用户写的文字。当成文字用
    // 就只剩一个光秃秃的 🤣，读者不知道被引用的是张贴纸。这条推翻了之前
    // 「连贴纸都让位」的判断。
    it('贴纸排在文字之前，带上 emoji 说明这是贴纸', 0, () => {
      // 宿主 str() 带参时返回 `key(参数)`，断言因此连 emoji 一起对。
      expect(replySnippetOf(entry('🎉', '', 'sticker', false)))
        .assertEqual('preview_sticker_emoji(🎉)');
      // 没有 emoji 的贴纸只说「贴纸」。
      expect(replySnippetOf(entry('', '', 'sticker', false))).assertEqual('preview_sticker');
      expect(replySnippetOf(entry('  ', '', 'sticker', false))).assertEqual('preview_sticker');
      // 连 placeholderLabel 都压过——贴纸就是贴纸，没有更准的说法。
      expect(replySnippetOf(entry('🎉', '已删除的消息', 'sticker', false)))
        .assertEqual('preview_sticker_emoji(🎉)');
    });

    it('按类型给通用词', 0, () => {
      expect(replySnippetOf(entry('', '', 'photo', false))).assertEqual('storage_photo');
      expect(replySnippetOf(entry('', '', 'video', false))).assertEqual('storage_video');
      expect(replySnippetOf(entry('', '', 'voice', false))).assertEqual('ns_voice_message');
    });

    it('付费媒体按解锁与否给两种词——没解锁不能剧透', 0, () => {
      expect(replySnippetOf(entry('', '', 'paidMedia', true))).assertEqual('paid_media');
      expect(replySnippetOf(entry('', '', 'paidMedia', false))).assertEqual('cp_unlocked_media');
      // paidMediaLocked 只对 paidMedia 有意义，别的类型不受它影响。
      expect(replySnippetOf(entry('', '', 'video', true))).assertEqual('storage_video');
    });

    // 用户反馈（#211 第 1 条）：气泡里引用文件、音乐、投票……一律显示「媒体消息」。
    // 各类型的说法与首页会话列表的预览对齐；有名字（文件名、歌名、问题）先用名字。
    it('文件显示文件名，没有文件名才说「文件」', 0, () => {
      const f: ReplySnippetInput = entry('', '', 'file', false);
      f.fileName = '报价单.pdf';
      expect(replySnippetOf(f)).assertEqual('报价单.pdf');
      expect(replySnippetOf(entry('', '', 'file', false))).assertEqual('preview_file');
    });

    it('音乐按「歌手 – 歌名」，缺一样就退一步', 0, () => {
      const both: ReplySnippetInput = entry('', '', 'audio', false);
      both.audioTitle = '晴天';
      both.audioPerformer = '周杰伦';
      expect(replySnippetOf(both)).assertEqual('周杰伦 – 晴天');
      const titleOnly: ReplySnippetInput = entry('', '', 'audio', false);
      titleOnly.audioTitle = '晴天';
      expect(replySnippetOf(titleOnly)).assertEqual('晴天');
      const fileOnly: ReplySnippetInput = entry('', '', 'audio', false);
      fileOnly.fileName = 'track01.mp3';
      expect(replySnippetOf(fileOnly)).assertEqual('track01.mp3');
      expect(replySnippetOf(entry('', '', 'audio', false))).assertEqual('preview_music');
    });

    it('GIF 走的是视频管线，但要说 GIF 而不是视频', 0, () => {
      const gif: ReplySnippetInput = entry('', '', 'video', false);
      gif.isAnimation = true;
      expect(replySnippetOf(gif)).assertEqual('preview_gif');
    });

    it('圆形视频、投票、联系人、位置、游戏各有各的说法', 0, () => {
      expect(replySnippetOf(entry('', '', 'videoNote', false))).assertEqual('preview_video_note');
      const poll: ReplySnippetInput = entry('', '', 'poll', false);
      poll.pollQuestion = '周末去哪';
      expect(replySnippetOf(poll)).assertEqual('📊 周末去哪');
      expect(replySnippetOf(entry('', '', 'poll', false))).assertEqual('preview_poll');
      const contact: ReplySnippetInput = entry('', '', 'contact', false);
      contact.contactName = '张三';
      expect(replySnippetOf(contact)).assertEqual('👤 张三');
      expect(replySnippetOf(entry('', '', 'contact', false))).assertEqual('preview_contact');
      const venue: ReplySnippetInput = entry('', '', 'venue', false);
      venue.venueTitle = '西湖';
      expect(replySnippetOf(venue)).assertEqual('📍 西湖');
      expect(replySnippetOf(entry('', '', 'location', false))).assertEqual('preview_location');
      const game: ReplySnippetInput = entry('', '', 'game', false);
      game.gameTitle = '2048';
      expect(replySnippetOf(game)).assertEqual('🎮 2048');
      expect(replySnippetOf(entry('', '', 'game', false))).assertEqual('preview_game');
    });

    it('没见过的类型落到通用兜底，不会返回空串', 0, () => {
      expect(replySnippetOf(entry('', '', '', false))).assertEqual('cp_media_message');
      expect(replySnippetOf(entry('', '', 'someFutureType', false)))
        .assertEqual('cp_media_message');
    });
  });
}
