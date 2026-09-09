import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ShareHandoff, parseHandoff, serializeHandoff } from '../util/sharedContent';
import { logE } from '../util/log';

// 分享面板里选中的目标 + 内容，从扩展进程交回主进程。
//
// 走文件而不是 want 参数：want 的参数总量有 IPC 大小限制（systemShare 自己的
// 文档也点名 200KB），而这里要带一串路径和可能很长的说明文字。文件在同一个
// 应用沙箱里，两个进程都能读写。
//
// 编解码在 util/sharedContent（纯函数，有单测），这里只管读写。

const FILE_NAME: string = 'share-handoff.json';

let handoffPath: string = '';

export function initShareHandoff(filesDir: string): void {
  if (filesDir === '') {
    return;
  }
  handoffPath = `${filesDir}/${FILE_NAME}`;
}

export function writeShareHandoff(handoff: ShareHandoff): boolean {
  if (handoffPath === '') {
    return false;
  }
  let file: fs.File | null = null;
  try {
    file = fs.openSync(handoffPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, serializeHandoff(handoff));
    return true;
  } catch (e) {
    logE(`writeShareHandoff failed: ${e}`);
    return false;
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}

// 读并**立刻删除**：交接是一次性的，留在盘上会在下次冷启动时被重放一遍
// （用户会看到自己昨天分享过的东西又冒出来）。
export function takeShareHandoff(): ShareHandoff | null {
  if (handoffPath === '') {
    return null;
  }
  let file: fs.File | null = null;
  try {
    if (!fs.accessSync(handoffPath)) {
      return null;
    }
    const stat: fs.Stat = fs.statSync(handoffPath);
    if (stat.size <= 0) {
      fs.unlinkSync(handoffPath);
      return null;
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    file = fs.openSync(handoffPath, fs.OpenMode.READ_ONLY);
    fs.readSync(file.fd, buffer);
    fs.closeSync(file);
    file = null;
    fs.unlinkSync(handoffPath);
    // 说明文字里有中文，必须按 UTF-8 解码。
    const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
    return parseHandoff(text);
  } catch (e) {
    logE(`takeShareHandoff failed: ${e}`);
    return null;
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}
