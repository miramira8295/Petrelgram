// 页签重新挂树时，它的 navBar 该不该算可见。
//
// **为什么需要复位。** 四个页签各自把 navBar 的显隐写进 AppStorage，dock（底部
// 页签栏）据此决定藏不藏。而 onNavBarStateChange **只在变化时触发**，不会在页面
// 重建时补一发——所以上一轮留在 AppStorage 里的 false 会让 dock 永久藏着。
//
// **为什么不能一律复位成 true。** 原来的写法是 aboutToAppear 里直接写 true，
// 理由是「本页刚建好时栈必然是空的」。这个前提在整页 router 跳转下不成立：
//
//   聊天详情（页签栈里的 NavDestination）
//     → router.pushUrl 打开应用内浏览器（pages/web/InAppBrowserPage 是整页
//       router 页，不是 NavDestination）
//     → router.back() 回来，底下这棵树重建，aboutToAppear 又跑一次
//     → 强行写 true，dock 盖在还开着的聊天详情页上，和输入框叠在一起
//
// 用户报的正是这个：「打开网页浏览器，关闭的时候 dock 就会出现」。四个页签写法
// 相同，所以从设置里点链接再回来也一样。
//
// 正确的复位值来自**栈的真实状态**，不是一个假设：分栏（平板）下左栏常驻，恒
// 可见；单栏下栈空才可见。
export function navBarVisibleOnAppear(splitLayout: boolean, stackDepth: number): boolean {
  if (splitLayout) {
    return true;
  }
  return stackDepth <= 0;
}

// 运行中也以布局与栈深为准。HdsNavigation 在页签切到后台时会报告 false，即使
// 它仍停在栈空的根页；若把这个临时报告存下来，用户下次点该页签时 dock 会先按
// 陈旧的 false 消失。反方向也一样：整页 router 退掉时可能报告 true，但单栏栈里
// 仍压着详情页。reported 只是一帧渲染状态，不是 dock 的业务状态。
export function navBarVisibleOnChange(_reported: boolean, splitLayout: boolean, stackDepth: number): boolean {
  return navBarVisibleOnAppear(splitLayout, stackDepth);
}

// dock（底部/侧边页签栏）该不该显示。**以取用那一刻的布局与栈深为准**，而不是
// 相信各页签早先算好、存进 AppStorage 的那个布尔。
//
// 【为什么不能信那个布尔】它由各页签的 onNavBarStateChange 写入，而那个回调
// **只在变化时触发**。它算出来的值依赖两个可能滞后的输入：
//   · screenW / screenH —— 由 EntryAbility 的 windowSizeChange 另行刷新，
//     两条路的先后无定（SettingsPage.onWindowResized 的注释里写过这一条）；
//   · stack.size()     —— 出栈时框架是先报「navBar 可见」还是先更新栈，未定。
// 任一个在那一帧是旧值，算出的 false 就**永久留在 AppStorage 里**——不会有第二
// 次回调来纠正它（值没变，页面那边的写入还带着"同值不写"的闸）。用户下次点该
// 页签，dock 就按这个陈旧的 false 消失了（用户实报「dock 的设置点击偶尔会消失」）。
//
// 现算就没有这个窗口：页签一切换就重新读一次真栈。
//
// stackDepth 为 undefined = 该页签还没被建过、栈尚未注册（Tabs 是懒建的），
// 此时没有真值可读，只能用存下来的布尔兜底。
export function dockVisibleForTab(
  splitLayout: boolean, stackDepth: number | undefined, storedFlag: boolean
): boolean {
  if (stackDepth === undefined) {
    return storedFlag;
  }
  return navBarVisibleOnAppear(splitLayout, stackDepth);
}
