// 「屏幕别熄」的仲裁。**纯记账，不碰系统**——真正调 setWindowKeepScreenOn 的是
// pages/chat/LiveViewerUi，这里只回答"现在到底该不该亮着"。
//
// 【为什么需要仲裁，不能各调各的】setWindowKeepScreenOn 是窗口上的**一个**布尔
// 开关，谁最后调谁说了算。在这之前只有直播在用（观看页 + 悬浮窗，它们本来就
// 共享一个标志）；2026-09-22 视频播放也要按播放状态开关它（用户：「播放视频的
// 时候能不能暂时不熄屏，不播放视频的时候正常熄屏」）。两边各调各的就会互相掐：
// 直播悬浮窗开着、这时暂停一个视频，视频那边一句 false 就把直播的也关了。
//
// 记的是**持有者集合**：有人要就亮着，全放开才熄。集合空/非空的翻转才产生一次
// 系统调用，中间的增减不产生任何调用。
//
// 持有者名字要**按实例**取（见 videoAwakeOwner）：同一时刻可能有两个播放器活着
// （全屏查看器从气泡接管播放的那一瞬间），共用一个名字会让先退场的那个把后
// 接手的那个一起放掉。
const owners: Set<string> = new Set<string>();
// 最后一次真正推给系统的值。只有它和"现在想要的"不一致时才需要再推一次。
let applied: boolean = false;

export const AWAKE_OWNER_LIVE: string = 'live';

let videoOwnerSeq: number = 0;

export function videoAwakeOwner(): string {
  videoOwnerSeq++;
  return `video:${videoOwnerSeq}`;
}

// 登记/注销一个持有者。**返回值是"需要推给系统的新状态"，不需要推时返回 null。**
// 调用方照这个返回值决定要不要碰窗口，别自己判断。
export function requestScreenAwake(owner: string, on: boolean): boolean | null {
  if (owner === '') {
    return null;
  }
  if (on) {
    owners.add(owner);
  } else {
    owners.delete(owner);
  }
  const wanted: boolean = owners.size > 0;
  if (wanted === applied) {
    return null;
  }
  applied = wanted;
  return wanted;
}

// 系统调用失败时回滚记账，否则 applied 会一直声称自己推成功过，
// 下一次同方向的请求被当成"没变化"而永远不再重试。
export function screenAwakeApplyFailed(attempted: boolean): void {
  applied = !attempted;
}

export function screenAwakeOwnerCount(): number {
  return owners.size;
}

export function resetScreenAwakeForTest(): void {
  owners.clear();
  applied = false;
  videoOwnerSeq = 0;
}
