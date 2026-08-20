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
      // 连贴纸都让位——虽然贴纸的 text 通常是那个 emoji。
      expect(replySnippetOf(entry('🎉', '', 'sticker', false))).assertEqual('🎉');
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

    it('按类型给通用词', 0, () => {
      expect(replySnippetOf(entry('', '', 'sticker', false))).assertEqual('sticker_tab');
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
