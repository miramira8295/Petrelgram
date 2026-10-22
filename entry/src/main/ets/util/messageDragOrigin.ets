const ORIGIN_PREFIX: string = 'petrelgram-message-drag-v1:';
interface MessageDragOrigin { account: string; chatId: number; }
interface DragExtra { extraInfo?: string; }

export function messageDragOriginTag(account: string, chatId: number): string {
  if (account === '' || !Number.isFinite(chatId) || chatId === 0) { return ''; }
  const origin: MessageDragOrigin = { account, chatId };
  return ORIGIN_PREFIX + JSON.stringify(origin);
}

export function isSameChatMessageDrag(tag: string, account: string, chatId: number): boolean {
  if (account === '' || chatId === 0 || tag.length > 4096 || !tag.startsWith(ORIGIN_PREFIX)) { return false; }
  try {
    const origin = JSON.parse(tag.substring(ORIGIN_PREFIX.length)) as MessageDragOrigin | null;
    return origin !== null && origin.account === account && origin.chatId === chatId;
  } catch (_) { return false; }
}

// ArkUI wraps DragItemInfo.extraInfo in the drop callback's JSON extraParams.
export function isSameChatMessageDragExtra(extra: string | undefined, account: string, chatId: number): boolean {
  if (!extra || extra.length > 8192) { return false; }
  try {
    const parsed = JSON.parse(extra) as DragExtra | null;
    return parsed !== null && typeof parsed.extraInfo === 'string' &&
      isSameChatMessageDrag(parsed.extraInfo, account, chatId);
  } catch (_) { return false; }
}
