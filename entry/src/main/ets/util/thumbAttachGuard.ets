import { logW } from './log';

// 常驻不变量：**画在屏幕上的缩略图必须属于当前这一行的文件**。
//
// 不是探针，别删。理由是这个 bug 的形状：2026-09-03 把 6 个 @Param 合并成一个
// 对象时，两个 @Monitor 的名字被落下了，而 ArkUI 对解析不了的监听路径**既不报
// 编译错、也不打运行时告警**——编译过、单测全绿、界面看着正常，只有滚动到某个
// 时机才露出"图配错文"。这一类错只有不变量兜得住。
//
// 判据放在 build() 的分支条件上：build 一定是拿当前 @Param 求值的，所以那里是
// 唯一不受"参数什么时候落地"影响的观测点。
//
// 正常情况下这里一行都不该出现。真出现了就是自愈又断了，按行里的两个 fileId
// 直接能看出它挂到哪一行去了。

const seen: Set<string> = new Set<string>();
const MAX_KEYS: number = 200;

export function warnStaleThumbAttach(
  attachedFileId: number, specFileId: number, drawing: string
): void {
  if (attachedFileId === specFileId) {
    return;
  }
  // 回收之后、重挂之前允许有一帧对不上（path 故意不清，见 aboutToRecycle），
  // 那一帧不算破坏不变量。
  if (attachedFileId === -1 && drawing === '') {
    return;
  }
  const key: string = `${attachedFileId}:${specFileId}`;
  if (seen.has(key)) {
    return;
  }
  if (seen.size >= MAX_KEYS) {
    seen.clear();
  }
  seen.add(key);
  logW(`[ThumbGuard] stale attach: drawing file=${attachedFileId} but row wants` +
    ` file=${specFileId} (path=${drawing})`);
}
