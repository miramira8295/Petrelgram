import { describe, it, expect } from '@ohos/hypium';
import { isInternalAuthError, needsAuthorizationReset, QR_CONFIRMATION_STATE } from '../main/ets/util/authError';

export default function authErrorTextTest() {
  describe('authError', () => {
    // TDLib 的「Call to <method> unexpected」是它在抱怨自己的授权状态机对不上，
    // 用户既看不懂也无从下手。手机模拟器上实测能稳定复现两条：
    // 冷启动点扫码、以及扫码态下提交手机号。
    it('treats_call_to_unexpected_as_internal', 0, () => {
      expect(isInternalAuthError('Call to setAuthenticationPhoneNumber unexpected')).assertTrue();
      expect(isInternalAuthError('Call to requestQrCodeAuthentication unexpected')).assertTrue();
    });

    // 真实的服务端错误要原样透出去：它们是用户能据此行动的（换号码、等一等、
    // 去官方客户端解封），我们编一句「请稍后重试」反而把信息删掉了。
    it('passes_through_real_server_errors', 0, () => {
      expect(isInternalAuthError('PHONE_NUMBER_INVALID')).assertFalse();
      expect(isInternalAuthError('PHONE_NUMBER_BANNED')).assertFalse();
      expect(isInternalAuthError('FLOOD_WAIT_86400')).assertFalse();
      expect(isInternalAuthError('PHONE_CODE_INVALID')).assertFalse();
    });

    // 空串/异常输入不该被当成内部错误——那会把「没有错误」显示成一句提示。
    it('handles_empty_and_odd_input', 0, () => {
      expect(isInternalAuthError('')).assertFalse();
      expect(isInternalAuthError('   ')).assertFalse();
    });

    // 大小写与前后空白不该影响判定：TDLib 各版本的措辞有过出入。
    it('is_case_and_whitespace_insensitive', 0, () => {
      expect(isInternalAuthError('  CALL TO logOut UNEXPECTED  ')).assertTrue();
    });

    // 「unexpected」出现在真实服务端错误里的可能性：目前 Telegram 的错误码全是
    // 大写下划线常量，不含这个词。但判定收窄到「Call to ... unexpected」这个
    // 完整形状，比裸 indexOf('unexpected') 稳，免得哪天误伤。
    it('does_not_match_bare_unexpected', 0, () => {
      expect(isInternalAuthError('UNEXPECTED_SERVER_RESPONSE')).assertFalse();
    });

    // 扫码授权态是**持久化**的：TDLib 把它写进 td.binlog，之后每次冷启动都恢复，
    // setAuthenticationPhoneNumber 被永久拒绝，用户再也用不了手机号登录
    // （手机模拟器 hilog 实证：污染态 WaitTdlibParameters -> WaitOtherDeviceConfirmation，
    // 跳过 WaitPhoneNumber；干净态才走 WaitPhoneNumber）。
    // 唯一的出路是清掉本地授权数据重来，但那是破坏性的——所以判定必须**两个条件同时成立**。
    it('resets_only_when_stuck_in_qr_state_and_rejected', 0, () => {
      expect(needsAuthorizationReset(
        'Call to setAuthenticationPhoneNumber unexpected', QR_CONFIRMATION_STATE)).assertTrue();
    });

    // 同样的拒绝，但授权态不是扫码态——那是别的时机问题，重试就够了，不该清数据。
    it('does_not_reset_when_not_in_qr_state', 0, () => {
      expect(needsAuthorizationReset(
        'Call to setAuthenticationPhoneNumber unexpected',
        'authorizationStateWaitPhoneNumber')).assertFalse();
      expect(needsAuthorizationReset(
        'Call to setAuthenticationPhoneNumber unexpected', '')).assertFalse();
    });

    // 在扫码态下，但错误是真实的服务端错误——号码本身有问题，清数据解决不了，
    // 反而把用户的本地状态白白毁掉。
    it('does_not_reset_on_real_server_errors', 0, () => {
      expect(needsAuthorizationReset('PHONE_NUMBER_INVALID', QR_CONFIRMATION_STATE)).assertFalse();
      expect(needsAuthorizationReset('FLOOD_WAIT_86400', QR_CONFIRMATION_STATE)).assertFalse();
      expect(needsAuthorizationReset('PHONE_NUMBER_BANNED', QR_CONFIRMATION_STATE)).assertFalse();
    });

    // 空输入不该触发破坏性操作。
    it('does_not_reset_on_empty_input', 0, () => {
      expect(needsAuthorizationReset('', QR_CONFIRMATION_STATE)).assertFalse();
    });
  });
}
