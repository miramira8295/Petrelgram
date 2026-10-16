import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { completedDragFilePath, messageDragPayload, messageDragType } from '../main/ets/util/messageDrag';

function td(json: string): TdObject { return JSON.parse(json) as TdObject; }
export default function messageDragTest() {
  describe('MessageDrag', (): void => {
    const permissions = td('{"can_be_forwarded":true,"can_be_saved":true}');
    const text = td('{"content":{"@type":"messageText","text":{"text":"hello https://example.com"}}}');
    it('text_preserves_original_text_and_link', 0, (): void => {
      expect(messageDragPayload(text, permissions)?.text).assertEqual('hello https://example.com');
    });
    it('unknown_or_denied_permissions_reject', 0, (): void => {
      expect(messageDragPayload(text, td('{}')) === null).assertTrue();
      expect(messageDragPayload(text, td('{"can_be_forwarded":false}')) === null).assertTrue();
    });
    it('protected_and_self_destructing_reject', 0, (): void => {
      const protectedMessage = td(JSON.stringify(text)); protectedMessage['has_protected_content'] = true;
      expect(messageDragPayload(protectedMessage, permissions) === null).assertTrue();
      const protectedProps = td(JSON.stringify(permissions)); protectedProps['has_protected_content_by_other_user'] = true;
      expect(messageDragPayload(text, protectedProps) === null).assertTrue();
      const expiring = td(JSON.stringify(text)); expiring['self_destruct_type'] = td('{"@type":"messageSelfDestructTypeImmediately"}');
      expect(messageDragPayload(expiring, permissions) === null).assertTrue();
    });
    it('sending_and_unsupported_messages_reject', 0, (): void => {
      const sending = td(JSON.stringify(text)); sending['sending_state'] = td('{}');
      expect(messageDragPayload(sending, permissions) === null).assertTrue();
      expect(messageDragPayload(td('{"content":{"@type":"messagePaidMedia"}}'), permissions) === null).assertTrue();
      expect(messageDragType('sticker')).assertEqual('');
    });
    it('photo_chooses_largest_original_not_first_thumbnail', 0, (): void => {
      const photo = td('{"content":{"@type":"messagePhoto","photo":{"sizes":[{"width":80,"height":80,"photo":{"id":1}},{"width":2000,"height":1000,"photo":{"id":2}},{"width":320,"height":160,"photo":{"id":3}}]}}}');
      expect(messageDragPayload(photo, permissions)?.fileId).assertEqual(2);
      expect(messageDragPayload(photo, td('{"can_be_forwarded":true}')) === null).assertTrue();
    });
    it('media_uses_original_not_thumbnail', 0, (): void => {
      const video = td('{"content":{"@type":"messageVideo","video":{"video":{"id":10},"thumbnail":{"file":{"id":11}}}}}');
      expect(messageDragPayload(video, permissions)?.fileId).assertEqual(10);
      expect(messageDragPayload(video, permissions)?.type).assertEqual('general.video');
    });
    it('document_and_voice_originals_supported', 0, (): void => {
      expect(messageDragPayload(td('{"content":{"@type":"messageDocument","document":{"document":{"id":9}}}}'), permissions)?.fileId).assertEqual(9);
      expect(messageDragPayload(td('{"content":{"@type":"messageVoiceNote","voice_note":{"voice_note":{"id":8}}}}'), permissions)?.type).assertEqual('general.audio');
    });
    it('partial_download_never_exported', 0, (): void => {
      expect(completedDragFilePath(td('{"local":{"path":"/partial","is_downloading_completed":false}}'))).assertEqual('');
      expect(completedDragFilePath(td('{"local":{"path":"/complete","is_downloading_completed":true}}'))).assertEqual('/complete');
      expect(completedDragFilePath(td('{"local":{"path":"","is_downloading_completed":true}}'))).assertEqual('');
    });
  });
}
