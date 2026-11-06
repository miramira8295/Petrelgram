// 会话实体的「镜像」：第二层 B4b-3 的数据结构。
//
// 目标态是 worker 持有唯一真身、UI 只持这一份镜像（同步读照旧命中它）。这一批
// 先把镜像本身做出来并接上 worker 的投递，UI 仍以 ChatStore 为准——但镜像是
// 按"将来要当权威"的规则在维护的，不是又一份影子比对。
//
// 【合并规则】worker 带来的字段一律以它为准，**除了三样本地独有、worker 拿不到
// 的东西**：
//   · avatarPath —— UI 解析完头像文件才有的路径；照片没换就一直保留
//   · typingText —— UI 侧"正在输入"的短时状态
//   · isLive / isRtmpLive —— 来自通话状态，不在这条数据链上
// 其余字段（含未读、预览、标题）一律覆盖，不做本地推测。

import { ChatEntry, cloneEntry } from './ChatEntry';
import { compareChatEntries } from './chatEntryFactory';

export class ChatMirror {
  private entries: Map<number, ChatEntry> = new Map<number, ChatEntry>();

  size(): number {
    return this.entries.size;
  }

  get(id: number): ChatEntry | undefined {
    return this.entries.get(id);
  }

  values(): ChatEntry[] {
    return Array.from(this.entries.values());
  }

  clear(): void {
    this.entries.clear();
  }

  // 本地独有字段的**写回**：UI 解析出头像路径、收到输入中、拿到直播状态时，
  // 镜像也必须跟着更新，否则切到 V2 读镜像时这些就没了（真机首测正是头像全空）。
  // 只在 worker 那条实体已经存在时才写，避免先造出一条空实体。
  setAvatarPath(chatId: number, path: string): void {
    const entry: ChatEntry | undefined = this.entries.get(chatId);
    if (entry === undefined || entry.avatarPath === path) {
      return;
    }
    const next: ChatEntry = cloneEntry(entry);
    next.avatarPath = path;
    this.entries.set(chatId, next);
  }

  setTyping(chatId: number, text: string): void {
    const entry: ChatEntry | undefined = this.entries.get(chatId);
    if (entry === undefined || entry.typingText === text) {
      return;
    }
    const next: ChatEntry = cloneEntry(entry);
    next.typingText = text;
    this.entries.set(chatId, next);
  }

  setLiveFlags(chatId: number, isLive: boolean, isRtmpLive: boolean): void {
    const entry: ChatEntry | undefined = this.entries.get(chatId);
    if (entry === undefined || (entry.isLive === isLive && entry.isRtmpLive === isRtmpLive)) {
      return;
    }
    const next: ChatEntry = cloneEntry(entry);
    next.isLive = isLive;
    next.isRtmpLive = isRtmpLive;
    this.entries.set(chatId, next);
  }

  // 合并一批 worker 实体，返回**真正变化**的条数（按 B4b 的可比字段口径，
  // revision 不计）。没变化的条目保持原对象身份，避免下游白刷。
  apply(remote: ChatEntry[]): number {
    let changed = 0;
    for (const incoming of remote) {
      const previous: ChatEntry | undefined = this.entries.get(incoming.id);
      const merged: ChatEntry = cloneEntry(incoming);
      if (previous !== undefined) {
        // 头像：照片没换就保住已经解析好的路径。
        merged.avatarPath = previous.photoFileId === incoming.photoFileId
          ? previous.avatarPath : '';
        merged.typingText = previous.typingText;
        if (previous.liveGroupCallId === incoming.liveGroupCallId) {
          merged.isLive = previous.isLive;
          merged.isRtmpLive = previous.isRtmpLive;
        }
        if (compareChatEntries(previous, merged) === '') {
          continue;
        }
        merged.revision = previous.revision + 1;
      } else {
        merged.revision = 0;
      }
      this.entries.set(incoming.id, merged);
      changed += 1;
    }
    return changed;
  }
}
