// 选好但还没发出去的媒体。
//
// 以前选完图直接就 sendMedia 了，想配文字只能事后「编辑说明」。改成先暂存在
// 输入框上方，用户打完字再一起发。
//
// 这一份状态**不进 composerMode**。那个状态机管的是"输入框此刻在做什么"——
// 普通/回复/编辑，三者互斥。而"附了几张图"和"在回复某条"是可以同时成立的：
// 回复某条 + 附图 + 配文本来就是一次完整操作。混进去会把互斥关系搞错。
//
// 只管集合运算，不碰文件系统、不碰 TDLib——那些只有页面和 store 做得了。

export interface PendingMediaItem {
  // 已经拷进应用缓存的本地路径（copyUriToCache 的产物）。
  path: string;
  isVideo: boolean;
  // ── 视频的附加信息。**只有实况照片那条路会填**（见 ChatPage.collectPickedMedia）。
  //
  // 为什么暂存项必须带着它们：选完图到点发送之间隔着用户打字，这段时间里
  // 唯一活着的就是这个数组。以前它只有 path/isVideo，于是导出实况时算好的
  // 封面与旋转后宽高在 sendPendingMedia 那一步被原地丢掉——接收端没有预览图、
  // 竖拍视频还横过来（用户实测「依然不展示」）。字段在这里，就一路活到发送。
  thumbPath?: string;
  thumbWidth?: number;
  thumbHeight?: number;
  width?: number;
  height?: number;
  durationSec?: number;
}

// Telegram 一个相册最多九个成员，选择器那侧也是这个上限。
export const PENDING_MEDIA_MAX: number = 9;

// 追加的结果。dropped 不是可有可无的：截断必须能被调用方看见并告诉用户，
// 悄悄少发几张比报错更难查。
export interface PendingMediaAppend {
  items: PendingMediaItem[];
  dropped: number;
}

export function appendPendingMedia(
  current: PendingMediaItem[], incoming: PendingMediaItem[]
): PendingMediaAppend {
  const room: number = Math.max(0, PENDING_MEDIA_MAX - current.length);
  const taken: PendingMediaItem[] = incoming.slice(0, room);
  return {
    items: [...current, ...taken],
    dropped: incoming.length - taken.length
  };
}

// 移除某一张。下标越界原样返回——调用方是 UI 事件，不该为越界准备分支。
export function removePendingMedia(
  current: PendingMediaItem[], index: number
): PendingMediaItem[] {
  if (index < 0 || index >= current.length) {
    return current;
  }
  return current.filter((_item: PendingMediaItem, i: number): boolean => i !== index);
}

// 拖拽换序：把 from 位置那一张挪到 to。发送顺序就是相册里的排列顺序，所以
// 这不是装饰性的——用户拖完看到的顺序必须就是对方收到的顺序。
//
// 先摘再插，而不是两两交换：交换会让中间那些张跟着乱跳，与手指下的视觉不符。
// 任一下标越界就原样返回——拖拽回调给的下标不保证有效（松手在列表外）。
export function movePendingMedia(
  current: PendingMediaItem[], from: number, to: number
): PendingMediaItem[] {
  const last: number = current.length - 1;
  if (from < 0 || from > last || to < 0 || to > last || from === to) {
    return current;
  }
  const rest: PendingMediaItem[] =
    current.filter((_item: PendingMediaItem, i: number): boolean => i !== from);
  return [...rest.slice(0, to), current[from], ...rest.slice(to)];
}

export function clearPendingMedia(): PendingMediaItem[] {
  return [];
}

export function hasPendingMedia(current: PendingMediaItem[]): boolean {
  return current.length > 0;
}

// 副标题要显示的两个数。图片和视频分开数，是因为"3 张图片"和"3 个视频"在
// 中文里量词不同，合成一句"3 个文件"会比不说还糟。
export interface PendingMediaCounts {
  photos: number;
  videos: number;
}

export function pendingMediaCounts(current: PendingMediaItem[]): PendingMediaCounts {
  let videos: number = 0;
  for (const item of current) {
    if (item.isVideo) {
      videos += 1;
    }
  }
  return { photos: current.length - videos, videos };
}

// 发送键此刻该不该是"发送"而不是"录音"。有暂存媒体时，正文为空也能发——
// 媒体本身就是内容，说明是可选的。
export function pendingMediaCanSend(
  current: PendingMediaItem[], draft: string
): boolean {
  return hasPendingMedia(current) || draft.trim() !== '';
}

// 暂存项 → 可发送项。
//
// 一比一的字段搬运，看着像废话，但它是**唯一**能保证"选择时算出来的视频元信息
// 不在发送前掉队"的地方：曾经这一步写成 `{ path, isVideo }` 字面量，多出来的
// 封面/宽高就那么无声消失了。放在这里是为了能被单测钉住。
export function toMediaSendItems(current: PendingMediaItem[]): PendingMediaItem[] {
  return current.map((item: PendingMediaItem): PendingMediaItem => ({
    path: item.path,
    isVideo: item.isVideo,
    thumbPath: item.thumbPath,
    thumbWidth: item.thumbWidth,
    thumbHeight: item.thumbHeight,
    width: item.width,
    height: item.height,
    durationSec: item.durationSec
  }));
}

// 暂存条上这一格该拿哪张图去渲染。
//
// **视频不能直接喂给 Image。** MediaStrip 原来一律 `Image(file://item.path)`，
// 旁边那个播放角标的注释还写着「缩略图是首帧」——这个假设不成立：ArkUI 的
// Image 解不了 mp4，那一格从来就是空白的。实况照片把这件事暴露了出来
// （用户实测：「我在文件发送的暂存区，也没有预览」）。
//
// 有封面就用封面（实况导出时顺手生成的 240x320 那张，见 util/sendThumb）；
// 没有就返回空串，由调用方画占位而不是喂一个渲染不出来的路径。
export function pendingThumbSource(item: PendingMediaItem): string {
  const thumb: string = item.thumbPath ?? '';
  if (thumb !== '') {
    return thumb;
  }
  // 图片本身就是自己的预览；视频没有封面时给不出图。
  return item.isVideo ? '' : item.path;
}
