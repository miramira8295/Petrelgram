import { describe, expect, it } from '@ohos/hypium';
import { requestOutcomeUncertain } from '../main/ets/util/tdRequestTimeout';

export default function tdRequestTimeoutTest() {
  describe('requestOutcomeUncertain', () => {
    // TdClient.send 超时时抛的就是这一句。
    it('client_timeout_is_uncertain', 0, (): void => {
      expect(requestOutcomeUncertain('request timeout')).assertTrue();
    });

    it('matching_is_case_insensitive', 0, (): void => {
      expect(requestOutcomeUncertain('Request Timeout')).assertTrue();
      expect(requestOutcomeUncertain('MessageStore.loadAround failed: REQUEST TIMEOUT')).assertTrue();
    });

    // 服务端的真失败要照常报出来，不能被这条吞掉。
    it('server_errors_stay_failures', 0, (): void => {
      expect(requestOutcomeUncertain('CHAT_ADMIN_REQUIRED')).assertFalse();
      expect(requestOutcomeUncertain('BUTTON_DATA_INVALID')).assertFalse();
      expect(requestOutcomeUncertain('Not Found')).assertFalse();
      expect(requestOutcomeUncertain('')).assertFalse();
    });

    // 代理心跳的 "Pong timeout expired" 也带 timeout，但它不是请求超时，
    // 不该被认成"结果未知"。
    it('other_timeouts_are_not_request_timeouts', 0, (): void => {
      expect(requestOutcomeUncertain('Pong timeout expired')).assertFalse();
      expect(requestOutcomeUncertain('connect timeout')).assertFalse();
    });
  });
}
