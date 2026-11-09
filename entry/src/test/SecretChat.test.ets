import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  MEMBERSHIP_SECRET_CLOSED, MEMBERSHIP_SECRET_PENDING, SECRET_CLOSED, SECRET_PENDING,
  SECRET_READY, canSendInSecretChat, parseSecretChat, secretBarTextKey, secretHeaderKey,
  secretMembershipState, secretStateOf
} from '../main/ets/util/secretChat';

function chat(stateType: string, outbound: boolean): TdObject {
  const state: TdObject = { '@type': stateType };
  const raw: TdObject = { '@type': 'secretChat' };
  raw['id'] = 7;
  raw['user_id'] = 42;
  raw['state'] = state;
  raw['is_outbound'] = outbound;
  raw['layer'] = 101;
  return raw;
}

export default function secretChatTest(): void {
  describe('secretChat', (): void => {

    it('三种状态各自认得出来', 0, (): void => {
      expect(secretStateOf('secretChatStateReady')).assertEqual(SECRET_READY);
      expect(secretStateOf('secretChatStatePending')).assertEqual(SECRET_PENDING);
      expect(secretStateOf('secretChatStateClosed')).assertEqual(SECRET_CLOSED);
    });

    // 认不出来的一律当 closed。反过来（当 pending 或 ready）就是让用户对着一个
    // 必然失败的输入框打字。
    it('未知状态当已关闭，不当就绪', 0, (): void => {
      expect(secretStateOf('')).assertEqual(SECRET_CLOSED);
      expect(secretStateOf('secretChatStateSomethingNew')).assertEqual(SECRET_CLOSED);
      expect(canSendInSecretChat(parseSecretChat(chat('', true)))).assertFalse();
    });

    it('字段照原样解出来', 0, (): void => {
      const info = parseSecretChat(chat('secretChatStateReady', true));
      expect(info.id).assertEqual(7);
      expect(info.userId).assertEqual(42);
      expect(info.layer).assertEqual(101);
      expect(info.isOutbound).assertTrue();
      expect(info.state).assertEqual(SECRET_READY);
    });

    it('拿不到对象时不炸，退成待建立且不可发', 0, (): void => {
      const info = parseSecretChat(undefined);
      expect(info.id).assertEqual(0);
      expect(info.userId).assertEqual(0);
      expect(canSendInSecretChat(info)).assertFalse();
    });

    // 只有 ready 能发。这条是整组的核心：判反了用户会对着必然失败的输入框打字。
    it('只有就绪能发消息', 0, (): void => {
      expect(canSendInSecretChat(parseSecretChat(chat('secretChatStateReady', false)))).assertTrue();
      expect(canSendInSecretChat(parseSecretChat(chat('secretChatStatePending', false)))).assertFalse();
      expect(canSendInSecretChat(parseSecretChat(chat('secretChatStateClosed', false)))).assertFalse();
    });

    it('输入区形态跟着状态走，就绪时不替换', 0, (): void => {
      expect(secretMembershipState(parseSecretChat(chat('secretChatStateReady', true)))).assertEqual('');
      expect(secretMembershipState(parseSecretChat(chat('secretChatStatePending', true))))
        .assertEqual(MEMBERSHIP_SECRET_PENDING);
      expect(secretMembershipState(parseSecretChat(chat('secretChatStateClosed', true))))
        .assertEqual(MEMBERSHIP_SECRET_CLOSED);
    });

    // 等待期两边的话术不同：发起方在等对方上线，接收方是本机在建密钥。
    it('等待中的措辞分收发两侧', 0, (): void => {
      expect(secretBarTextKey(MEMBERSHIP_SECRET_PENDING, true)).assertEqual('cp_secret_pending_out');
      expect(secretBarTextKey(MEMBERSHIP_SECRET_PENDING, false)).assertEqual('cp_secret_pending_in');
      // 已关闭时不分收发，两侧同一句。
      expect(secretBarTextKey(MEMBERSHIP_SECRET_CLOSED, true)).assertEqual('cp_secret_closed');
      expect(secretBarTextKey(MEMBERSHIP_SECRET_CLOSED, false)).assertEqual('cp_secret_closed');
    });

    it('顶栏副标题只在非就绪时覆盖', 0, (): void => {
      expect(secretHeaderKey(parseSecretChat(chat('secretChatStateReady', true)))).assertEqual('');
      expect(secretHeaderKey(parseSecretChat(chat('secretChatStatePending', true))))
        .assertEqual('chat_header_secret_pending');
      expect(secretHeaderKey(parseSecretChat(chat('secretChatStateClosed', true))))
        .assertEqual('chat_header_secret_closed');
    });
  });
}
