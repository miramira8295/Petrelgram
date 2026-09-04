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

    it('没见过的类型落到通用兜底，不会返回空串', 0, () => {
      expect(replySnippetOf(entry('', '', 'poll', false))).assertEqual('cp_media_message');
      expect(replySnippetOf(entry('', '', '', false))).assertEqual('cp_media_message');
      expect(replySnippetOf(entry('', '', 'someFutureType', false)))
        .assertEqual('cp_media_message');
    });
  });
}
