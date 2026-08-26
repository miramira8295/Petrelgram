import { describe, expect, it } from '@ohos/hypium';
import {
  SEARCH_SESSION_TTL_MS, forgetSearchSession, rememberSearchSession, takeSearchSession
} from '../main/ets/util/searchSession';

export default function searchSessionTest() {
  describe('searchSession', () => {
    it('记住关键词与分页，时效内取得回来', 0, (): void => {
      forgetSearchSession();
      rememberSearchSession('猫', 3, 1000);
      const got = takeSearchSession(1000 + SEARCH_SESSION_TTL_MS - 1);
      expect(got !== null).assertTrue();
      expect(got?.query).assertEqual('猫');
      expect(got?.tab).assertEqual(3);
    });
    it('超时就当没记，并且清掉', 0, (): void => {
      forgetSearchSession();
      rememberSearchSession('猫', 0, 1000);
      expect(takeSearchSession(1000 + SEARCH_SESSION_TTL_MS + 1)).assertNull();
      expect(takeSearchSession(1000)).assertNull();
    });
    it('空关键词不记', 0, (): void => {
      forgetSearchSession();
      rememberSearchSession('   ', 2, 1000);
      expect(takeSearchSession(1000)).assertNull();
    });
    it('明确离开就忘掉', 0, (): void => {
      rememberSearchSession('狗', 1, 1000);
      forgetSearchSession();
      expect(takeSearchSession(1000)).assertNull();
    });
  });
}
