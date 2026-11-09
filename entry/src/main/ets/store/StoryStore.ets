import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from '../util/log';

export interface StoryRingEntry {
  chatId: number;
  order: number;
  storyIds: number[];       // 升序（发布时间序）
  maxReadStoryId: number;
  hasUnread: boolean;
  isSelf: boolean;          // 自己的那一项，环里固定排第一
}

type StoryListener = (entries: StoryRingEntry[]) => void;

// 聊天列表顶部故事环的数据源：主故事列表（storyListMain）的活跃故事集合。
// TDLib 通过 updateChatActiveStories 推送每个会话的故事快照，空列表即移除。
export class StoryStore {
  private client: TdClient;
  private entriesById: Map<number, StoryRingEntry> = new Map();
  private subs: StoryListener[] = [];
  private opened: boolean = false;
  // 自己的会话 id。自己的那一项在环里固定排第一（和官方客户端一致），而不是
  // 按 order 混进联系人里。0 表示还没拿到，此时先按普通项收着，拿到之后重排。
  private selfId: number = 0;

  constructor(client: TdClient) {
    this.client = client;
    client.onUpdate('updateChatActiveStories', (u: TdObject) => this.onActiveStories(u));
  }

  // Must not run from the constructor: the store is built before client.start(),
  // so getMe would be sent unauthorized, fail, and leave selfId at 0 — the ring
  // would then never know which entry is yours.
  // open() runs at AuthStage.Ready, where getMe is answerable.
  private resolveSelf(): void {
    this.client.send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
      // 私聊的 chat_id 等于 user_id。
      this.selfId = (me['id'] as number | undefined) ?? 0;
      if (this.selfId !== 0) {
        this.publish();
      }
    }).catch((e: TdError): void => {
      logE(`StoryStore.getMe failed: ${e.message}`);
    });
  }

  // 自己的会话 id；0 表示 getMe 还没回来。环需要它来渲染「我的动态」那一格，
  // 包括自己还没发过动态、环里根本没有自己这项的情况。
  selfChatId(): number {
    return this.selfId;
  }

  // 触发 TDLib 拉取主故事列表（结果全部经 update 回流）。
  open(): void {
    if (this.opened) {
      return;
    }
    this.opened = true;
    this.resolveSelf();
    const req: TdRequest = { '@type': 'loadActiveStories' };
    req['story_list'] = { '@type': 'storyListMain' } as TdObject;
    this.client.send(req).catch((e: TdError): void => {
      // 404 = 列表已到底（无更多会话），是正常终止信号。
      if (e.code !== 404) {
        logE(`StoryStore.loadActiveStories failed: ${e.message}`);
      }
    });
  }

  subscribe(l: StoryListener): () => void {
    this.subs = [...this.subs, l];
    l(this.entries());
    return (): void => {
      this.subs = this.subs.filter((x: StoryListener) => x !== l);
    };
  }

  // 自己永远第一，其余按 order 降序——order 是 TDLib 给的联系人排序，把自己
  // 也丢进去比较的话，自己会随它上下跳。
  entries(): StoryRingEntry[] {
    return Array.from(this.entriesById.values())
      .map((e: StoryRingEntry): StoryRingEntry => {
        e.isSelf = this.selfId !== 0 && e.chatId === this.selfId;
        return e;
      })
      .sort((a: StoryRingEntry, b: StoryRingEntry) => {
        if (a.isSelf !== b.isSelf) {
          return a.isSelf ? -1 : 1;
        }
        return b.order - a.order;
      });
  }

  entryOf(chatId: number): StoryRingEntry | undefined {
    return this.entriesById.get(chatId);
  }

  private onActiveStories(u: TdObject): void {
    const active = u['active_stories'] as TdObject | undefined;
    if (active === undefined) {
      return;
    }
    const chatId: number = (active['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      return;
    }
    const list = active['list'] as TdObject | undefined;
    const listType: string = list !== undefined
      ? ((list['@type'] as string | undefined) ?? '') : '';
    const infos: TdObject[] = (active['stories'] as TdObject[] | undefined) ?? [];
    // 归档（被隐藏的联系人）不进主环；故事过期清空后同样移除。
    if (infos.length === 0 || listType === 'storyListArchive') {
      if (this.entriesById.delete(chatId)) {
        this.publish();
      }
      return;
    }
    const maxRead: number = (active['max_read_story_id'] as number | undefined) ?? 0;
    const storyIds: number[] = infos
      .map((info: TdObject): number => (info['story_id'] as number | undefined) ?? 0)
      .filter((id: number): boolean => id > 0)
      .sort((a: number, b: number) => a - b);
    this.entriesById.set(chatId, {
      chatId: chatId,
      order: (active['order'] as number | undefined) ?? 0,
      storyIds: storyIds,
      maxReadStoryId: maxRead,
      hasUnread: storyIds.some((id: number): boolean => id > maxRead),
      isSelf: this.selfId !== 0 && chatId === this.selfId
    });
    this.publish();
  }

  private publish(): void {
    const snapshot = this.entries();
    for (const l of this.subs) {
      l(snapshot);
    }
  }
}
