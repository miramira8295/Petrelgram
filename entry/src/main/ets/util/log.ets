// 运行日志缓冲。**这里是全应用日志的唯一出口**——logI / logW / logE 取代了
// 原来散在 148 个文件里的 700 多处 console.*。
//
// 为什么不直接拦截 console：ArkTS 明确禁止覆写对象方法
// （arkts-no-method-reassignment）和 Function.apply/call
// （arkts-no-func-apply-call），那条路在这门语言里根本不存在。所以只能把调用点
// 换掉，好在是机械替换，编译器全程兜底。
//
// 为什么要自己留一份：hilog 是系统日志，第三方应用**读不回来**。HiAppEvent 的
// 崩溃事件里虽然带 hilog 段，但那只在崩溃时才有，而大多数问题（消息不刷新、
// 滑不动、发送慢）根本不崩。
//
// 这个模块被 148 个文件引用，所以依赖必须极少：只有 CoreFileKit。上报那一半在
// services/diagLog（它才碰 NetworkKit 和端点配置）。
//
// **上报必须由用户主动触发。** 这份缓冲含 [StoreDiag] 的消息 id 这类东西，属于
// 聊天痕迹，和崩溃记录不是一回事。

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 两级：内存里留一小段，攒够就追加到磁盘，磁盘上轮转两份。
//
// 只放内存不行——[StoreDiag] 这类诊断行在滑动时是每帧级别的，几百行几秒就
// 冲干净了，等用户想起来去设置里点上报，出问题那一段早没了。
//
// 全放内存也不行——要留下足够长的一段就得常驻几 MB，而这个应用本来就在跟
// 内存压力较劲（切后台还要 trimPixelCache）。
//
// 所以内存只当写缓冲，攒够 FLUSH_LINES 行就追加到文件；文件超过 MAX_FILE_BYTES
// 就轮转，保留当前 + 上一份，合计约 4MB。磁盘上这点东西可以忽略，换来的是
// 几万行的回溯深度。
const MAX_LINES: number = 600;
const FLUSH_LINES: number = 300;
// 单行上限。一行超长通常是谁把整个 JSON 打出来了，截断即可。
const MAX_LINE_CHARS: number = 500;
// 每份日志文件的上限，保留两份。
const MAX_FILE_BYTES: number = 2 * 1024 * 1024;
// 一次上报最多带多少。超出就只取最新的那一段——出问题前后那几分钟才是有用的，
// 而且请求体太大在弱网下根本传不完。
const MAX_UPLOAD_CHARS: number = 2 * 1024 * 1024;
const UPLOAD_TIMEOUT_MS: number = 15000;

const lines: string[] = [];
let installed: boolean = false;
let logDir: string = '';

function currentPath(): string {
  return `${logDir}/petrelgram-log.txt`;
}

function previousPath(): string {
  return `${logDir}/petrelgram-log.1.txt`;
}

// 把内存里攒的追加到磁盘。轮转发生在追加之后：先写满再换，免得刚轮转完
// 又立刻写一大块进新文件。
function flushToDisk(): void {
  if (logDir === '' || lines.length === 0) {
    return;
  }
  const chunk: string = `${lines.join('\n')}\n`;
  lines.splice(0, lines.length);
  try {
    const file = fs.openSync(currentPath(),
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
    fs.writeSync(file.fd, chunk);
    fs.closeSync(file);
    if (fs.statSync(currentPath()).size >= MAX_FILE_BYTES) {
      if (fs.accessSync(previousPath())) {
        fs.unlinkSync(previousPath());
      }
      fs.renameSync(currentPath(), previousPath());
    }
  } catch (e) {
    // 落盘失败不能反过来把应用拖垮，也不能在这里再 console.error —— 那会
    // 递归回到 push 里。丢掉这一批，继续攒下一批。
  }
}

function push(level: string, text: string): void {
  const trimmed: string = text.length > MAX_LINE_CHARS
    ? `${text.substring(0, MAX_LINE_CHARS)}…` : text;
  lines.push(`${level} ${trimmed}`);
  if (lines.length >= FLUSH_LINES && logDir !== '') {
    flushToDisk();
    return;
  }
  // 还没配好目录（启动最早期）时退化成纯内存环，不至于无限涨。
  if (lines.length > MAX_LINES) {
    lines.shift();
  }
}

// 拿到 filesDir 之后调用，此后才会落盘。
export function initDiagLog(filesDir: string): void {
  logDir = filesDir;
}

// **不要用 String.fromCharCode(...bytes)**。这里原本是那么写的，两个问题：
//
//   1. 展开成实参会爆栈。日志文件轻易到几百 KB，spread 就是几十万个实参，
//      直接抛异常被下面的 catch 吞掉、返回空串——**表现是日志"读出来是空的"**。
//      实测：磁盘上 716 KB 的日志，界面显示 0 KB，上报也就一直在传空内容。
//      用户报的"上传老是失败"很可能根本不是网络问题（issue #89）。
//   2. 按字节码位拼字符串对 UTF-8 是错的，中文会被拆成乱码。
//
// TextDecoder 两个问题一起解决：不受长度限制，且按 UTF-8 正确解码。
function readFile(path: string): string {
  try {
    if (!fs.accessSync(path)) {
      return '';
    }
    const stat = fs.statSync(path);
    if (stat.size <= 0) {
      return '';
    }
    const buffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    // readSync 返回实际读到的字节数——用它而不是 stat.size 去切，文件在读的
    // 过程中被轮转/截断时才不会把尾部的垃圾也解出来。
    const read: number = fs.readSync(file.fd, buffer);
    fs.closeSync(file);
    if (read <= 0) {
      return '';
    }
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buffer, 0, read));
  } catch (e) {
    return '';
  }
}

// 磁盘上的两份 + 内存里还没落盘的，按时间先后拼起来，超长则只留最新的一段。
function collectAll(): string {
  flushToDisk();
  const all: string = `${readFile(previousPath())}${readFile(currentPath())}${lines.join('\n')}`;
  return all.length > MAX_UPLOAD_CHARS
    ? all.substring(all.length - MAX_UPLOAD_CHARS) : all;
}

function joinArgs(args: Object[]): string {
  const parts: string[] = [];
  for (const a of args) {
    parts.push(`${a}`);
  }
  return parts.join(' ');
}

// 三个出口。除了写进缓冲，照旧往系统日志里打一份——hilog 仍然是插着数据线
// 调试时最顺手的东西，这里只是额外留了个副本。
//
// 转发给 console 时先拼成一个字符串，而不是把 rest 参数展开转发：ArkTS 不允许
// 把 rest 参数 spread 给非 rest 形参（A spread argument must either have a
// tuple type or be passed to a rest parameter）。调用点本来也几乎全是单个
// 模板字符串，拼一下没有信息损失。
export function logI(...args: Object[]): void {
  const text: string = joinArgs(args);
  push('I', text);
  console.info(text);
}

export function logW(...args: Object[]): void {
  const text: string = joinArgs(args);
  push('W', text);
  console.warn(text);
}

export function logE(...args: Object[]): void {
  const text: string = joinArgs(args);
  push('E', text);
  console.error(text);
}

// 大致有多少字节可发，给设置页显示"将发送 xx KB"。
export function diagLogSize(): number {
  return collectAll().length;
}

// 供设置页在上报前展示给用户看：发出去的就是这些。
export function diagLogText(): string {
  return collectAll();
}

export function clearDiagLog(): void {
  lines.splice(0, lines.length);
  try {
    if (logDir !== '' && fs.accessSync(currentPath())) {
      fs.unlinkSync(currentPath());
    }
    if (logDir !== '' && fs.accessSync(previousPath())) {
      fs.unlinkSync(previousPath());
    }
  } catch (e) {
    // 删不掉就算了，轮转本身会把它压下去。
  }
}

