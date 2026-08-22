// 这次更新检查该不该被节流跳过。
//
// **为什么不能只看时间**（issue #87）：应用自己升级之后，缓存里那条结果是
// **上一个版本**查出来的，无论多新都已经失效。而启动时 restoreCached() 会把它
// 原样铺到「关于」页上，自动检查又被 6 小时的间隔挡住——于是用户看到的最新
// 版本号和更新内容一直是旧的，非得手动点一次「检查更新」才刷新。
//
// 所以把"这条结果是哪个版本查的"一起存下来，版本对不上就当缓存失效、放行。
// 升级本来就是低频事件，多打一次网络请求可以忽略。
//
// checkedForVersion 为空 = 旧版本升上来、还没有这个字段。同样放行一次，
// 顺便把基准补上。
//
// 时间戳的两种脏数据都要挡：NaN（读坏了）和未来时间（用户改过系统时钟）。
// 任一成立就放行——**宁可多查一次，也不能让检查被永久挡死**：那会让用户再也
// 收不到更新提示，而这个错误自己不会恢复。
export function updateCheckThrottled(
  lastCheckAt: number,
  now: number,
  intervalMs: number,
  checkedForVersion: string,
  currentVersion: string
): boolean {
  if (checkedForVersion === '' || checkedForVersion !== currentVersion) {
    return false;
  }
  if (!Number.isFinite(lastCheckAt) || lastCheckAt <= 0) {
    return false;
  }
  const elapsed: number = now - lastCheckAt;
  if (elapsed < 0) {
    // 上次检查在"未来"：时钟被改过，缓存的时间戳不可信。
    return false;
  }
  return elapsed < intervalMs;
}
