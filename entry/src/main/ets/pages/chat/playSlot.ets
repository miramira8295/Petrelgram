// 播放位竞选。
//
// 聊天流是异构变高列表（图片/视频/文字混排，相册九宫格里还能图视频混装，
// LazyForEach 还会回收组件），官方短视频列表那套「按 offset / itemHeight 反推
// 索引」不成立 —— 播放位只能选，不能算。
//
// 判定何时发生由调用方决定（见 PlaySlotRegistry：滚动停下后才跑）。这里只
// 负责：给定一组候选与现任，选出唯一的播放位。

// 入选线：新任必须可见到这个比例才有资格上位。
export const PLAY_SLOT_ENTER_RATIO: number = 0.6;
// 保持线：现任只要还在这条线上就不换届。两条线拉开差距形成迟滞 —— 同屏两个
// 视频时，没有迟滞就会因为几像素的滚动来回夺位，这是最伤体验的抖动。
export const PLAY_SLOT_KEEP_RATIO: number = 0.4;

export interface PlaySlotCandidate {
  key: string;
  messageId: number;
  albumIndex: number; // -1 表示整条消息（非相册）
  ratio: number;      // 可见面积 / 自身面积，[0,1]
  centerY: number;    // 自身中心在窗口坐标系的 y（vp）
}

export function slotKey(messageId: number, albumIndex: number): string {
  return `${messageId}:${albumIndex}`;
}

// slotKey 的逆运算：只取消息 id 那一段（相册下标对进度交接没有意义，气泡
// 进度表 bubblePositionMs 是按 messageId 记的）。解析失败返回 0。
export function slotKeyMessageId(key: string): number {
  const at = key.indexOf(':');
  if (at <= 0) {
    return 0;
  }
  const id = Number.parseInt(key.substring(0, at), 10);
  return Number.isNaN(id) ? 0 : id;
}

// 一条媒体是否有资格参加播放位竞选。纯函数，方便把「自动播放视频 / 省电模式 /
// 减少动效」这三个开关的组合完整单测。
//
// 语义等价于 powerFeatureEnabled(KEY_POWER_AUTOPLAY_VIDEO) && !reduceAnimations()
// （powerFeatureEnabled 内部已经与上 !powerSavingActive()，这里把省电模式显式
// 拆成一个入参，让判定本身不依赖 AppStorage）。
//
// 动图（GIF/动画）永远不参加竞选：它们走整文件下载 + SmartLoopVideo 循环播放，
// 与流式播放位是两条互斥的链路（见 spec §3.3）。
export function shouldCompete(autoplayVideoEnabled: boolean, powerSaving: boolean,
  reduceAnimations: boolean, isAnimation: boolean): boolean {
  if (isAnimation) {
    return false;
  }
  return autoplayVideoEnabled && !powerSaving && !reduceAnimations;
}

// 「自动播放大小上限」（#226：只想自动播放小于多少 MB 的视频）。
// maxMb = 0 表示不限；fileSize = 0 是大小未知，放行——维持加这个设置之前的行为。
// 自动播放是边下边播，大视频自动播起来主要是在烧流量，这就是这道闸的用处。
export function autoplaySizeAllowed(fileSize: number, maxMb: number): boolean {
  if (maxMb <= 0 || fileSize <= 0) {
    return true;
  }
  return fileSize <= maxMb * 1024 * 1024;
}

function find(candidates: PlaySlotCandidate[], key: string): PlaySlotCandidate | null {
  if (key === '') {
    return null;
  }
  for (const c of candidates) {
    if (c.key === key) {
      return c;
    }
  }
  return null;
}

// 比例高者胜；持平时取离视口中心更近的。
function better(a: PlaySlotCandidate, b: PlaySlotCandidate, viewportCenterY: number): boolean {
  if (a.ratio !== b.ratio) {
    return a.ratio > b.ratio;
  }
  return Math.abs(a.centerY - viewportCenterY) < Math.abs(b.centerY - viewportCenterY);
}

export function pickPlaySlot(candidates: PlaySlotCandidate[], viewportCenterY: number,
  current: string, pinned: string): string {
  // 用户手动点播的最优先，直到它自己跌破保持线。
  const locked = find(candidates, pinned);
  if (locked !== null && locked.ratio >= PLAY_SLOT_KEEP_RATIO) {
    return locked.key;
  }
  // 迟滞：现任还在保持线上就连任，哪怕别人可见比例更高。
  const incumbent = find(candidates, current);
  if (incumbent !== null && incumbent.ratio >= PLAY_SLOT_KEEP_RATIO) {
    return incumbent.key;
  }
  let winner: PlaySlotCandidate | null = null;
  for (const c of candidates) {
    if (c.ratio < PLAY_SLOT_ENTER_RATIO) {
      continue;
    }
    if (winner === null || better(c, winner, viewportCenterY)) {
      winner = c;
    }
  }
  return winner === null ? '' : winner.key;
}
