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

// 【原声明，保留作为历史】`export type TabKind = 'chat' | 'contacts' | 'settings';`
// ——个人资料页签当时不是路由容器，它的唯一子页（AccountEditPage）只能落在设置
// 栈上，代价是点「编辑信息」会把页签切到设置。加上 'profile' 之后它有了自己的
// 栈，编辑页回到「盖在个人资料页签之上、返回就回个人资料」的迁移前行为。
// 个人资料页签强制单栏（.mode(NavigationMode.Stack)），推目的地就是整页替换。
export type TabKind = 'chat' | 'contacts' | 'settings' | 'profile';

// 对齐 NavPathInfo 里我们实际用到的两个字段。
export interface NavPathInfoLike {
  name: string;
  param?: Object;
}

// NavPathStack 的最小子集——只声明本项目用到的方法。
export interface NavStackLike {
  clear(animated?: boolean): void;
  pushPath(info: NavPathInfoLike): void;
  // 出栈一层。返回值声明成 void 而不是 NavPathInfoLike：真栈的
  // pop(animated?): NavPathInfo | undefined 在结构上仍然满足 void 返回
  //（返回值更具体是允许的），而 NavPathInfo.param 是 unknown、和
  // NavPathInfoLike.param 的 Object|undefined 对不上，照抄会让 SettingsPage 里
  // 那个 as NavStackLike 的转换失败。调用方本来也不用这个返回值。
  pop(animated?: boolean): void;
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

// 栈里**最靠上**的那个同名目的地带的 param，没有就 undefined。
//
// 【为什么需要它】目的页在 `aboutToAppear` 里拿不到自己的栈：官方生命周期写明
// 「aboutToAppear 在 build() 执行之前调用」，而栈是 `NavDestination.onReady()`
// 交过来的，onReady 在 build 里——那一刻 `this.navStack` 必然还是 null
// （官方同处还写着「不建议在 aboutToAppear 中使用栈操作，此时页面还未构建完成」）。
// 于是「带参数进来、进页面就自动跑一次」这类逻辑必须另有取参数的路子：全局注册表
// 里的栈是同一个，而且在 pushPath 之前就注册好了。
//
// 真实事故：话题标签 `#tag` 点进全局搜索，78026c9 把搜索页从 router.pushUrl 改成
// tab 栈的 pushPath 之后，搜索页只剩 `router.getParams()` 这条兜底——那是 router
// 的参数，pushPath 根本不往那儿放，于是关键词丢了、进去不自动搜（1.4.3 起）。
//
// 取最靠上的一个而不是第一个：同名目的地可以叠多层（从搜索结果进会话、再点标签
// 又推一个搜索页），后推的那个才是本次进来的。
export function lastParamOfDest(stack: NavStackLike, name: string): Object | undefined {
  const names: string[] = stack.getAllPathName();
  for (let i: number = names.length - 1; i >= 0; i--) {
    if (names[i] === name) {
      return stack.getParamByIndex(i);
    }
  }
  return undefined;
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
