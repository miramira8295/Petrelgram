// Each invocation owns its detached player and sources. A reused component may
// already have new fields by the time this native job completes.
//
// 【2026-11-08 崩溃修复】这里原本在 beginRelease（原生异步 release）失败时再补一次
// 同步 release()，**这段已经删掉**。理由：
//
//   崩溃栈（平板/手机各三条，hisysevent FAULT 里拿到的完整 native 栈）是
//     #00 memcpy
//     #01 libijkplayer_napi.so (IJKPlayerNapiProxy::IjkMediaPlayer_release()+148)
//     #02 libace_napi.z.so (NativeAsyncWork::AsyncWorkCallback+484)
//   另一形态是 terminating due to uncaught exception of type std::bad_alloc，
//   同一帧 IjkMediaPlayer_release()——对已经释放的对象里的 std::string 做拷贝。
//
//   也就是「同一个 native player 被 release 了两次」。异步 release 返回 false /
//   reject 只说明**这一次调用没走完**，不代表原生对象还在：work 已经入队、随后
//   组件销毁或上下文失效时最容易走到这里，这时再调同步 release() 就是对已释放
//   对象动手。
//
//   宁可让这一个 player 泄漏（几十 KB，进程退出即回收），也不能 double free 崩掉
//   整个 App：泄漏可以事后修，闪退会直接丢掉用户的登录态和未发送消息。
//
// 数据源的关闭照旧——它和 native player 的释放是两个对象，失败时也会被逐个
// try 掉，不会因为一个源关不掉就跳过其余的。
//
// 【2026-11-08 第二处修复：全应用串行】
//
// 上面的栈里，崩溃线程叫 `OS_FFRT__`——原生 release 跑在 fftf 线程池里，而
// `IjkMediaPlayer_release()` 里做的是对某个 std::string 的**拷贝构造**，抛
// std::bad_alloc 说明它读的那块内存已经被别的线程释放或改写了。同一个页面上
// 一屏贴纸 / 多个视频同时卸载时，会有十几个 release 几乎同时进原生代理，
// 代理内部那张「xcomponentId → player」的表就被并发读写了。
//
// 所以这里再加一道**全应用**的闸：所有 ijk 播放器的原生释放排成一条链，上一次
// 真的完成（releaseAsync 的 Promise 落地）之后才放下一次进去。代价是卸载变慢
// 几十毫秒（本来也是延迟执行的），换来的是不再并发碰那张表。
let nativeReleaseChain: Promise<void> = Promise.resolve();

// 【2026-11-09 第三处修复：不再使用插件的 releaseAsync】
//
// 崩溃栈又拿到了两版，形态一致：
//   #00 memcpy
//   #01 libijkplayer_napi.so (IJKPlayerNapiProxy::IjkMediaPlayer_release()+148)
//   #02 libace_napi.z.so (NativeAsyncWork::AsyncWorkCallback+484)
//
// 读了插件源码（.ijk-probe/cpp）后根因是**插件自己的异步壳有悬垂引用**：
// `IJKPlayerNapi::releaseAsync()` 把 `CommonCallBackInfo`（只存 xcomponentId）
// 丢进 napi 线程池，执行时再 `IJKPlayerNapi::getInstance(id)` 取回实例并调
// `IjkMediaPlayer_release()`。这个回调排队之后、真正执行之前，只要那个实例
// 已经被销毁（页面切走、组件卸载、JS 侧对象回收），`getInstance(id)` 拿到的
// 就是失效对象，`IjkMediaPlayer_release()` 里第一件事——把 `id_` 这个
// std::string 按值拷一份传给 `get_media_player(id_)`——就会读已经释放的内存。
// 所以崩的永远是 memcpy / basic_string 拷贝，而且线程名是 OS_FFRT__。
//
// 这不是我们串行化没做好，而是**只要还走 releaseAsync，就永远存在这个窗口**。
// 插件同时导出了同步的 `release()`（`IjkMediaPlayer_release()` 在调用线程里
// 立刻执行），那时实例一定还活着，不存在“排队后又死掉”的窗口。
//
// 代价：释放会在 JS 线程上同步跑完（关流 + 减引用，量级是毫秒）。用下面的
// 串行链保证同一时刻只有一次在跑，避免连续卸载把主线程顶住。
let nativeSyncReleaseChain: Promise<void> = Promise.resolve();

/** 把一次**同步**原生释放排进全局串行链（替代 releaseAsync）。 */
export function enqueueNativeReleaseSync(beginRelease: (() => void) | null,
  closeSources: (() => void)[]): Promise<void> {
  const run: Promise<void> = nativeSyncReleaseChain.then((): void => {
    if (beginRelease !== null) {
      try {
        beginRelease();
      } catch (error) {
        // 同步释放也可能抛：记一笔，绝不再补第二次释放。
      }
    }
    for (const close of closeSources) {
      try {
        close();
      } catch (error) {
      }
    }
  }).catch((): void => {});
  nativeSyncReleaseChain = run;
  return run;
}

/**
 * 把一次原生释放排进全局串行链。返回的 Promise 在**这一次**释放结束后落地，
 * 调用方可以据此减少存活计数。
 */
export function enqueueNativeRelease(beginRelease: (() => Promise<boolean>) | null,
  closeSources: (() => void)[]): Promise<void> {
  const run: Promise<void> = nativeReleaseChain
    .then((): Promise<void> => releaseVideoResources(beginRelease, closeSources))
    // 一次失败不能把整条链卡死：吞掉错误继续排下一项。
    .catch((): void => {});
  nativeReleaseChain = run;
  return run;
}

export async function releaseVideoResources(beginRelease: (() => Promise<boolean>) | null,
  closeSources: (() => void)[]): Promise<void> {
  if (beginRelease !== null) {
    try {
      if (!await beginRelease()) {
        // 原生侧报告没释放成功：**不再补同步 release**（见文件头注释）。
        // 走到这里说明原生对象的归属已经不清楚了，交给它自己的生命周期收尾。
        throw new Error('Native video release did not complete');
      }
    } catch (error) {
      // 只记日志，不动原生对象。
    }
  }
  let failed: boolean = false;
  for (const close of closeSources) {
    try {
      close();
    } catch (error) {
      failed = true;
    }
  }
  if (failed) {
    throw new Error('Video source cleanup failed');
  }
}
