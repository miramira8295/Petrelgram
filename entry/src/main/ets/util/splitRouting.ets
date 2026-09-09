// 分栏模式下的推栈决策。
//
// 抽成纯函数是为了让规则脱离 ArkUI 可单测：HdsNavigation 的分栏没有
// MultiNavigation 那套「左起右清栈」，规则得自己定，而这条规则一旦写错，
// 平板上点第二个会话就会在右栏叠一层、返回键退回上一个会话——是那种肉眼
// 走查很难稳定复现、上线后才被报上来的问题。

// 跳转从哪一栏发起。
//   navbar  左栏（会话列表、通知、深链——凡是"选一个会话"的语义都算）
//   content 右栏内部（会话里点「查看群资料」这种）
//   search  全局搜索页里点结果。**它和 navbar 的区别只有一条：返回要回到搜索页。**
//           所以既不清栈、也不去重——去重那一支会把压在目标之上的搜索页一起弹掉，
//           正是用户报的「有些能回到搜索结果、有些退回文件夹 tab」。
export type PushOrigin = 'navbar' | 'content' | 'search';

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
  // 'skip' | 'popTo' | 'push' | 'clearAndPush'
  action: string;
  // popTo 时要出栈几层（目标之上压着多少层）；其余为 0。
  popCount: number;
}

// replaceExisting —— **"选一个会话来看"这条路只保留一个详情页**。
//
// 【它修的是什么】用户报：Pad 左栏点多个会话，右栏叠出多个页面，返回要按很
// 多次。平板上左栏会话列表一直露着，"一律叠加"于是没有刹车。
//
// 【为什么不只在分栏下生效】用户明确要的是「点击会话列表进入的详情只保留一
// 个，其他路径不变」——判据是**从哪条路进来的**，不是屏幕多宽。手机上从列表
// 选会话同样该只有一个：那条路的语义本来就是"换一个会话看"。
//
// 【那"手机端允许多个会话详情叠加"呢】保留，它走的是另一条路：origin='content'
// ——从会话里点群链接/@提及/转发来源/资料页「发消息」进另一个会话。那是"再往
// 里走一层"，返回必须回到上一个会话（1.4.0 的回归就是把这条也清了）。
// 两句话不矛盾：一条说 navbar，一条说 content。
//
// 【调用方按什么传】origin='navbar' 的入口是：会话列表、归档以外的行、通知、
// 深链、通话记录、联系人、dock 迷你条。origin='content' 的入口在
// ChatPage / ForumTopicsPage / ProfilePage / ChatProfilePage 里，共 9 处。
// origin='search' 只有全局搜索页点结果这一处——它原来归在 navbar，2026-09-08
// 按用户要求改掉：「我在搜索找一个资源点进去后退出来怎么是文件夹 tab 页，
// 想要都可以返回上个页面」。
//
// 【为什么 skip 仍然优先】栈顶已经是目标时清空再推等于把同一页拆了重建：
// 白闪一下，滚动位置、草稿、正在播的语音全丢。点自己已经开着的那个会话是很
// 常见的一下（想回到它），必须是空操作。
export function decideChatPush(
  stack: StackFrame[], target: StackFrame, replaceExisting: boolean = false,
  allowDuplicate: boolean = false
): ChatPushDecision {
  const depth: number = stack.length;
  // allowDuplicate：**跳过整段去重**，无条件叠一层（origin='search' 专用）。
  //
  // 去重那一支（popTo）不看 origin：只要栈里有同一个会话，就把压在它上面的全弹掉
  // ——从搜索点进一个**之前开过**的会话时，被弹掉的正是搜索页自己。于是同样一个
  // 「点结果 → 返回」，会话没开过就回得到搜索、开过就回不到，用户看到的就是
  // "有时行有时不行"。搜索这条路允许同一个会话在栈上出现两次，换来返回语义确定。
  if (allowDuplicate) {
    return { action: 'push', popCount: 0 };
  }
  for (let i = depth - 1; i >= 0; i--) {
    if (!sameFrame(stack[i], target)) {
      continue;
    }
    // 找到了。在栈顶就什么都不做，否则把压在它上面的那些层出掉。
    const above: number = depth - 1 - i;
    if (above === 0) {
      return { action: 'skip', popCount: 0 };
    }
    // 替换语义下"目标在更深处"和"目标不在栈里"是同一件事：最后只剩目标这一
    // 层。走 popTo 而不是 clearAndPush，是因为出栈能复用那一页——结果一样，
    // 代价更小（不重建、不丢滚动位置）。
    return { action: 'popTo', popCount: above };
  }
  return replaceExisting
    ? { action: 'clearAndPush', popCount: 0 }
    : { action: 'push', popCount: 0 };
}
