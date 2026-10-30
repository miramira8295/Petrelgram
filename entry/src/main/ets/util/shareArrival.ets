import { directShareSteps } from './directSharePlan';
import { SendProgress } from './sendProgress';
import { SharedItem } from './sharedContent';
import { logE } from './log';
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
  checkPermissions?: (payload: SharedPayload) => Promise<void>;
  // 把图片/视频放进输入框上方的暂存区，返回被截掉的张数。
  appendMedia: (items: MediaSendItem[]) => number;
  // 写草稿（说明文字）。
  setDraft: (text: string) => void;
  // 当前草稿。分享的说明要接在用户已有的草稿后面，不能覆盖。
  draftText: () => string;
  sendDocument: (path: string, caption: string) => Promise<void>;
  sendAudio: (path: string, caption: string) => Promise<void>;
  // 直接发送那一档用：不经过输入框，图片/视频当场发出去。
  sendMedia: (items: MediaSendItem[], caption: string) => Promise<void>;
  sendText: (text: string) => Promise<void>;
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
        thumbPath: geo.thumbPath, posterPath: geo.posterPath,
        thumbWidth: geo.thumbWidth, thumbHeight: geo.thumbHeight,
        width: geo.width, height: geo.height, durationSec: geo.durationSec
      };
    });
    plan.dropped += host.appendMedia(items);
  }

  // 直接发的那些：配文只跟第一条走，否则每个文件底下都挂一遍同样的说明。
  let usedCaption: boolean = false;
  for (let i = 0; i < plan.documents.length; i++) {
    host.sendDocument(plan.documents[i], usedCaption ? '' : caption).catch(reportShareError);
    usedCaption = true;
  }
  for (let i = 0; i < plan.audios.length; i++) {
    host.sendAudio(plan.audios[i], usedCaption ? '' : caption).catch(reportShareError);
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
export async function sendShareDirectly(payload: SharedPayload, host: ShareArrivalHost,
  geometry: Map<string, ShareMediaGeometry> = new Map<string, ShareMediaGeometry>(),
  progress: SendProgress = new SendProgress(),
  active: () => boolean = (): boolean => true
): Promise<void> {
  if (!active()) { throw new Error('share session ended'); }
  await host.checkPermissions?.(payload);
  const steps = directShareSteps(payload);
  for (let i = 0; i < steps.length; i++) {
    if (!active()) { throw new Error('share session ended'); }
    const step = steps[i];
    await progress.run(i, async (): Promise<void> => {
      if (step.kind === 'media') {
        const media: MediaSendItem[] = step.items.map((item: SharedItem): MediaSendItem => {
          const geo: ShareMediaGeometry | undefined = geometry.get(item.uri);
          if (geo === undefined) { return { path: item.uri, isVideo: item.kind === 'video' }; }
          return { path: item.uri, isVideo: item.kind === 'video', thumbPath: geo.thumbPath,
            posterPath: geo.posterPath, thumbWidth: geo.thumbWidth, thumbHeight: geo.thumbHeight,
            width: geo.width, height: geo.height, durationSec: geo.durationSec };
        });
        await host.sendMedia(media, step.caption);
      } else if (step.kind === 'text') {
        await host.sendText(step.caption);
      } else if (step.kind === 'audio') {
        await host.sendAudio(step.items[0].uri, step.caption);
      } else {
        await host.sendDocument(step.items[0].uri, step.caption);
      }
    });
  }
  host.scrollToBottom();
}

function reportShareError(error: Object): void {
  logE(`Share arrival failed: ${error}`);
  promptAction.showToast({ message: $r('app.string.fw_failed'), duration: 2000 });
}

// 已确认成功的步骤不再交给用户重试；说明文字也不能再跟第二批重复发送。
export function remainingDirectShare(payload: SharedPayload, progress: SendProgress): SharedPayload {
  const steps = directShareSteps(payload);
  const media: SharedItem[] = [];
  let caption: string = '';
  for (let i = 0; i < steps.length; i++) {
    if (progress.completedStep(i)) { continue; }
    media.push(...steps[i].items);
    if (steps[i].caption !== '') { caption = steps[i].caption; }
  }
  return { caption, media };
}
