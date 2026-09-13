import { describe, it, expect } from '@ohos/hypium';
import { formatPreview, previewThumbOf, stripPreviewIcon } from '../main/ets/util/formatPreview';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function msg(content: TdObject): TdObject {
  const m: TdObject = { '@type': 'message' };
  m['content'] = content;
  return m;
}

export default function formatPreviewTest() {
  describe('formatPreview', () => {
    it('null_message_empty', 0, () => {
      expect(formatPreview(null)).assertEqual('');
    });
    it('text', 0, () => {
      const text: TdObject = { '@type': 'formattedText' };
      text['text'] = 'hello world';
      const c: TdObject = { '@type': 'messageText' };
      c['text'] = text;
      expect(formatPreview(msg(c))).assertEqual('hello world');
    });
    it('photo_no_caption', 0, () => {
      const cap: TdObject = { '@type': 'formattedText' };
      cap['text'] = '';
      const c: TdObject = { '@type': 'messagePhoto' };
      c['caption'] = cap;
      expect(formatPreview(msg(c))).assertEqual('📷 preview_photo');
    });
    it('photo_with_caption', 0, () => {
      const cap: TdObject = { '@type': 'formattedText' };
      cap['text'] = 'beach';
      const c: TdObject = { '@type': 'messagePhoto' };
      c['caption'] = cap;
      expect(formatPreview(msg(c))).assertEqual('📷 beach');
    });
    it('sticker_with_emoji', 0, () => {
      const st: TdObject = { '@type': 'sticker' };
      st['emoji'] = '🎉';
      const c: TdObject = { '@type': 'messageSticker' };
      c['sticker'] = st;
      expect(formatPreview(msg(c))).assertEqual('preview_sticker_emoji(🎉)');
    });
    it('voice', 0, () => {
      const c: TdObject = { '@type': 'messageVoiceNote' };
      expect(formatPreview(msg(c))).assertEqual('preview_voice');
    });
    it('poll_no_question', 0, () => {
      const c: TdObject = { '@type': 'messagePoll' };
      expect(formatPreview(msg(c))).assertEqual('preview_poll');
    });
    it('unknown_fallback', 0, () => {
      const c: TdObject = { '@type': 'messageSomeFutureType' };
      expect(formatPreview(msg(c))).assertEqual('preview_unsupported');
    });
    it('custom_service_action_keeps_server_text', 0, () => {
      const c: TdObject = { '@type': 'messageCustomServiceAction' };
      c['text'] = '群组规则已更新';
      expect(formatPreview(msg(c))).assertEqual('群组规则已更新');
    });
    it('expired_media_is_understandable', 0, () => {
      const c: TdObject = { '@type': 'messageExpiredPhoto' };
      expect(formatPreview(msg(c))).assertEqual('preview_photo_expired');
    });
    it('video_no_caption', 0, () => {
      const c: TdObject = { '@type': 'messageVideo' };
      expect(formatPreview(msg(c))).assertEqual('📹 preview_video');
    });
    it('video_with_caption', 0, () => {
      const cap: TdObject = { '@type': 'formattedText' }; cap['text'] = 'trip';
      const c: TdObject = { '@type': 'messageVideo' }; c['caption'] = cap;
      expect(formatPreview(msg(c))).assertEqual('📹 trip');
    });
    it('document', 0, () => {
      const c: TdObject = { '@type': 'messageDocument' };
      expect(formatPreview(msg(c))).assertEqual('📎 preview_file');
    });
    it('animation', 0, () => {
      const c: TdObject = { '@type': 'messageAnimation' };
      expect(formatPreview(msg(c))).assertEqual('GIF');
    });
    it('audio', 0, () => {
      const c: TdObject = { '@type': 'messageAudio' };
      expect(formatPreview(msg(c))).assertEqual('preview_music');
    });
    it('location', 0, () => {
      const c: TdObject = { '@type': 'messageLocation' };
      expect(formatPreview(msg(c))).assertEqual('preview_location');
    });
    it('sticker_no_emoji', 0, () => {
      const st: TdObject = { '@type': 'sticker' }; st['emoji'] = '';
      const c: TdObject = { '@type': 'messageSticker' }; c['sticker'] = st;
      expect(formatPreview(msg(c))).assertEqual('preview_sticker');
    });
    it('text_missing_inner', 0, () => {
      const inner: TdObject = { '@type': 'formattedText' };
      const c: TdObject = { '@type': 'messageText' }; c['text'] = inner;
      expect(formatPreview(msg(c))).assertEqual('');
    });
    it('null_content_no_crash', 0, () => {
      const m = JSON.parse('{"@type":"message","content":null}') as TdObject;
      expect(formatPreview(m)).assertEqual('');
    });
    it('video_chat_started', 0, () => {
      const c: TdObject = { '@type': 'messageVideoChatStarted' };
      expect(formatPreview(msg(c))).assertEqual('service_video_chat_started');
    });
    it('video_chat_ended', 0, () => {
      const c: TdObject = { '@type': 'messageVideoChatEnded' };
      expect(formatPreview(msg(c))).assertEqual('service_video_chat_ended');
    });
    it('video_chat_scheduled', 0, () => {
      const c: TdObject = { '@type': 'messageVideoChatScheduled' };
      expect(formatPreview(msg(c))).assertEqual('service_video_chat_scheduled');
    });

    // issue #202：会话列表预览用 minithumbnail（内联 base64 JPEG）当小图，有图时去掉开头的 emoji。
    it('previewThumbOf: minithumbnail → data URL for photo/video/animation/document, else empty', 0, () => {
      const mini: TdObject = { '@type': 'minithumbnail' };
      mini['width'] = 40; mini['height'] = 30; mini['data'] = 'AAAA';
      const photo: TdObject = { '@type': 'photo' }; photo['minithumbnail'] = mini;
      const content: TdObject = { '@type': 'messagePhoto' }; content['photo'] = photo;
      const msg: TdObject = { '@type': 'message' }; msg['content'] = content;
      expect(previewThumbOf(msg)).assertEqual('data:image/jpeg;base64,AAAA');
      const video: TdObject = { '@type': 'video' }; video['minithumbnail'] = mini;
      const vc: TdObject = { '@type': 'messageVideo' }; vc['video'] = video;
      const vm: TdObject = { '@type': 'message' }; vm['content'] = vc;
      expect(previewThumbOf(vm)).assertEqual('data:image/jpeg;base64,AAAA');
      const doc: TdObject = { '@type': 'document' };   // 没有 minithumbnail
      const dc: TdObject = { '@type': 'messageDocument' }; dc['document'] = doc;
      const dm: TdObject = { '@type': 'message' }; dm['content'] = dc;
      expect(previewThumbOf(dm)).assertEqual('');
      const tm: TdObject = { '@type': 'message' }; tm['content'] = { '@type': 'messageText' } as TdObject;
      expect(previewThumbOf(tm)).assertEqual('');
      expect(previewThumbOf(null)).assertEqual('');
    });
    it('stripPreviewIcon drops only a leading media emoji', 0, () => {
      expect(stripPreviewIcon('📷 照片')).assertEqual('照片');
      expect(stripPreviewIcon('📹 看这个')).assertEqual('看这个');
      expect(stripPreviewIcon('📎 report.pdf')).assertEqual('report.pdf');
      expect(stripPreviewIcon('普通文本 📷')).assertEqual('普通文本 📷');
      expect(stripPreviewIcon('')).assertEqual('');
    });
  });
}
