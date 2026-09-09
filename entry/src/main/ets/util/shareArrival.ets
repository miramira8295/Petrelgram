import { promptAction } from '@kit.ArkUI';
import { MediaSendItem } from '../store/MessageStore';
import { SharedPayload } from './sharedContent';
import { ShareMediaGeometry } from './shareLivePhoto';
import { SharePlan, captionForDirectSend, hasDirectSend, planShare } from './shareStaging';

// 分享的内容落到会话页之后的执行侧。
//
// ChatPage 只留一句接线（applyRouteParams 里 `if (route.sharePending)`），
// 决策在 util/shareStaging（纯函数、有单测），落地在这里。这么分是因为
// "该怎么处理"能单测，"往哪个 store 上打"不能。

// ChatPage 提供的落点。只要这几件事，不需要把整个页面传进来。
export interface ShareArrivalHost {
  // 把图片/视频放进输入框上方的暂存区，返回被截掉的张数。
  appendMedia: (items: MediaSendItem[]) => number;
  // 写草稿（说明文字）。
  setDraft: (text: string) => void;
  // 当前草稿。分享的说明要接在用户已有的草稿后面，不能覆盖。
  draftText: () => string;
  sendDocument: (path: string, caption: string) => void;
  sendAudio: (path: string, caption: string) => void;
  // 直接发送那一档用：不经过输入框，图片/视频当场发出去。
  sendMedia: (items: MediaSendItem[], caption: string) => Promise<void>;
  sendText: (text: string) => void;
  // 发完/放好之后滚到底，让用户看见结果。
  scrollToBottom: () => void;
}

// 两段文字接起来。都非空时中间空一行——用户自己打的那半和分享带来的那半
// 本来就是两回事，挤在一行里读不出来。
function joinDraft(existing: string, incoming: string): string {
  if (existing === '') {
    return incoming;
  }
  if (incoming === '') {
    return existing;
  }
  return `${existing}\n${incoming}`;
}

// 执行一次分享落地。返回 true 表示确实处理了内容（调用方据此决定要不要
// 提示用户）。
export function applyShareArrival(payload: SharedPayload, host: ShareArrivalHost,
  alreadyStaged: number,
  geometry: Map<string, ShareMediaGeometry> = new Map<string, ShareMediaGeometry>()): boolean {
  const plan: SharePlan = planShare(payload, alreadyStaged);
  const caption: string = captionForDirectSend(payload, plan);

  if (plan.staged.length > 0) {
    // 实况照片恢复出来的那一条要带上封面和显示宽高——不带的话接收端没有预览图、
    // 竖拍的还会横过来（issue #193 的另一半，见 util/shareLivePhoto）。
    const items: MediaSendItem[] = plan.staged.map((item: StagedLike): MediaSendItem => {
      const geo: ShareMediaGeometry | undefined = geometry.get(item.path);
      if (geo === undefined) {
        return { path: item.path, isVideo: item.isVideo };
      }
      return {
        path: item.path, isVideo: item.isVideo,
        thumbPath: geo.thumbPath, thumbWidth: geo.thumbWidth, thumbHeight: geo.thumbHeight,
        width: geo.width, height: geo.height
      };
    });
    plan.dropped += host.appendMedia(items);
  }

  // 直接发的那些：配文只跟第一条走，否则每个文件底下都挂一遍同样的说明。
  let usedCaption: boolean = false;
  for (let i = 0; i < plan.documents.length; i++) {
    host.sendDocument(plan.documents[i], usedCaption ? '' : caption);
    usedCaption = true;
  }
  for (let i = 0; i < plan.audios.length; i++) {
    host.sendAudio(plan.audios[i], usedCaption ? '' : caption);
    usedCaption = true;
  }

  if (plan.draft !== '') {
    host.setDraft(joinDraft(host.draftText(), plan.draft));
  }
  if (plan.staged.length > 0 || hasDirectSend(plan)) {
    host.scrollToBottom();
  }

  if (plan.dropped > 0) {
    promptAction.showToast({ message: $r('app.string.cp_pending_media_full'), duration: 2000 });
  } else if (plan.staged.length > 0) {
    promptAction.showToast({ message: $r('app.string.share_staged'), duration: 2000 });
  }
  return plan.staged.length > 0 || hasDirectSend(plan) || plan.draft !== '';
}

// planShare 返回的暂存项形状。单独声明一份是为了不让本模块反过来 import
// shareStaging 的内部类型名（它是纯函数模块，接口面越小越好）。
interface StagedLike {
  path: string;
  isVideo: boolean;
}

// 「直接发送」那一档：不落输入框，当场发出去。
//
// 和 applyShareArrival 共用同一份 planShare（决策一致），差别只在图片/视频
// 的去处：这里直接 sendMedia，那里进暂存区。文档/音频两边都是直接发——
// 它们本来就没有暂存位。
//
// 返回的 Promise 在**请求都发出去之后**兑现（不是上传完成）。调用方据此决定
// 何时退回后台：TDLib 收下之后上传会在后台继续，应用有 dataTransfer 长时任务。
export function sendShareDirectly(payload: SharedPayload, host: ShareArrivalHost,
  geometry: Map<string, ShareMediaGeometry> = new Map<string, ShareMediaGeometry>()
): Promise<void> {
  // alreadyStaged 传 0：这一档不碰暂存区，没有名额一说。
  const plan: SharePlan = planShare(payload, 0);
  let usedCaption: boolean = false;

  const media: MediaSendItem[] = plan.staged.map((item: StagedLike): MediaSendItem => {
    const geo: ShareMediaGeometry | undefined = geometry.get(item.path);
    if (geo === undefined) {
      return { path: item.path, isVideo: item.isVideo };
    }
    return {
      path: item.path, isVideo: item.isVideo,
      thumbPath: geo.thumbPath, thumbWidth: geo.thumbWidth, thumbHeight: geo.thumbHeight,
      width: geo.width, height: geo.height
    };
  });

  let chain: Promise<void> = Promise.resolve();
  if (media.length > 0) {
    // 说明文字跟着图片走（和相册那条路一致：配文挂在第一条上）。
    chain = host.sendMedia(media, payload.caption);
    usedCaption = true;
  }
  for (let i = 0; i < plan.documents.length; i++) {
    host.sendDocument(plan.documents[i], usedCaption ? '' : payload.caption);
    usedCaption = true;
  }
  for (let i = 0; i < plan.audios.length; i++) {
    host.sendAudio(plan.audios[i], usedCaption ? '' : payload.caption);
    usedCaption = true;
  }
  // 纯文字：没有媒体时它自己就是一条消息。
  if (!usedCaption && payload.caption !== '') {
    host.sendText(payload.caption);
  }
  host.scrollToBottom();
  return chain;
}
