// 分享目标名单的落盘层。**这个模块的 import 是刻意压到最少的**——
// 分享面板里那份界面跑在 ShareExtensionAbility 里，那是独立进程，AppStorage
// 是空的、TDLib 没有登录态、拿不到 ChatStore。它能看见主应用状态的唯一途径
// 就是主应用预先写下的这份快照文件（与 services/crashRecordStore 的
// "标记文件"同一思路，文件头有更长的说明）。
//
// 所以这里只依赖 CoreFileKit / ArkTS，不碰 ArkUI、不碰 store。

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ShareTarget, parseShareTargets, serializeShareTargets } from '../util/shareTargets';
import { logE } from '../util/log';

const FILE_NAME: string = 'share-targets.json';

// 主进程与扩展进程各自设一次。用应用级 filesDir（两边解析到同一个沙箱目录）。
let snapshotPath: string = '';

export function initShareSnapshot(filesDir: string): void {
  if (filesDir === '') {
    return;
  }
  snapshotPath = `${filesDir}/${FILE_NAME}`;
}

// 读快照。任何异常都当成"没有快照"——分享面板宁可少一行推荐也不能起不来。
export function readShareTargetSnapshot(): ShareTarget[] {
  if (snapshotPath === '') {
    return [];
  }
  let file: fs.File | null = null;
  try {
    if (!fs.accessSync(snapshotPath)) {
      return [];
    }
    const stat: fs.Stat = fs.statSync(snapshotPath);
    if (stat.size <= 0) {
      return [];
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    file = fs.openSync(snapshotPath, fs.OpenMode.READ_ONLY);
    fs.readSync(file.fd, buffer);
    // 会话标题里有中文，必须按 UTF-8 解码。逐字节拼 String.fromCharCode
    // 会把中文拆成乱码（crashRecordStore 那份只存 ASCII 才用得了那种写法）。
    const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
    return withLiveAvatars(parseShareTargets(text));
  } catch (e) {
    logE(`readShareTargetSnapshot failed: ${e}`);
    return [];
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}

// 快照里的头像路径是**写快照那一刻**的。之后 TDLib 完全可能在缓存清理时把
// 那张图删掉，界面拿着死路径就画出一个空圈。读的时候顺手核一遍，不存在的
// 就清空——界面看到空串会退回首字母，那是对的显示。
// 12 个文件的 accessSync，成本可以忽略。
function withLiveAvatars(targets: ShareTarget[]): ShareTarget[] {
  return targets.map((target: ShareTarget): ShareTarget => {
    if (target.avatarPath === '') {
      return target;
    }
    let alive: boolean = false;
    try {
      alive = fs.accessSync(target.avatarPath);
    } catch (e) {
      alive = false;
    }
    if (alive) {
      return target;
    }
    return {
      chatId: target.chatId, title: target.title, avatarPath: '',
      initials: target.initials, isSavedMessages: target.isSavedMessages
    };
  });
}

// 写快照。失败只记日志——这是锦上添花的能力，绝不能影响主流程。
//
// ⚠️ **必须异步。** 这个函数由 ChatStore 的订阅触发（见 ShareTargetService），
// 也就是**滑动会话列表时**会走到；原来用 openSync/writeSync，2026-09-09 的
// Frame 录制量到单次 **6.78ms 同步文件 IO 落在 UI 线程上**，而一帧的预算才
// 8.31ms。序列化本身是纯内存的，先算好再交给异步 IO。
export function writeShareTargetSnapshot(targets: ShareTarget[]): void {
  if (snapshotPath === '') {
    return;
  }
  const payload: string = serializeShareTargets(targets);
  fs.open(snapshotPath,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    .then((file: fs.File): Promise<void> =>
      fs.write(file.fd, payload).then((): void => { fs.closeSync(file); }))
    .catch((e: Object): void => {
      logE(`writeShareTargetSnapshot failed: ${e}`);
    });
}

// 退出登录/切换账号时把名单抹掉：快照里有会话标题，属于用户内容。
export function clearShareTargetSnapshot(): void {
  if (snapshotPath === '') {
    return;
  }
  try {
    if (fs.accessSync(snapshotPath)) {
      fs.unlinkSync(snapshotPath);
    }
  } catch (e) {
    logE(`clearShareTargetSnapshot failed: ${e}`);
  }
}
