import { describe, it, expect } from '@ohos/hypium';
import {
  decidePush, chatKey, StackFrame, StackAction, decideChatPush } from '../main/ets/util/splitRouting';

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


    // **1.4.0 回归的场景钉死在这里**：文件夹A → 聊天B →（从 B 内部点进）聊天C。
    // 从聊天内部跳另一个聊天是 'content'——必须保留 B 那一层，否则返回会跳过
    // B 直接落回列表。此前 navigateToChat 的 origin 恒为 'navbar'，推 C 时把 B
    // 清掉了，用户按返回直接回到文件夹A。
    it('chat_to_chat_from_inside_keeps_the_previous_chat', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '100:0')];
      const got: StackAction = decidePush(stack, 'content', f('ChatPage', '200:0'));
      expect(got).assertEqual('push');
    });

    // 反面：从左栏列表选另一个会话仍然是"换一个看"，该清栈——不然在列表里
    // 点十个会话就叠十层，返回要按十次。
    it('chat_to_chat_from_the_list_still_replaces', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '100:0')];
      const got: StackAction = decidePush(stack, 'navbar', f('ChatPage', '200:0'));
      expect(got).assertEqual('clearAndPush');
    });

    // ——— 会话栈：允许堆叠多个窗口，但同一 chatId 只能有一个 ———

    // 空栈：直接推。
    it('chat_push_onto_an_empty_stack', 0, () => {
      const d = decideChatPush([], f('ChatPage', '10:0'));
      expect(d.action).assertEqual('push');
      expect(d.popCount).assertEqual(0);
    });

    // 不同会话：叠上去，不清栈——这是"允许多个聊天窗口"的核心。
    it('chat_stacks_a_different_chat', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ChatPage', '20:0')];
      const d = decideChatPush(stack, f('ChatPage', '30:0'));
      expect(d.action).assertEqual('push');
    });

    // 已在栈顶：什么都不做，别重复推一层一模一样的。
    it('chat_at_the_top_is_a_no_op', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ChatPage', '20:0')];
      const d = decideChatPush(stack, f('ChatPage', '20:0'));
      expect(d.action).assertEqual('skip');
    });

    // **同一 ID 已在栈里更深处：回到那一层，不新开**。
    // 栈 [A,B,C] 再打开 A → 出两层回到 A，而不是变成 [A,B,C,A]。
    it('chat_already_deeper_pops_back_to_it', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ChatPage', '20:0'), f('ChatPage', '30:0')];
      const d = decideChatPush(stack, f('ChatPage', '10:0'));
      expect(d.action).assertEqual('popTo');
      expect(d.popCount).assertEqual(2);
    });

    // 栈底那一层同理，只是要出的层数不同。
    it('chat_pop_count_counts_layers_above_the_target', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ChatPage', '20:0')];
      const d = decideChatPush(stack, f('ChatPage', '10:0'));
      expect(d.action).assertEqual('popTo');
      expect(d.popCount).assertEqual(1);
    });

    // 同一个群的不同话题是**两个**会话窗口，不该互相去重。
    it('chat_different_topics_are_different_windows', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', chatKey(10, 5))];
      const d = decideChatPush(stack, f('ChatPage', chatKey(10, 7)));
      expect(d.action).assertEqual('push');
    });

    // 栈里混着别的页面（资料页）时，按 name+key 比对，不会误判。
    it('chat_ignores_other_destinations_when_deduping', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ProfilePage', '10')];
      const d = decideChatPush(stack, f('ChatPage', '10:0'));
      expect(d.action).assertEqual('popTo');
      expect(d.popCount).assertEqual(1);
    });
  });
}
