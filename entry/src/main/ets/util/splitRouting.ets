// 分栏模式下的推栈决策。
//
// 抽成纯函数是为了让规则脱离 ArkUI 可单测：HdsNavigation 的分栏没有
// MultiNavigation 那套「左起右清栈」，规则得自己定，而这条规则一旦写错，
// 平板上点第二个会话就会在右栏叠一层、返回键退回上一个会话——是那种肉眼
// 走查很难稳定复现、上线后才被报上来的问题。

// 跳转从哪一栏发起。
//   navbar  左栏（会话列表、通知、深链——凡是"选一个会话"的语义都算）
//   content 右栏内部（会话里点「查看群资料」这种）
export type PushOrigin = 'navbar' | 'content';

// 决策结果。
//   skip          栈顶已经是同一个目标，什么都不做
//   clearAndPush  先清空右栏再推，保证右栏是替换不是叠加
//   push          正常入栈
export type StackAction = 'skip' | 'clearAndPush' | 'push';

// 栈的一层。key 区分同一个 name 下的不同实例。
export interface StackFrame {
  name: string;
  key: string;
}

// 会话的实例键。话题（forum topic）算不同实例：同一个群的不同话题是两个
// 会话界面，互相之间该能叠也该能替换。
export function chatKey(chatId: number, topicId: number): string {
  return `${chatId}:${topicId}`;
}

function sameFrame(a: StackFrame, b: StackFrame): boolean {
  return a.name === b.name && a.key === b.key;
}

// 只看栈顶。深层存在同名同键项不算「已经打开」——那时用户看到的是别的页面，
// 静默不动会让点击像是失灵了。
export function decidePush(
  stack: StackFrame[], origin: PushOrigin, target: StackFrame
): StackAction {
  const depth: number = stack.length;
  if (depth > 0 && sameFrame(stack[depth - 1], target)) {
    return 'skip';
  }
  return origin === 'navbar' ? 'clearAndPush' : 'push';
}

// ——— 会话栈的规则（和上面的 decidePush 不是一套，别混用）———
//
// **为什么不复用 decidePush**：settingsNav 和 MyProfilePage 明确依赖它的
// clearAndPush 让各自的栈深恒为 1（那几个文件里有多处注释钉着这一点）。
// 会话栈要的是相反的东西——能叠。所以单独一条规则，两边互不影响。
//
// **规则**：允许同时打开多个会话窗口，但**同一个会话只能有一个窗口**。
//   · 目标已在栈顶      → 什么都不做
//   · 目标在栈里更深处  → 出栈回到那一层，不新开重复的一层
//   · 其余              → 叠一层上去
//
// 和此前的差别：以前从会话列表选会话是 clearAndPush（右栏是替换不是叠加），
// 现在一律叠加。**代价要说清楚**：连着打开十个会话就是十层，返回要按十次。
// 换来的是"从聊天里点进另一个聊天，返回能回到上一个"这条链完整成立。
//
// 去重按 (name, key) 二元组：同一个群的不同话题 key 不同，是两个窗口，
// 互不去重——它们本来就是两个会话界面。
export interface ChatPushDecision {
  // 'skip' | 'popTo' | 'push'
  action: string;
  // popTo 时要出栈几层（目标之上压着多少层）；其余为 0。
  popCount: number;
}

export function decideChatPush(stack: StackFrame[], target: StackFrame): ChatPushDecision {
  const depth: number = stack.length;
  for (let i = depth - 1; i >= 0; i--) {
    if (!sameFrame(stack[i], target)) {
      continue;
    }
    // 找到了。在栈顶就什么都不做，否则把压在它上面的那些层出掉。
    const above: number = depth - 1 - i;
    return above === 0
      ? { action: 'skip', popCount: 0 }
      : { action: 'popTo', popCount: above };
  }
  return { action: 'push', popCount: 0 };
}
