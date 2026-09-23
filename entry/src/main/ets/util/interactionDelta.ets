import { ReactionInfo } from '../store/MessageEntry';

// updateMessageInteractionInfo 到达时，行里**会画出来**的那部分（评论数、评论人、
// 反应）到底变没变。
//
// 频道里这条推送绝大多数只是浏览数 +1。原来不管变没变都 patch：克隆一行、复制
// 消息数组、触发列表 notify，还把已经解析好的自定义表情路径和评论人头像清空再
// 重新拉。现在浏览数走 viewCountChannel，这里判定"没变"就整个跳过 patch。
//
// 自定义表情的本地路径**不参与比较**：推送里它总是 ''（还没解析），行里的已经
// 解析好了，拿它比会让每一次推送都判成"变了"。
export function interactionChanged(
  prevCommentCount: number, prevReplierIds: number[], prevReactions: ReactionInfo[],
  nextCommentCount: number, nextReplierIds: number[], nextReactions: ReactionInfo[]
): boolean {
  if (prevCommentCount !== nextCommentCount) {
    return true;
  }
  if (!sameIds(prevReplierIds, nextReplierIds)) {
    return true;
  }
  if (prevReactions.length !== nextReactions.length) {
    return true;
  }
  for (let i = 0; i < prevReactions.length; i++) {
    const a: ReactionInfo = prevReactions[i];
    const b: ReactionInfo = nextReactions[i];
    if (a.emoji !== b.emoji || a.customEmojiId !== b.customEmojiId ||
      a.count !== b.count || a.isChosen !== b.isChosen) {
      return true;
    }
  }
  return false;
}

function sameIds(a: number[], b: number[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}
