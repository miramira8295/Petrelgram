// 应用起不来时的救命通道。
//
// 崩溃发生 30 分钟后，系统会单独拉起这个进程，把沙箱里还没被处理的故障事件
// 交给同名观察者。整个应用主进程都不参与——这正是"用户打不开了"那种情况下
// 唯一还能把崩溃信息取出来的路径。
//
// 三条硬约束（官方《使用FaultLogExtensionAbility订阅事件》）：
//   1. 拉起后只有 10s；
//   2. **它自己崩溃就不会再被拉起**，所以 import 链必须干净——这里只引
//      crashRecordStore，那个模块的依赖是刻意压到最少的（没有 ArkUI）；
//   3. 观察者名字必须和主进程里那个空实现的一致，否则接不上。

import { FaultLogExtensionAbility, hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { flushCrashUploads, ingestCrashParams, initCrashStore } from '../services/crashRecordStore';

// 和 services/crashReport 里的 DELAYED_WATCHER 同名。**不从那边 import**：
// 那个模块会拉进 hiAppEvent 之外的东西，而这里越少越好。改名时两处一起改。
const DELAYED_WATCHER: string = 'petrelgramCrashWatcherDelayed';

export default class CrashFaultLogAbility extends FaultLogExtensionAbility {
  onFaultReportReady(): void {
    try {
      initCrashStore(this.context.filesDir);
    } catch (e) {
      console.error(`CrashFaultLogAbility initCrashStore failed: ${e}`);
      return;
    }
    hiAppEvent.addWatcher({
      name: DELAYED_WATCHER,
      appEventFilters: [{ domain: hiAppEvent.domain.OS, names: [hiAppEvent.event.APP_CRASH] }],
      onReceive: (_domain: string, groups: Array<hiAppEvent.AppEventGroup>): void => {
        const params: Array<Record<string, Object>> = [];
        for (const group of groups) {
          for (const info of group.appEventInfos) {
            params.push(info.params as Record<string, Object>);
          }
        }
        ingestCrashParams(params);
      }
    });
  }

  onDisconnect(): void {
    // 10s 到了。没发完的留在文件里，下次启动或下次拉起时补发。
    flushCrashUploads();
  }
}
