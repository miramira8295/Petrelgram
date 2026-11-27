import { TdObject } from '../tdkit/TdTypes';

// 本地草稿缓存（用户报：输入一堆文字后返回再进来被清空）。
//
// 【为什么服务端那条不够】保存走 setChatDraftMessage、恢复走 getChat().draft_message，
// 而保存是 fire-and-forget（不等结果）。真机日志 1.4.7.2 抓到过：
//   [Draft] save    chat=-1004320533021 len=3
//   [Draft] restore chat=-1004320533021 serverLen=0 localLen=0
// 同一个会话、中间没有任何 saveDraft failed——新页面的 getChat 抢在草稿落地之前
// 拿到了 chat 对象。往返越快越容易撞上，正好对应"返回再进来"这个操作。
//
// 【做法】离开时同步写本地，进来先读本地；setChatDraftMessage 照发（跨端同步要它），
// 服务端回来的草稿只在本地没有时才采用。顺带给会话列表提供「草稿:」预览。
export class DraftCache {
  private drafts: Map<number, string> = new Map<number, string>();

  get(chatId: number): string {
    return this.drafts.get(chatId) ?? '';
  }

  put(chatId: number, text: string): void {
    if (text === '') {
      this.drafts.delete(chatId);
      return;
    }
    this.drafts.set(chatId, text);
  }

  chatIds(): number[] {
    return Array.from(this.drafts.keys());
  }

  serialize(): string {
    const out: Record<string, string> = {};
    this.drafts.forEach((text: string, chatId: number): void => {
      out[`${chatId}`] = text;
    });
    return JSON.stringify(out);
  }

  // 坏数据一律当空缓存：草稿丢了只是回到改动前的行为，绝不能让它把启动搞崩。
  load(raw: string): void {
    this.drafts.clear();
    if (raw === '') {
      return;
    }
    try {
      const parsed: object = JSON.parse(raw) as object;
      if (parsed === null || Array.isArray(parsed)) {
        return;
      }
      const map: Record<string, string> = parsed as Record<string, string>;
      for (const key of Object.keys(map)) {
        const id: number = Number.parseInt(key, 10);
        const text: string = map[key];
        if (Number.isFinite(id) && typeof text === 'string' && text !== '') {
          this.drafts.set(id, text);
        }
      }
    } catch (e) {
      // 解析失败就是空缓存。
    }
  }
}

// 会话列表里的草稿预览：折行压成空格、超长截断。
export function draftPreviewOf(text: string, maxChars: number): string {
  const flat: string = text.replace(/\s+/g, ' ').trim();
  if (flat === '') {
    return '';
  }
  return flat.length > maxChars ? `${flat.substring(0, maxChars)}…` : flat;
}

export interface ParsedTdDraft {
  text: string;
  date: number;
  replyToId: number;
}

// 解析 TDLib 1.8.71 的 draftMessage 对象（兼容旧版 input_message_content / input_message_text 字段）。
export function parseTdDraftMessage(draft: TdObject | undefined): ParsedTdDraft {
  if (draft === undefined) {
    return { text: '', date: 0, replyToId: 0 };
  }
  const date: number = (draft['date'] as number | undefined) ?? 0;
  const content = (draft['content'] ?? draft['input_message_content'] ?? draft['input_message_text']) as TdObject | undefined;
  const contentType: string = content !== undefined ? ((content['@type'] as string | undefined) ?? '') : '';
  const ft = (contentType === 'draftMessageContentText' || contentType === 'inputMessageText')
    ? (content?.['text'] as TdObject | undefined) : undefined;
  const text: string = ft !== undefined ? ((ft['text'] as string | undefined) ?? '') : '';
  let replyToId: number = 0;
  const replyTo = draft['reply_to'] as TdObject | undefined;
  if (replyTo !== undefined && (replyTo['@type'] as string | undefined) === 'inputMessageReplyToMessage') {
    replyToId = (replyTo['message_id'] as number | undefined) ?? 0;
  }
  return {
    text,
    date: Number.isFinite(date) && date > 0 ? Math.floor(date) : 0,
    replyToId: Number.isFinite(replyToId) && replyToId > 0 ? replyToId : 0
  };
}

// 决定打开会话时是否用云端草稿覆盖本地草稿：
//   · 云端时间戳严格更新（含其他端清空草稿 date=0 但本地已有旧草稿的情况不盲目清，除非云端明确给新时间戳）；
//   · 或本地为空而云端非空。
export function shouldAdoptServerDraft(
  localText: string, localDate: number, serverText: string, serverDate: number
): boolean {
  if (serverDate > localDate && (serverText !== localText || serverText !== '')) {
    return true;
  }
  if (localText === '' && serverText !== '') {
    return true;
  }
  return false;
}
