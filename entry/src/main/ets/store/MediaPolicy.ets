import { MessageEntry } from './MessageEntry';

// 媒体下载的唯一决策点。
//
// 旧模型是「按网络类型的开关矩阵」：3 套 profile × 7 个开关，但全 app 只有
// shouldAutoDownload() 读它，且只作用于 live 到达的消息，翻历史完全不看 ——
// 开关名副其不实，用户看到的是"设置无效 + 下载停不下来"。
//
// 新模型按用户意图分级：看得见 → 缩略图，放大 → 高清，成为播放位 → 开流，
// 明确要 → 整文件。网络类型只影响一处（邻图预取），其余由行为决定。
export type MediaIntent = 'thumb' | 'full' | 'stream' | 'explicit';

// 从 MessageEntry 抽出的最小输入。用「还需要什么」而不是「有什么」表达，
// 已在本地的文件天然产出空意图，调用方不必再判重。
export interface MediaSubject {
  contentType: string;
  isAnimation: boolean;
  needsThumb: boolean;
  needsFull: boolean;
  needsVideo: boolean;
}

export interface MediaContext {
  inWindow: boolean;
  isPlaySlot: boolean;
  viewerOpen: boolean;
  autoplayEnabled: boolean;
  powerSaving: boolean;
  networkMetered: boolean;
  reduceAnimations: boolean;
}

// 体积小、播放即用，进窗口就取：不取的话点开还要等一次往返。语音体积极小
// 且必须秒播，无条件 eager；videoNote（圆形视频）体积不小，改到下方受
// autoAllowed 约束，省电/关自动播放时要能拦住。
const EAGER_TYPES: string[] = ['voice'];

export function decideMedia(subject: MediaSubject, ctx: MediaContext): MediaIntent[] {
  const intents: MediaIntent[] = [];
  if (!ctx.inWindow) {
    return intents; // 窗口外一律不预取
  }
  if (subject.needsThumb) {
    // 'thumb' 仅作语义完整：真正的入队（含去重与限速重试）在
    // MessageStore.requestPhotos() 上半段既有逻辑里完成，store 的分派故意
    // 不消费这里返回的 'thumb'，避免重复下载。
    intents.push('thumb');
  }
  // 高清图（'full'）不再由这里产出：全屏查看器打开只是 store 级状态，若在
  // 这里按 viewerOpen 产出 'full'，store 的全量遍历循环会对窗口内每一张
  // 有 photoFullFileId 的照片都发起原图下载——查看器只看当前这一张，其余
  // 都是浪费。高清下载完全交给 MediaViewerOverlay 自己对当前图与左右邻图
  // 调 requestFullPhoto 驱动。
  if (!subject.needsVideo) {
    return intents;
  }
  const autoAllowed = ctx.autoplayEnabled && !ctx.powerSaving && !ctx.reduceAnimations;
  if (subject.isAnimation) {
    // GIF/动图：体积小且要无限循环，流式反而更差，维持整文件路径；但仍要
    // 服从「减少动效」——不播就不该下整文件。
    if (autoAllowed) {
      intents.push('explicit');
    }
    return intents;
  }
  if (EAGER_TYPES.indexOf(subject.contentType) >= 0) {
    intents.push('explicit');
    return intents;
  }
  if (subject.contentType === 'videoNote') {
    // 仅在自动播放允许时自动下；否则等用户点 onVideoNoteDownload。
    if (autoAllowed) {
      intents.push('explicit');
    }
    return intents;
  }
  if (subject.contentType === 'video' && ctx.isPlaySlot && autoAllowed) {
    intents.push('stream');
  }
  return intents;
}

// 计费网络下不预取查看器的左右邻图 —— 这是网络类型唯一还起作用的地方。
export function shouldPrefetchNeighbour(ctx: MediaContext): boolean {
  return ctx.viewerOpen && !ctx.networkMetered;
}

export function subjectOfEntry(entry: MessageEntry): MediaSubject {
  return {
    contentType: entry.contentType,
    isAnimation: entry.isAnimation,
    needsThumb: entry.photoFileId !== 0 && entry.photoPath === '',
    needsFull: entry.photoFullFileId !== 0 && entry.photoFullPath === '',
    needsVideo: entry.videoFileId !== 0 && entry.videoPath === ''
  };
}
