import { StackFrame } from './splitRouting';

// 四个 tab 的路由栈注册表。
//
// 为什么需要它：Navigation 的栈由组件持有，而深链、通知点击、账号切换这三条
// 路径都在页面之外触发跳转，拿不到组件上下文。官方给的四种取栈方式里，
// @Provide/@Consume 被官方自己标注「有耦合，不推荐」，onReady 和
// queryNavigationInfo 都只在页面内可用——只有全局注册这一条走得通。
//
// 存 NavStackLike 而不是 NavPathStack：后者是 ArkUI 类型，宿主单测里构造不出来。
// NavPathStack 在结构上满足这个接口，运行时直接传进来即可。

export type TabKind = 'chat' | 'contacts' | 'settings';

// 对齐 NavPathInfo 里我们实际用到的两个字段。
export interface NavPathInfoLike {
  name: string;
  param?: Object;
}

// NavPathStack 的最小子集——只声明本项目用到的方法。
export interface NavStackLike {
  clear(animated?: boolean): void;
  pushPath(info: NavPathInfoLike): void;
  size(): number;
  getAllPathName(): string[];
  getParamByIndex(index: number): Object | undefined;
}

const stacks: Map<TabKind, NavStackLike> = new Map<TabKind, NavStackLike>();

// tab 的 HdsNavigation 建好栈之后调一次。重复注册以后者为准——账号切换会重建
// 组件树，旧栈必须被顶掉，否则跳转会打到一个已经下树的栈上。
export function registerStack(tab: TabKind, stack: NavStackLike): void {
  stacks.set(tab, stack);
}

export function stackOf(tab: TabKind): NavStackLike | undefined {
  return stacks.get(tab);
}

// 账号切换时用：旧账号的 chatId 在新账号下是另一个会话，栈里留着就是错的。
export function clearAllStacks(): void {
  stacks.forEach((s: NavStackLike): void => { s.clear(false); });
}

// 把真栈转成 decidePush() 吃的快照。keyOf 由调用方给——只有调用方知道自己
// 塞进 param 的是什么形状。
export function snapshotOf(
  stack: NavStackLike, keyOf: (name: string, param: Object | undefined) => string
): StackFrame[] {
  const out: StackFrame[] = [];
  const names: string[] = stack.getAllPathName();
  for (let i = 0; i < names.length; i++) {
    const name: string = names[i];
    out.push({ name: name, key: keyOf(name, stack.getParamByIndex(i)) });
  }
  return out;
}

// 仅供单测：模块级 Map 在用例之间共享，不重置会互相污染。
export function resetStacksForTest(): void {
  stacks.clear();
}
