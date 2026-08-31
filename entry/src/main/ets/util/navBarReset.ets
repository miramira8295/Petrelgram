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
