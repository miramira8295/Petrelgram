// 发送前的沙箱暂存：**去重放在目录上，文件名保持原样**（纯判据，有单测）。
//
// 【为什么会有这个文件】用户 2026-09-16 报：「发出去的文件为啥都带有
// send-1231231231」。
//
// 发送前必须把选中的 URI 复制进沙箱（TDLib 读不了分享给我们的临时授权 URI），
// 复制时又要防「一次选九张、同一毫秒」撞名，于是旧做法把去重信息塞进**文件名**：
// `send_<毫秒>_<序号>_<原名>`。而 TDLib 发文件时 `document.file_name` 取的正是
// **本地文件的 basename**——同一条事实也支撑着 util/livePhoto 的 PGLIVE_ 约定
// （接收侧靠 file_name 把实况认回来）。所以那个前缀原样发到了对方手里。
//
// 现在改成 `<cacheDir>/send/<毫秒>_<序号>/<原名>`：basename 一字不改，收件人看到的
// 就是用户自己那份文件的名字；唯一性由目录保证。
//
// 【这个文件为什么不 import fs】本模块被单测直接引用，而 @kit.CoreFileKit 不该
// 进宿主测试包。真正动磁盘的两件事（建目录、清过期）在 util/sendStagingFs，
// 只有 AttachActions / ShareInbox 引它。

export const SEND_STAGING_DIR: string = 'send';
export const SHARE_STAGING_DIR: string = 'share';

// 暂存目录的保留时长。
//
// 【下界由上传决定，不能按分钟算】TDLib 是直接从这个路径上传的；发送失败后消息
// 还挂在列表里，用户重试走的仍是同一个路径。删早了＝重试必失败。
export const STAGING_TTL_MS: number = 24 * 60 * 60 * 1000;

export function stagingDirName(nowMs: number, seq: number): string {
  return `${nowMs}_${seq}`;
}

export function stagedFilePath(
  cacheDir: string, kind: string, nowMs: number, seq: number, fileName: string
): string {
  return `${cacheDir}/${kind}/${stagingDirName(nowMs, seq)}/${fileName}`;
}

// 建不出目录时的退路（见 sendStagingFs.ensureStagingDir）：回到旧的扁平命名。
// 名字难看，但一定发得出去——发不出去比名字难看严重得多。
export function flatStagedPath(
  cacheDir: string, kind: string, nowMs: number, seq: number, fileName: string
): string {
  return `${cacheDir}/${kind}_${nowMs}_${seq}_${fileName}`;
}

// 从目录名里读回时间戳。**不是我们写出来的名字一律返回 -1**：cacheDir 是公共
// 地界，清理只能动自己的东西。
export function stagingStampOf(name: string): number {
  const underscore: number = name.indexOf('_');
  if (underscore <= 0 || underscore === name.length - 1) {
    return -1;
  }
  const head: string = name.substring(0, underscore);
  for (let i = 0; i < head.length; i++) {
    const c: string = head.charAt(i);
    if (c < '0' || c > '9') {
      return -1;
    }
  }
  const stamp: number = Number.parseInt(head, 10);
  return Number.isFinite(stamp) ? stamp : -1;
}

// 该删哪几个暂存目录。认不出名字的、以及还没到期的，都不动。
export function expiredStagingDirs(
  names: string[], nowMs: number, ttlMs: number
): string[] {
  const out: string[] = [];
  for (const name of names) {
    const stamp: number = stagingStampOf(name);
    if (stamp < 0) {
      continue;
    }
    if (nowMs - stamp > ttlMs) {
      out.push(name);
    }
  }
  return out;
}
