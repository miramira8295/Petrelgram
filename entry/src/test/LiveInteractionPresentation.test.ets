import { describe, expect, it } from '@ohos/hypium';
import {
  LiveInteractionEntry, LiveInteractionPresentationInput, isSupportedLiveChannelMessage,
  liveInteractionLooksLikeEmojiOnly, liveInteractionPresentation, looksLikeEmojiOnly, mergeLiveInteractions
} from '../main/ets/util/liveInteractionPresentation';

function entry(key: string, source: string, date: number, arrival: number): LiveInteractionEntry {
  return {
    key, revision: '', source, id: arrival, senderKey: 'messageSenderUser:7',
    senderName: '用户', senderInitials: '用', senderAvatarPath: '', colorSeed: 7,
    date, text: '你好', photoPath: '', emojiOnly: false, isFromOwner: false,
    sendState: 'none', arrivalOrder: arrival
  };
}

function input(): LiveInteractionPresentationInput {
  return {
    valid: true, resolved: true, active: true, joined: true, joinedOnce: true,
    recovering: false, messagesAllowed: true, canSendMessages: true, messageCount: 0,
    channelAttached: true, channelHistoryState: 'ready', channelHistoryError: ''
  };
}

export default function liveInteractionPresentationTest() {
  describe('LiveInteractionPresentation', (): void => {
    it('keeps_stable_arrival_order_for_equal_dates', 0, (): void => {
      // 文本必须不同：同发送者 + 同时间 + 同文本会命中跨源去重（见下一个用例），
      // 两条被合成一条，就验不到排序了。
      const later = entry('call:2', 'call', 10, 2);
      later.text = '在的';
      const earlier = entry('chat:1', 'chat', 10, 1);
      const merged = mergeLiveInteractions([later, earlier], 100);
      expect(merged[0].key).assertEqual('chat:1');
      expect(merged[1].key).assertEqual('call:2');
    });
    it('dedupes_only_matching_cross_source_messages', 0, (): void => {
      const chat = entry('chat:1', 'chat', 10, 1);
      const call = entry('call:2', 'call', 11, 2);
      call.isFromOwner = true;
      const merged = mergeLiveInteractions([chat, call], 100);
      expect(merged.length).assertEqual(1);
      expect(merged[0].key).assertEqual('call:2');
      const repeated = entry('call:3', 'call', 11, 3);
      expect(mergeLiveInteractions([call, repeated], 100).length).assertEqual(2);
    });
    it('maps_loading_readonly_and_partial_error_states', 0, (): void => {
      const loading = input();
      loading.channelHistoryState = 'loading';
      expect(liveInteractionPresentation(loading).kind).assertEqual('loading');
      const readonly = input();
      readonly.canSendMessages = false;
      expect(liveInteractionPresentation(readonly).statusText).assertEqual('live_chat_readonly_short');
      const failed = input();
      failed.channelHistoryState = 'error';
      failed.channelHistoryError = '网络错误';
      expect(liveInteractionPresentation(failed).showHistoryRetry).assertTrue();
      expect(liveInteractionPresentation(failed).composerEnabled).assertTrue();
    });
    it('filters_service_messages_and_recognizes_emoji', 0, (): void => {
      expect(isSupportedLiveChannelMessage('system', false)).assertFalse();
      expect(isSupportedLiveChannelMessage('photo', false)).assertTrue();
      expect(isSupportedLiveChannelMessage('video', true)).assertTrue();
      expect(liveInteractionLooksLikeEmojiOnly('❤️🔥')).assertTrue();
      expect(liveInteractionLooksLikeEmojiOnly('hi 👋')).assertFalse();
      expect(looksLikeEmojiOnly('😄')).assertTrue();
      expect(looksLikeEmojiOnly('开心')).assertFalse();
      expect(looksLikeEmojiOnly('happy')).assertFalse();
    });
  });
}
