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

    // ——— 「选一个会话来看」这条路只保留一个详情页 ———
    //
    // 用户要的是「点击会话列表进入的详情只保留一个，其他路径不变」。判据是
    // **从哪条路进来的**（origin='navbar'）而不是屏幕多宽，手机平板一致。

    it('navbar_replaces_instead_of_stacking', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      const d = decideChatPush(stack, f('ChatPage', '20:0'), true);
      expect(d.action).assertEqual('clearAndPush');
      expect(d.popCount).assertEqual(0);
    });

    it('navbar_keeps_exactly_one_detail_page', 0, () => {
      // 连点三个会话：每一次都是替换，详情永远只有一层。
      const first = decideChatPush([], f('ChatPage', '10:0'), true);
      expect(first.action).assertEqual('clearAndPush');
      const second = decideChatPush([f('ChatPage', '10:0')], f('ChatPage', '20:0'), true);
      expect(second.action).assertEqual('clearAndPush');
      const third = decideChatPush([f('ChatPage', '20:0')], f('ChatPage', '30:0'), true);
      expect(third.action).assertEqual('clearAndPush');
    });

    // 点自己已经开着的那一个：**必须是空操作**。清空再推等于把同一页拆了重建，
    // 白闪一下，滚动位置、草稿、正在播的语音全丢。
    it('navbar_still_skips_the_chat_already_on_top', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '20:0')];
      const d = decideChatPush(stack, f('ChatPage', '20:0'), true);
      expect(d.action).assertEqual('skip');
    });

    // 目标在更深处时走 popTo 而不是 clearAndPush：结果一样（只剩目标那一层），
    // 但出栈能复用那一页，不重建、不丢滚动位置。
    it('navbar_pops_back_rather_than_rebuilding', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('ChatPage', '20:0')];
      const d = decideChatPush(stack, f('ChatPage', '10:0'), true);
      expect(d.action).assertEqual('popTo');
      expect(d.popCount).assertEqual(1);
    });

    // **「其他路径不变」的那一半**：从会话里点群链接/@提及/转发来源/资料页
    // 「发消息」进另一个会话仍然叠加。这就是"手机端允许多个会话详情叠加"说的
    // 那条路——返回必须回到上一个会话（1.4.0 的回归正是把这条也清了）。
    it('content_origin_still_stacks', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      const d = decideChatPush(stack, f('ChatPage', '20:0'), false);
      expect(d.action).assertEqual('push');
    });

    // 默认值必须是 false（= 叠加）。省略第三参的调用点若哪天多起来，默认值
    // 一旦翻成 true 就会静默地把 content 那条路也拖进替换。
    it('default_is_still_stacking', 0, () => {
      const stack: StackFrame[] = [f('ChatPage', '10:0')];
      expect(decideChatPush(stack, f('ChatPage', '20:0')).action).assertEqual('push');
    });
    // ——— origin='search'：返回必须回到搜索页（2026-09-08 用户反馈）———
    //
    // 用户报「我在搜索找一个资源点进去后退出来怎么是文件夹 tab 页……有些可以回到
    // 搜索结果，有些会退回到文件夹」。原因是搜索原本按 navbar 走：会话没开过就
    // clearAndPush（整条栈连搜索页一起清），开过就 popTo（把压在目标之上的搜索页
    // 弹掉）——两条路都保不住搜索页，而走哪条取决于"之前开没开过"，所以时灵时不灵。

    it('search_push_keeps_the_stack_even_when_target_is_absent', 0, () => {
      // 第四个参数 allowDuplicate=true 就是 origin='search'
      const stack: StackFrame[] = [f('GlobalSearchPage', 's')];
      const d = decideChatPush(stack, f('ChatPage', '30:0'), false, true);
      expect(d.action).assertEqual('push');
      expect(d.popCount).assertEqual(0);
    });

    it('search_push_does_not_pop_when_target_is_already_deeper', 0, () => {
      // 这一条是"有些退回文件夹"的那一半：目标之前开过、搜索页压在它上面。
      const stack: StackFrame[] = [f('ChatPage', '30:0'), f('GlobalSearchPage', 's')];
      const d = decideChatPush(stack, f('ChatPage', '30:0'), false, true);
      expect(d.action).assertEqual('push');
      expect(d.popCount).assertEqual(0);
    });

    it('search_push_never_clears_even_with_replaceExisting', 0, () => {
      // allowDuplicate 优先于 replaceExisting：搜索这条路任何情况都不清栈。
      const stack: StackFrame[] = [f('ChatPage', '10:0'), f('GlobalSearchPage', 's')];
      expect(decideChatPush(stack, f('ChatPage', '20:0'), true, true).action).assertEqual('push');
    });

    it('navbar_and_content_behaviour_is_unchanged', 0, () => {
      // 回归护栏：新参数默认 false，旧两种 origin 的判定一个字都不能变。
      const stack: StackFrame[] = [f('ChatPage', '30:0'), f('ChatPage', '40:0')];
      // navbar：目标在更深处 → 出栈回到它
      expect(decideChatPush(stack, f('ChatPage', '30:0'), true).action).assertEqual('popTo');
      // content：同样去重（"已经开着的不再新开一层"）
      expect(decideChatPush(stack, f('ChatPage', '30:0'), false).action).assertEqual('popTo');
      // navbar 且目标不在栈里 → 清栈只留目标
      expect(decideChatPush(stack, f('ChatPage', '50:0'), true).action).assertEqual('clearAndPush');
    });

  });
}
