import { describe, it, expect } from '@ohos/hypium';
import {
  CONTACT_ERR_BAD_PHONE, CONTACT_ERR_NETWORK, CONTACT_ERR_NO_USER, CONTACT_ERR_OTHER,
  contactAddErrorKind, contactErrorRecoverable
} from '../main/ets/util/contactAddError';

export default function contactAddErrorTest() {
  describe('contactAddError', () => {
    // 回归：客户端错误是带空格的句子，原来只写下划线形式，一句都认不出来，
    // 用户看到的是兜底的「添加联系人失败，请稍后重试」（2026-10-30）。
    it('客户端句子：User not found 归为找不到用户', 0, (): void => {
      expect(contactAddErrorKind('User not found')).assertEqual(CONTACT_ERR_NO_USER);
    });

    it('两种写法都认：USER_NOT_FOUND 与 User not found', 0, (): void => {
      expect(contactAddErrorKind('400: USER_NOT_FOUND')).assertEqual(CONTACT_ERR_NO_USER);
      expect(contactAddErrorKind('400: User not found')).assertEqual(CONTACT_ERR_NO_USER);
    });

    it('号码没注册：正确的 UNOCCUPIED 与历史拼错的 NOT_OCCUPIED 都归为找不到用户', 0, (): void => {
      expect(contactAddErrorKind('400: PHONE_NUMBER_UNOCCUPIED')).assertEqual(CONTACT_ERR_NO_USER);
      expect(contactAddErrorKind('400: PHONE_NUMBER_NOT_OCCUPIED')).assertEqual(CONTACT_ERR_NO_USER);
      expect(contactAddErrorKind('Phone number is not occupied')).assertEqual(CONTACT_ERR_NO_USER);
    });

    it('号码不合法：服务端码与客户端句子都归为号牌问题', 0, (): void => {
      expect(contactAddErrorKind('400: PHONE_NUMBER_INVALID')).assertEqual(CONTACT_ERR_BAD_PHONE);
      expect(contactAddErrorKind('Phone number is invalid')).assertEqual(CONTACT_ERR_BAD_PHONE);
      expect(contactAddErrorKind('Invalid target phone number specified')).assertEqual(CONTACT_ERR_BAD_PHONE);
      expect(contactAddErrorKind('Field "phone_number" must contain a valid phone number'))
        .assertEqual(CONTACT_ERR_BAD_PHONE);
      expect(contactAddErrorKind('Phone number must be encoded in UTF-8')).assertEqual(CONTACT_ERR_BAD_PHONE);
    });

    it('网络 / 超时 / 频率限制归为网络类', 0, (): void => {
      expect(contactAddErrorKind('request timeout')).assertEqual(CONTACT_ERR_NETWORK);
      expect(contactAddErrorKind('Network request failed')).assertEqual(CONTACT_ERR_NETWORK);
      expect(contactAddErrorKind('400: FLOOD_WAIT_12')).assertEqual(CONTACT_ERR_NETWORK);
    });

    it('认不出来的归 other', 0, (): void => {
      expect(contactAddErrorKind('Something unexpected happened')).assertEqual(CONTACT_ERR_OTHER);
      expect(contactAddErrorKind('')).assertEqual(CONTACT_ERR_OTHER);
    });

    // 只有「人没找着 / 没认出来」才值得换下一条路重试；号码错和断网重试无意义。
    it('可恢复性：找不到用户与未知错误可换路，号牌与网络不可', 0, (): void => {
      expect(contactErrorRecoverable(CONTACT_ERR_NO_USER)).assertTrue();
      expect(contactErrorRecoverable(CONTACT_ERR_OTHER)).assertTrue();
      expect(contactErrorRecoverable(CONTACT_ERR_BAD_PHONE)).assertFalse();
      expect(contactErrorRecoverable(CONTACT_ERR_NETWORK)).assertFalse();
    });
  });
}
