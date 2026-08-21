// 崩溃订阅（主进程侧）。存储与上报在 services/crashRecordStore——那一层的
// import 被刻意压到最少，因为扩展进程也要加载它，见那边的文件头。
//
// 走 hiAppEvent 订阅 OS/APP_CRASH。官方《订阅崩溃事件（ArkTS）》写明这一条同时
// 覆盖 JsError 和 NativeCrash——后者正是 tdlib / ijkplayer 这些 .so 的信号崩溃，
// 是本应用最查不动的那一类。另外 @ohos.faultLogger 从 API 18 起已废弃，官方直接
// 指向 hiAppEvent，所以这不是二选一。
//
// 时序：应用没有主动捕获时，崩溃事件在**下次启动**才回调。所以观察者必须在
// onCreate 里、执行业务逻辑之前就注册好，否则那次崩溃的事件就漏了。
//
// 光有主进程的观察者救不了"启动就崩"：模块级崩溃发生在 import 阶段，onCreate
// 的函数体根本执行不到（v1.3.6 那次正是如此）。注意**记录本身不会丢**——采集和
// 落盘是系统做的，只要之前有一次正常启动注册过订阅条件，事件就已经存进沙箱了。
// 丢的是"取出来"这一步。官方对此的答案是 FaultLogExtensionAbility：崩溃 30 分钟
// 后系统单独拉起一个进程来处理，不依赖应用能启动。
//
// 为此注册**两个**观察者：
//   A（NORMAL_WATCHER）  正常重启时处理事件；
//   B（DELAYED_WATCHER） 空实现，只为把订阅条件留在沙箱里，让扩展进程接得上。
// 两者名字必须不同，否则后注册的会覆盖前一个的过滤条件、事件直接丢（官方
// 《使用FaultLogExtensionAbility订阅事件》的"部分事件丢失"一节）。

import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { flushCrashUploads, ingestCrashParams, initCrashStore } from './crashRecordStore';
import { logE } from '../util/log';

// 扩展进程里用的是 DELAYED 这个名字，两边必须一致。
export const NORMAL_WATCHER: string = 'petrelgramCrashWatcher';
export const DELAYED_WATCHER: string = 'petrelgramCrashWatcherDelayed';

// 官方示例里这两个配置各有版本门槛，照它的写法用 sdkApiVersion 挡。
const EVENT_CONFIG_API: number = 20;
const EVENT_POLICY_API: number = 24;

function paramsOf(groups: Array<hiAppEvent.AppEventGroup>): Array<Record<string, Object>> {
  const out: Array<Record<string, Object>> = [];
  for (const group of groups) {
    for (const info of group.appEventInfos) {
      out.push(info.params as Record<string, Object>);
    }
  }
  return out;
}

// 在 onCreate 里、业务逻辑之前调用。
export function startCrashWatch(context: common.UIAbilityContext): void {
  initCrashStore(context.filesDir);

  // 崩溃日志规格：把日志截到 1MB，别让一次崩溃写出一个巨大的文件。
  if (deviceInfo.sdkApiVersion >= EVENT_CONFIG_API) {
    const config: Record<string, hiAppEvent.ParamType> = {
      'log_file_cutoff_sz_bytes': 1024000,
      'simplify_vma_printing': true
    };
    hiAppEvent.setEventConfig(hiAppEvent.event.APP_CRASH, config).catch((e: Error): void => {
      logE(`crashReport.setEventConfig failed: ${e.message}`);
    });
  }
  if (deviceInfo.sdkApiVersion >= EVENT_POLICY_API) {
    // 页面切换轨迹：崩在哪个页面比堆栈更快指向复现路径，而它只含页面 URL，
    // 不含任何用户内容。
    const policy: hiAppEvent.EventPolicy = {
      'appCrashPolicy': { 'pageSwitchLogEnable': true }
    };
    hiAppEvent.configEventPolicy(policy).catch((e: Error): void => {
      logE(`crashReport.configEventPolicy failed: ${e.message}`);
    });
  }

  const filters: hiAppEvent.AppEventFilter[] =
    [{ domain: hiAppEvent.domain.OS, names: [hiAppEvent.event.APP_CRASH] }];
  const normal: hiAppEvent.Watcher = {
    name: NORMAL_WATCHER,
    appEventFilters: filters,
    onReceive: (_domain: string, groups: Array<hiAppEvent.AppEventGroup>): void => {
      ingestCrashParams(paramsOf(groups));
    }
  };
  // B 是空实现。它唯一的作用是把订阅条件留在沙箱里，好让应用起不来时扩展进程
  // 接得上（同名覆盖）。A 已经处理过的事件，B 在这里空转一次消耗掉。
  const delayed: hiAppEvent.Watcher = {
    name: DELAYED_WATCHER,
    appEventFilters: filters,
    onReceive: (_domain: string, _groups: Array<hiAppEvent.AppEventGroup>): void => {}
  };
  try {
    hiAppEvent.addWatcher(normal);
    hiAppEvent.addWatcher(delayed);
  } catch (e) {
    logE(`crashReport.addWatcher failed: ${e}`);
  }
  // 上次没发出去的补发（当时网络不通、或者进程被切断）。
  flushCrashUploads();
}
