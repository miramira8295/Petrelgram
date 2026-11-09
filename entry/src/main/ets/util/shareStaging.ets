import { PENDING_MEDIA_MAX } from './pendingMedia';
import { SharedItem, SharedPayload } from './sharedContent';

// 分享的内容落到某个会话之后，"每一样东西该怎么处理"的决策。纯函数。
//
// 【为什么图片和文档不一样】输入框上方的暂存区（util/pendingMedia）只装
// 图片和视频——它是相册那条路的产物，PendingMediaItem 里连文件名都没有。
// 文档和音频没有暂存位可放，只能直接发。所以：
//
//   图片/视频 → 暂存到输入框上方，说明文字进草稿，用户确认后一起发
//   文档/音频 → 直接发出，说明文字作为第一条的配文
//   纯文字/链接 → 进草稿，不发
//
// 这条分界不是随意的：暂存意味着"还能反悔"，而直接发不能。图片是分享里最
// 常见的一类，给它反悔的机会最有价值；文档一次一个、目标明确，用户在选择
// 会话那一步就已经确认过了。

export interface StagedMediaItem {
  path: string;
  isVideo: boolean;
}

export interface SharePlan {
  // 进输入框上方暂存区的图片/视频。
  staged: StagedMediaItem[];
  // 立刻按文档发的路径。
  documents: string[];
  // 立刻按音频发的路径。
  audios: string[];
  // 进草稿的文字。图片被暂存时它是配文；只有文字时它就是全部内容。
  draft: string;
  // 因为超过暂存上限而没能带上的张数。调用方要告诉用户，不能悄悄少发。
  dropped: number;
}

// caption 归属：有图片被暂存时，说明文字进草稿（跟着图片一起发）；
// 没有图片但有文档时，它是文档的配文，不该再留在草稿里重复一遍。
export function planShare(payload: SharedPayload, alreadyStaged: number = 0): SharePlan {
  const staged: StagedMediaItem[] = [];
  const documents: string[] = [];
  const audios: string[] = [];
  let dropped: number = 0;
  const room: number = Math.max(0, PENDING_MEDIA_MAX - alreadyStaged);

  for (let i = 0; i < payload.media.length; i++) {
    const item: SharedItem = payload.media[i];
    if (item.kind === 'image' || item.kind === 'video') {
      if (staged.length < room) {
        staged.push({ path: item.uri, isVideo: item.kind === 'video' });
      } else {
        dropped++;
      }
    } else if (item.kind === 'audio') {
      audios.push(item.uri);
    } else {
      documents.push(item.uri);
    }
  }

  // 说明文字只能出现在一个地方，否则用户会看到它发两遍。
  const keepInDraft: boolean = staged.length > 0 ||
    (documents.length === 0 && audios.length === 0);
  return {
    staged: staged,
    documents: documents,
    audios: audios,
    draft: keepInDraft ? payload.caption : '',
    dropped: dropped
  };
}

// 直接发出去的那些的配文。只有在草稿没留住它的时候才用，避免重复。
export function captionForDirectSend(payload: SharedPayload, plan: SharePlan): string {
  return plan.draft === '' ? payload.caption : '';
}

// 这次分享有没有"立刻就发"的东西。调用方据此决定提示哪一句文案。
export function hasDirectSend(plan: SharePlan): boolean {
  return plan.documents.length > 0 || plan.audios.length > 0;
}
