// 崩溃记录的存储与上报。**这个模块的 import 是刻意压到最少的。**
//
// FaultLogExtensionAbility 会在一个独立进程里加载它，而那个进程没有 ArkUI。
// 一旦 import 链里有任何在模块级解引用 UI 符号的东西（比如 util/materialTuning
// 里的 BlurStyle.*），扩展进程自己就会在加载时崩掉——而官方写明"
// FaultLogExtensionAbility 自身崩溃时，不会再次被系统服务拉起"，那就等于这条
// 救命通道彻底断了。所以这里只依赖 CoreFileKit / NetworkKit / ApiCredentials
// （后者只依赖同目录的 credCodec，没有别的）。
//
// **只留不含用户内容的字段。** 崩溃事件里还有两样东西刻意不碰：
//   hilog —— 崩溃前最多 1000 行本应用的流水日志。我们的日志里有 [StoreDiag]
//            这类消息 id，整段留下来就是把聊天痕迹落盘。
//   external_log —— 故障日志全文，同样含 HiLog 段。
// 留下的是时间、版本、崩溃类型、前后台、进程存活时长、异常名/信息/堆栈。堆栈
// 是我们自己的代码路径，不含用户数据，而它恰恰是唯一真正有用的部分。

import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { crashReportBase, crashReportToken } from '../tdkit/ApiCredentials';
import { logE } from '../util/log';

// 留几条。崩溃是低频事件，留太多只是占地方；留太少又会被一次连环崩溃冲掉。
const MAX_RECORDS: number = 10;
// 堆栈截断长度。够定位到我们自己的帧，又不至于把整个 so 的地址表存下来。
const MAX_STACK_CHARS: number = 4000;
const FILE_NAME: string = 'crash-records.json';
// 两个观察者的名字必须不同，见文件头。扩展进程里用的是 DELAYED 这个名字。
export const NORMAL_WATCHER: string = 'petrelgramCrashWatcher';
export const DELAYED_WATCHER: string = 'petrelgramCrashWatcherDelayed';
const UPLOAD_TIMEOUT_MS: number = 8000;

// 用户关掉上报时留下的标记文件。
//
// 不读 AppSettings：那会把 ArkUI 的依赖拖进扩展进程（见文件头）。也不读
// AppStorage：扩展进程里它是空的。主进程在设置变化时写/删这个文件，扩展进程
// 只要 accessSync 一下就知道用户的选择，零额外依赖。
const OPT_OUT_FILE: string = 'crash-upload-off';

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
  // 已经成功上报过。主进程和扩展进程都可能拿到同一条事件（官方点名的
  // "系统事件重复上报"），靠这个避免重复发。
  uploaded: boolean;
}

let recordsPath: string = '';
let baseDir: string = '';

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
    logE(`crashReport.readAll failed: ${e}`);
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
    logE(`crashReport.writeAll failed: ${e}`);
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
    stack: stack.length > MAX_STACK_CHARS ? stack.substring(0, MAX_STACK_CHARS) : stack,
    uploaded: false
  };
}

export function crashUploadConfigured(): boolean {
  return crashReportBase !== '' && crashReportToken !== '';
}

// 主进程在设置开关变化时调用。
export function setCrashUploadOptOut(optOut: boolean): void {
  if (baseDir === '') {
    return;
  }
  const marker: string = `${baseDir}/${OPT_OUT_FILE}`;
  try {
    if (optOut) {
      const file = fs.openSync(marker, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.closeSync(file);
    } else if (fs.accessSync(marker)) {
      fs.unlinkSync(marker);
    }
  } catch (e) {
    logE(`crashRecordStore.setCrashUploadOptOut failed: ${e}`);
  }
}

function uploadEnabled(): boolean {
  if (!crashUploadConfigured() || baseDir === '') {
    return false;
  }
  try {
    return !fs.accessSync(`${baseDir}/${OPT_OUT_FILE}`);
  } catch (e) {
    return true;
  }
}

// 发一条。成功（2xx）才算数，失败就留着下次再发。
function upload(record: CrashRecord): Promise<boolean> {
  const request = http.createHttp();
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${crashReportToken}`
    } as Record<string, string>,
    extraData: JSON.stringify(record),
    connectTimeout: UPLOAD_TIMEOUT_MS,
    readTimeout: UPLOAD_TIMEOUT_MS
  };
  return request.request(`${crashReportBase}/crash`, options)
    .then((res: http.HttpResponse): boolean => {
      request.destroy();
      return res.responseCode >= 200 && res.responseCode < 300;
    }).catch((e: Error): boolean => {
      request.destroy();
      logE(`crashReport.upload failed: ${e.message}`);
      return false;
    });
}

// 把还没发出去的都发一遍。扩展进程只有 10s，所以逐条串行、发一条存一条——
// 中途被切断时已发出去的不会重发，没发的下次接着来。
export async function flushCrashUploads(): Promise<void> {
  if (!uploadEnabled()) {
    return;
  }
  const records: CrashRecord[] = readAll();
  for (let i = 0; i < records.length; i++) {
    if (records[i].uploaded) {
      continue;
    }
    const ok: boolean = await upload(records[i]);
    if (!ok) {
      return;
    }
    records[i].uploaded = true;
    writeAll(records);
  }
}

// 收到事件：先落盘，再尝试上报。落盘在前——网络失败时记录仍在，下次启动补发。
export function ingestCrashParams(paramsList: Array<Record<string, Object>>): void {
  const next: CrashRecord[] = readAll();
  let added: number = 0;
  for (const params of paramsList) {
    const record = recordOf(params);
    // 主进程和扩展进程可能拿到同一条（官方点名的"系统事件重复上报"），
    // 按时间戳 + 异常信息去重。
    const dup: boolean = next.some((r: CrashRecord): boolean =>
      r.time === record.time && r.exceptionMessage === record.exceptionMessage);
    if (!dup) {
      next.push(record);
      added += 1;
    }
  }
  if (added === 0) {
    return;
  }
  next.sort((a: CrashRecord, b: CrashRecord): number => b.time - a.time);
  writeAll(next.slice(0, MAX_RECORDS));
  flushCrashUploads();
}

export function initCrashStore(filesDir: string): void {
  baseDir = filesDir;
  recordsPath = `${filesDir}/${FILE_NAME}`;
}

export function crashRecords(): CrashRecord[] {
  return readAll();
}

export function clearCrashRecords(): void {
  writeAll([]);
}
