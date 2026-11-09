// util/sendStaging 的磁盘那一半：建这一批的暂存目录、清过期的暂存目录。
//
// 判据全在 util/sendStaging（纯函数、有单测）；这里只做 fs 调用，所以本文件不
// 被单测引用——宿主测试包里不该出现 @kit.CoreFileKit。

import { fileIo as fs } from '@kit.CoreFileKit';
import { STAGING_TTL_MS, expiredStagingDirs, stagingDirName } from './sendStaging';
import { logE } from './log';

// 建好这一批的暂存目录并返回它；失败返回 ''，调用方退回扁平命名。
//
// recursion=true 一次把 `<cacheDir>/<kind>` 和它下面这一批的目录都建出来
// （mkdirSync 的两参重载，API 11 起）。
export function ensureStagingDir(
  cacheDir: string, kind: string, nowMs: number, seq: number
): string {
  const dir: string = `${cacheDir}/${kind}/${stagingDirName(nowMs, seq)}`;
  try {
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    return dir;
  } catch (e) {
    logE(`sendStaging.ensureStagingDir ${dir} failed: ${e}`);
    return '';
  }
}

// 一个进程只扫一次：要 listFile，没必要每发一个文件都来一遍。
const swept: Set<string> = new Set<string>();

// 清掉过期的暂存目录。
//
// 【为什么现在才有清理】旧的扁平暂存文件全仓没有任何地方扫过，只增不删。目录化
// 之后顺手补上：目录名自带时间戳，过期判定不用 stat。
//
// 删不掉只是留一坨占空间的文件，绝不能让它影响这次发送——所以整段包在 try 里，
// 且每个目录各自 try。
export function sweepStaging(cacheDir: string, kind: string, nowMs: number): void {
  if (swept.has(kind)) {
    return;
  }
  swept.add(kind);
  const root: string = `${cacheDir}/${kind}`;
  try {
    if (!fs.accessSync(root)) {
      return;
    }
    const expired: string[] = expiredStagingDirs(
      fs.listFileSync(root), nowMs, STAGING_TTL_MS);
    for (const name of expired) {
      const dir: string = `${root}/${name}`;
      try {
        // rmdirSync 是递归删（同 tdkit/AccountRegistry.removeAccountAndData）。
        fs.rmdirSync(dir);
      } catch (e) {
        logE(`sendStaging.sweep rmdir ${dir} failed: ${e}`);
      }
    }
  } catch (e) {
    logE(`sendStaging.sweep ${root} failed: ${e}`);
  }
}
