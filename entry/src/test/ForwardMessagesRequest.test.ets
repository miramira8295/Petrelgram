import { describe, expect, it } from '@ohos/hypium';
import {
  buildForwardMessagesRequest, forwardCaptionRemovable, ForwardCaptionCandidate,
  ForwardMessagesRequestInput, selectionHasRemovableForwardCaption
} from '../main/ets/util/forwardMessagesRequest';
import { TdRequest } from '../main/ets/tdkit/TdTypes';

function inputOf(): ForwardMessagesRequestInput {
  return {
    toChatId: 20,
    fromChatId: 10,
    messageIds: [5, 3, 5, 4],
    threadRootId: 99,
    sendCopy: false,
    removeCaption: false,
    canRemoveCaption: false
  };
}

export default function forwardMessagesRequestTest() {
  describe('forwardMessagesRequest', () => {
    it('sorts and deduplicates ids at the TDLib boundary', 0, () => {
      const req: TdRequest = buildForwardMessagesRequest(inputOf())!;
      expect(req['message_ids'] as number[]).assertDeepEquals([3, 4, 5]);
      expect(req['send_copy'] as boolean).assertFalse();
      expect(req['remove_caption'] as boolean).assertFalse();
    });

    it('maps copy and caption options without emitting an ignored combination', 0, () => {
      const copy: ForwardMessagesRequestInput = inputOf();
      copy.sendCopy = true;
      copy.removeCaption = true;
      copy.canRemoveCaption = true;
      const enabled: TdRequest = buildForwardMessagesRequest(copy)!;
      expect(enabled['send_copy'] as boolean).assertTrue();
      expect(enabled['remove_caption'] as boolean).assertTrue();

      copy.sendCopy = false;
      const notCopy: TdRequest = buildForwardMessagesRequest(copy)!;
      expect(notCopy['remove_caption'] as boolean).assertFalse();
      copy.sendCopy = true;
      copy.canRemoveCaption = false;
      const noCaption: TdRequest = buildForwardMessagesRequest(copy)!;
      expect(noCaption['remove_caption'] as boolean).assertFalse();
    });

    it('keeps a topic only when forwarding inside the source chat', 0, () => {
      const crossChat: TdRequest = buildForwardMessagesRequest(inputOf())!;
      expect(crossChat['message_thread_id'] as number).assertEqual(0);
      const sameChat: ForwardMessagesRequestInput = inputOf();
      sameChat.toChatId = sameChat.fromChatId;
      const req: TdRequest = buildForwardMessagesRequest(sameChat)!;
      expect(req['message_thread_id'] as number).assertEqual(99);
    });

    it('recognizes captions without treating ordinary text as a caption', 0, () => {
      expect(forwardCaptionRemovable('photo', 'caption')).assertTrue();
      expect(forwardCaptionRemovable('video', '  ')).assertFalse();
      expect(forwardCaptionRemovable('text', 'message')).assertFalse();
      expect(forwardCaptionRemovable('paidMedia', 'caption')).assertTrue();
    });

    it('enables caption removal when any selected media item has a caption', 0, () => {
      const messages: ForwardCaptionCandidate[] = [
        { id: 1, contentType: 'text', text: 'ordinary message' },
        { id: 2, contentType: 'photo', text: '' },
        { id: 3, contentType: 'video', text: 'selected caption' }
      ];
      expect(selectionHasRemovableForwardCaption(messages, [1, 3])).assertTrue();
      expect(selectionHasRemovableForwardCaption(messages, [1, 2])).assertFalse();
      // A caption outside the current multi-selection must not enable the option.
      expect(selectionHasRemovableForwardCaption(messages, [1])).assertFalse();
    });

    it('rejects an empty or invalid request', 0, () => {
      const empty: ForwardMessagesRequestInput = inputOf();
      empty.messageIds = [];
      expect(buildForwardMessagesRequest(empty) === null).assertTrue();
      empty.messageIds = [1];
      empty.toChatId = 0;
      expect(buildForwardMessagesRequest(empty) === null).assertTrue();
    });
  });
}
