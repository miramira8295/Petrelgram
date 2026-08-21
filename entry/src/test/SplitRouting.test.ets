import { describe, it, expect } from '@ohos/hypium';
import {
  decidePush, chatKey, StackFrame, StackAction
} from '../main/ets/util/splitRouting';

function f(name: string, key: string): StackFrame {
  const out: StackFrame = { name: name, key: key };
  return out;
}

export default function splitRoutingTest(): void {
  describe('splitRouting', (): void => {

    it('空栈从左栏推 → clearAndPush', 0, (): void => {
      const got: StackAction = decidePush([], 'navbar', f('ChatPage', '10:0'));
      expect(got).assertEqual('clearAndPush');
    });

    it('空栈从右栏推 → push', 0, (): void => {
      const got: StackAction = decidePush([], 'content', f('ProfilePage', '7'));
      expect(got).assertEqual('push');
    });

    it('左栏点第二个会话 → clearAndPush（替换而非叠加）', 0, (): void => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      const got: StackAction = decidePush(stack, 'navbar', f('ChatPage', '11:0'));
      expect(got).assertEqual('clearAndPush');
    });

    it('右栏内点查看群资料 → push（叠加）', 0, (): void => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      const got: StackAction = decidePush(stack, 'content', f('ChatProfilePage', '10'));
      expect(got).assertEqual('push');
    });

    it('栈顶已是同一会话 → skip（通知重复点击不重开）', 0, (): void => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      const got: StackAction = decidePush(stack, 'navbar', f('ChatPage', '10:0'));
      expect(got).assertEqual('skip');
    });

    it('同一会话不同话题 → 不 skip', 0, (): void => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      const got: StackAction = decidePush(stack, 'navbar', f('ChatPage', '10:99'));
      expect(got).assertEqual('clearAndPush');
    });

    it('同一会话在栈中但不在栈顶 → 不 skip', 0, (): void => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ChatProfilePage', '10')];
      const got: StackAction = decidePush(stack, 'content', f('ChatPage', '10:0'));
      expect(got).assertEqual('push');
    });

    it('chatKey 用 chatId 与 topicId 组合，负 chatId 也能区分', 0, (): void => {
      expect(chatKey(10, 0)).assertEqual('10:0');
      expect(chatKey(-100123, 7)).assertEqual('-100123:7');
      expect(chatKey(10, 0) === chatKey(10, 1)).assertFalse();
    });

  });
}
