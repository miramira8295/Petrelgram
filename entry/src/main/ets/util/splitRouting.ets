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
