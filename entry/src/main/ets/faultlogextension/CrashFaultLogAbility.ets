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
//
// ---- 底线版本（API 20）安全性论证 ----
//
// FaultLogExtensionAbility 起始 21，而 compatibleSdkVersion 是 20。这里**不加**
// 版本判断，因为没有一条代码路径需要它：
//
//   运行时：本文件唯一的雷是下面的 extends——20 上基类符号是 undefined，模块
//   一加载就抛。但本模块只被 faultLog 扩展进程加载，而拉起该进程的系统子系统
//   21 才存在；20 上进程根本不会被拉起，这行永远不执行。退一万步真被拉起，
//   它也在独立进程里（module.json5 的 :faultLog），炸了只是这条补报通道没有，
//   主进程一根汗毛都伤不到。ArkTS 也不允许条件 extends，这里没有更强的写法。
//
//   主进程：从不 import 本模块；crashReport 里 15+/22+ 的配套接口各有闸门。
//
//   安装期：module.json5 里 type: "faultLog" 的声明不是代码能拦的层。旁证是
//   构建链明知 compatibleSdkVersion=20、extension 要 21，只给 WARN 不给 ERROR
//   ——工具链把"必然装不上"的问题都做成硬错误（如 00303 一族），把"需要
//   运行时自护"的做成警告。真要百分百确认 20 上装得上，只能上真机/模拟器。

import { FaultLogExtensionAbility, hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { flushCrashUploads, ingestCrashParams, initCrashStore } from '../services/crashRecordStore';
import { logE } from '../util/log';

// 和 services/crashReport 里的 DELAYED_WATCHER 同名。**不从那边 import**：
// 那个模块会拉进 hiAppEvent 之外的东西，而这里越少越好。改名时两处一起改。
const DELAYED_WATCHER: string = 'petrelgramCrashWatcherDelayed';

export default class CrashFaultLogAbility extends FaultLogExtensionAbility {
  onFaultReportReady(): void {
    try {
      initCrashStore(this.context.filesDir);
    } catch (e) {
      logE(`CrashFaultLogAbility initCrashStore failed: ${e}`);
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
