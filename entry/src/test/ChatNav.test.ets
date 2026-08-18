import { describe, expect, it } from '@ohos/hypium';
import { findChatRouteIndex, RouteSnapshot } from '../main/ets/util/chatNav';

// 重复开页的根因不是某一个调用点写错了，而是十个调用点各自 pushUrl，谁也
// 不知道栈里已经有一个同会话的详情页。这个纯函数就是那个"谁也不知道"的
// 补丁：给它一份路由栈快照，它说出该回到哪一层，或者 0 表示确实得新开。
function route(index: number, chatId: number, topicId: number = 0): RouteSnapshot {
  return { index: index, name: 'ChatPage', path: 'pages/chat/', chatId: chatId, topicId: topicId };
}

export default function chatNavTest() {
  describe('chatNav', () => {
    it('returns 0 for an empty stack', 0, () => {
      expect(findChatRouteIndex([], 42, 0)).assertEqual(0);
    });

    it('finds the chat page already carrying this chat', 0, () => {
      const stack: RouteSnapshot[] = [
        { index: 1, name: 'Index', path: 'pages/', chatId: 0, topicId: 0 },
        route(2, 7),
        route(3, 9)
      ];
      expect(findChatRouteIndex(stack, 7, 0)).assertEqual(2);
      expect(findChatRouteIndex(stack, 9, 0)).assertEqual(3);
    });

    it('returns 0 when no route carries the chat', 0, () => {
      expect(findChatRouteIndex([route(2, 7)], 8, 0)).assertEqual(0);
    });

    // 非 ChatPage 的页面即便带了同一个 chatId（资料页就带），也不是可以
    // 回退过去的目标——回过去用户会落在资料页而不是会话里。
    it('ignores routes that are not the chat page', 0, () => {
      const stack: RouteSnapshot[] = [
        { index: 1, name: 'ProfilePage', path: 'pages/profile/', chatId: 7, topicId: 0 }
      ];
      expect(findChatRouteIndex(stack, 7, 0)).assertEqual(0);
    });

    // 论坛的两个话题是同一个 chatId 下两个真正不同的页面，去重不能把它们
    // 合并——否则从话题 A 点到话题 B 会莫名其妙退回 A。
    it('keeps forum topics of one chat apart', 0, () => {
      const stack: RouteSnapshot[] = [route(2, 7, 100), route(3, 7, 200)];
      expect(findChatRouteIndex(stack, 7, 100)).assertEqual(2);
      expect(findChatRouteIndex(stack, 7, 200)).assertEqual(3);
      expect(findChatRouteIndex(stack, 7, 300)).assertEqual(0);
      // 主会话（无话题）也和任何话题页不是一回事。
      expect(findChatRouteIndex(stack, 7, 0)).assertEqual(0);
    });

    // 同一个会话被重复推进栈是当前的 bug 现象；修好之后不该再出现，但
    // 万一出现，回到最靠上的那一层是唯一不会丢中间页的选择。
    it('returns the topmost match when duplicates already exist', 0, () => {
      expect(findChatRouteIndex([route(2, 7), route(4, 7)], 7, 0)).assertEqual(4);
    });
  });
}
