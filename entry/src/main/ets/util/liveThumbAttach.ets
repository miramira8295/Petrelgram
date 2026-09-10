// 「这次 spec 变化要不要重挂缩略图订阅」的判据。
//
// 抽成纯函数是为了能在宿主上跑回归测试——和同目录的 liveThumbPath 同一个理由。
// 这里出错的代价是**图配错文**：气泡的文字是新消息的，图还是上一条的。
//
// 【为什么需要它】LiveThumbImage 的 6 个独立 @Param 在 2026-09-03 合并成了一个
// spec 对象（省 updateStateVars 的开销），但两个自愈用的 @Monitor 仍写着合并前
// 的参数名 'fileId' / 'initialPath'——组件里已经没有这两个成员了。ArkUI 对解析
// 不了的监听路径既不报编译错也不打运行时告警，于是自愈**静默失效**了一周。
//
// 2026-09-10 真机实测把它钉死：50 次 attach，monitorFires 恒为 0；同一次滑动里
// 抓到 7 次 attachedFileId ≠ spec.fileId，且挂着的正是相邻那一行的文件
//   inst=9 挂 14667（该 14680）／inst=18 挂 14680（该 14929）／inst=25 挂 14929（该 14950）
// ——一个复用壳挂的恰好是另一行的文件。
//
// 【为什么监听 spec 整体而不是 'spec.fileId'】LiveThumbSpec 是普通 interface，
// 没有 @ObservedV2 / @Trace，嵌套路径的观测没有保证；而调用点每次重建都传新的
// 对象字面量，监听根对象一定触发。多触发不要紧——判据在这里，同身份直接早退。

export function shouldReattachThumb(
  specFileId: number,
  specInitialPath: string,
  attachedFileId: number,
  currentPath: string
): boolean {
  // 挂着的文件和该挂的不是一个，一定重挂。
  // 也覆盖两种边界：attachedFileId === -1（回收过还没重挂）、以及
  // 「可下载文件 ⇄ 纯路径模式」的互相切换。
  if (attachedFileId !== specFileId) {
    return true;
  }
  // fileId=0 没有可订阅的文件，身份就是 initialPath 本身：画着的不是本行自带的
  // 那张，就得重挂（本地发出的图、原图回填都走这条）。
  if (specFileId === 0) {
    return currentPath !== specInitialPath;
  }
  // 同一个可下载文件：路径由 mediaThumbChannel 自己推过来，不必重挂。
  // 退订+重订阅是滚动时的每行常数开销，能省则省。
  return false;
}
