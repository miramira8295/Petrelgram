import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  requestChatJump, resetChatJumpChannel, subscribeChatJump
} from '../main/ets/util/chatJumpChannel';

export default function chatJumpChannelTest() {
  describe('chatJumpChannel', () => {
    beforeEach((): void => { resetChatJumpChannel(); });

    it('订阅方收到本会话的跳转请求', 0, (): void => {
      const got: number[] = [];
      subscribeChatJump(7, (id: number): void => { got.push(id); });
      requestChatJump(7, 42);
      expect(got.length).assertEqual(1);
      expect(got[0]).assertEqual(42);
    });

    // 键是 chatId：分栏下可能同时开着两个会话，跳转不能串台。
    it('不串到别的会话', 0, (): void => {
      const got: number[] = [];
      subscribeChatJump(7, (id: number): void => { got.push(id); });
      requestChatJump(8, 42);
      expect(got.length).assertEqual(0);
    });

    it('退订之后不再收到', 0, (): void => {
      const got: number[] = [];
      const off = subscribeChatJump(7, (id: number): void => { got.push(id); });
      off();
      requestChatJump(7, 42);
      expect(got.length).assertEqual(0);
    });

    // 没有订阅者 = 那个会话没开着。**不排队**：留一份"待送"会在下次打开同一个
    // 会话时冒出一次陈旧跳转，那比不跳更糟。
    it('没人订阅时静默丢弃，不会留到下次订阅', 0, (): void => {
      requestChatJump(7, 42);
      const got: number[] = [];
      subscribeChatJump(7, (id: number): void => { got.push(id); });
      expect(got.length).assertEqual(0);
    });

    it('非法入参不发', 0, (): void => {
      const got: number[] = [];
      subscribeChatJump(7, (id: number): void => { got.push(id); });
      requestChatJump(7, 0);
      requestChatJump(7, -1);
      requestChatJump(0, 42);
      expect(got.length).assertEqual(0);
    });

    // 分栏下同一个会话可能被两处订阅（页面 + 将来的预览层），都要收到。
    it('多个订阅者都收到', 0, (): void => {
      let a = 0;
      let b = 0;
      subscribeChatJump(7, (): void => { a++; });
      subscribeChatJump(7, (): void => { b++; });
      requestChatJump(7, 42);
      expect(a).assertEqual(1);
      expect(b).assertEqual(1);
    });
  });
}
