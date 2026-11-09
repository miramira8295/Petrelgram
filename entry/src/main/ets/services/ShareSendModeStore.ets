import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  DEFAULT_SEND_MODE, ShareSendMode, parseSendMode, serializeSendMode
} from '../util/shareSendMode';
import { logE } from '../util/log';

// 「点头像之后直接发还是进会话编辑」的记忆。理由与格式见 util/shareSendMode。
// 依赖压到最少：面板那个独立进程也要读写它。

const FILE_NAME: string = 'share-send-mode';

let modePath: string = '';

export function initShareSendMode(filesDir: string): void {
  if (filesDir === '') {
    return;
  }
  modePath = `${filesDir}/${FILE_NAME}`;
}

export function readShareSendMode(): ShareSendMode {
  if (modePath === '') {
    return DEFAULT_SEND_MODE;
  }
  let file: fs.File | null = null;
  try {
    if (!fs.accessSync(modePath)) {
      return DEFAULT_SEND_MODE;
    }
    const stat: fs.Stat = fs.statSync(modePath);
    if (stat.size <= 0 || stat.size > 32) {
      return DEFAULT_SEND_MODE;
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    file = fs.openSync(modePath, fs.OpenMode.READ_ONLY);
    fs.readSync(file.fd, buffer);
    return parseSendMode(
      util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer)));
  } catch (e) {
    logE(`readShareSendMode failed: ${e}`);
    return DEFAULT_SEND_MODE;
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}

export function writeShareSendMode(mode: ShareSendMode): void {
  if (modePath === '') {
    return;
  }
  let file: fs.File | null = null;
  try {
    file = fs.openSync(modePath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, serializeSendMode(mode));
  } catch (e) {
    logE(`writeShareSendMode failed: ${e}`);
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}
