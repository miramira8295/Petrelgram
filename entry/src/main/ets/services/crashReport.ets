// 崩溃记录：把上一次崩溃留下来，好让用户反馈问题时有东西可贴（issue #61）。
//
// 走 hiAppEvent 订阅 OS/APP_CRASH。官方《订阅崩溃事件（ArkTS）》写明这一条同时
// 覆盖 JsError 和 NativeCrash——后者正是 tdlib / ijkplayer 这些 .so 的信号崩溃，
// 是本应用最查不动的那一类。另外 @ohos.faultLogger 从 API 18 起已废弃，官方直接
// 指向 hiAppEvent，所以这不是二选一。
//
// 时序：应用没有主动捕获时，崩溃事件在**下次启动**才回调。所以观察者必须在
// onCreate 里、执行业务逻辑之前就注册好，否则那次崩溃的事件就漏了。
//
// **只留不含用户内容的字段。** 事件里还有两样东西刻意不碰：
//   hilog —— 崩溃前最多 1000 行本应用的流水日志。我们的日志里有 [StoreDiag]
//            这类消息 id，以后也难保不会有别的，整段留下来就是把聊天痕迹落盘。
//   external_log —— 故障日志全文，同样含 HiLog 段。
// 留下的是时间、版本、崩溃类型、异常名/信息/堆栈——堆栈是我们自己的代码路径，
// 不含用户数据，而它恰恰是唯一真正有用的部分。
//
// 这里只负责**记下来**，不发送。往哪儿报是另一件事，需要单独决定。

import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

// 留几条。崩溃是低频事件，留太多只是占地方；留太少又会被一次连环崩溃冲掉。
const MAX_RECORDS: number = 10;
// 堆栈截断长度。够定位到我们自己的帧，又不至于把整个 so 的地址表存下来。
const MAX_STACK_CHARS: number = 4000;
const FILE_NAME: string = 'crash-records.json';

// 官方示例里这两个配置各有版本门槛，照它的写法用 sdkApiVersion 挡。
const EVENT_CONFIG_API: number = 20;
const EVENT_POLICY_API: number = 24;

export interface CrashRecord {
  // 崩溃发生的时间戳（毫秒）。
  time: number;
  // 'JsError' | 'NativeCrash'
  crashType: string;
  appVersion: string;
  // 崩溃时应用在不在前台。前台崩是用户看得见的，后台崩往往是另一类问题。
  foreground: boolean;
  // 进程存活了多久（秒）。极短就意味着启动崩溃——1.3.6 那次就是。
  lifeTimeSec: number;
  exceptionName: string;
  exceptionMessage: string;
  stack: string;
}

let recordsPath: string = '';

function readAll(): CrashRecord[] {
  if (recordsPath === '' || !fs.accessSync(recordsPath)) {
    return [];
  }
  try {
    const stat = fs.statSync(recordsPath);
    const buffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(recordsPath, fs.OpenMode.READ_ONLY);
    fs.readSync(file.fd, buffer);
    fs.closeSync(file);
    const text: string = String.fromCharCode(...new Uint8Array(buffer));
    const parsed = JSON.parse(text) as CrashRecord[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    console.error(`crashReport.readAll failed: ${e}`);
    return [];
  }
}

function writeAll(records: CrashRecord[]): void {
  if (recordsPath === '') {
    return;
  }
  try {
    const file = fs.openSync(recordsPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, JSON.stringify(records));
    fs.closeSync(file);
  } catch (e) {
    console.error(`crashReport.writeAll failed: ${e}`);
  }
}

function textOf(value: Object | undefined): string {
  return value === undefined || value === null ? '' : `${value}`;
}

function recordOf(params: Record<string, Object>): CrashRecord {
  const exception = params['exception'] as Record<string, Object> | undefined;
  const stack: string = exception !== undefined ? textOf(exception['stack']) : '';
  return {
    time: Number(textOf(params['time'])) || 0,
    crashType: textOf(params['crash_type']),
    appVersion: textOf(params['bundle_version']),
    foreground: `${params['foreground']}` === 'true',
    lifeTimeSec: Number(textOf(params['process_life_time'])) || 0,
    exceptionName: exception !== undefined ? textOf(exception['name']) : '',
    exceptionMessage: exception !== undefined ? textOf(exception['message']) : '',
    stack: stack.length > MAX_STACK_CHARS ? stack.substring(0, MAX_STACK_CHARS) : stack
  };
}

// 在 onCreate 里、业务逻辑之前调用。
export function startCrashWatch(context: common.UIAbilityContext): void {
  recordsPath = `${context.filesDir}/${FILE_NAME}`;

  // 崩溃日志规格：把日志截到 1MB，别让一次崩溃写出一个巨大的文件。
  // 官方示例同样用 sdkApiVersion 挡着这两段——枚举/接口都只在函数体里碰。
  if (deviceInfo.sdkApiVersion >= EVENT_CONFIG_API) {
    const config: Record<string, hiAppEvent.ParamType> = {
      'log_file_cutoff_sz_bytes': 1024000,
      'simplify_vma_printing': true
    };
    hiAppEvent.setEventConfig(hiAppEvent.event.APP_CRASH, config).catch((e: Error): void => {
      console.error(`crashReport.setEventConfig failed: ${e.message}`);
    });
  }
  if (deviceInfo.sdkApiVersion >= EVENT_POLICY_API) {
    // 页面切换轨迹：崩在哪个页面比堆栈更快指向复现路径，而它只含页面 URL，
    // 不含任何用户内容。
    const policy: hiAppEvent.EventPolicy = {
      'appCrashPolicy': { 'pageSwitchLogEnable': true }
    };
    hiAppEvent.configEventPolicy(policy).catch((e: Error): void => {
      console.error(`crashReport.configEventPolicy failed: ${e.message}`);
    });
  }

  const watcher: hiAppEvent.Watcher = {
    name: 'petrelgramCrashWatcher',
    appEventFilters: [{ domain: hiAppEvent.domain.OS, names: [hiAppEvent.event.APP_CRASH] }],
    onReceive: (_domain: string, groups: Array<hiAppEvent.AppEventGroup>): void => {
      const next: CrashRecord[] = readAll();
      for (const group of groups) {
        for (const info of group.appEventInfos) {
          next.push(recordOf(info.params as Record<string, Object>));
        }
      }
      // 新的在前，超出上限的丢最旧的。
      next.sort((a: CrashRecord, b: CrashRecord): number => b.time - a.time);
      writeAll(next.slice(0, MAX_RECORDS));
    }
  };
  try {
    hiAppEvent.addWatcher(watcher);
  } catch (e) {
    console.error(`crashReport.addWatcher failed: ${e}`);
  }
}

export function crashRecords(): CrashRecord[] {
  return readAll();
}

export function clearCrashRecords(): void {
  writeAll([]);
}
