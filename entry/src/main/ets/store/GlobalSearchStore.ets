import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatMemberCount } from '../util/formatMemberCount';
import { str } from '../util/strings';
import { logE } from '../util/log';

const DL_PRIORITY: number = 1;

export interface SearchRow {
  chatId: number;
  userId: number; // >0 for app (bot) rows — open via createPrivateChat
  title: string;
  initials: string;
  avatarPath: string;
  subtitle: string;
  isChannel: boolean;
}

type Listener = () => void;
type Bucket = 'top' | 'recent' | 'opened' | 'results' | 'joined' | 'similar' | 'apps';

// Backing store for the global search page: frequent contacts (getTopChats),
// recently opened chats, and name-based chat search (local + public).
export class GlobalSearchStore {
  private client: TdClient;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private fileApply: Map<number, (path: string) => void> = new Map();
  private searchSeq: number = 0;
  private joinedResolvePending: number = 0;
  private similarResolvePending: number = 0;

  topUsers: SearchRow[] = [];
  recent: SearchRow[] = [];
  recentlyOpened: SearchRow[] = [];
  results: SearchRow[] = [];
  joinedChannels: SearchRow[] = [];
  similarChannels: SearchRow[] = [];
  apps: SearchRow[] = [];
  searching: boolean = false;
  searchFailed: boolean = false;
  topLoaded: boolean = false;
  recentLoaded: boolean = false;
  openedLoaded: boolean = false;
  topFailed: boolean = false;
  recentFailed: boolean = false;
  openedFailed: boolean = false;
  joinedLoaded: boolean = false;
  similarLoaded: boolean = false;
  appsLoaded: boolean = false;
  joinedFailed: boolean = false;
  similarFailed: boolean = false;
  appsFailed: boolean = false;

  // 自己的 user id（＝「我的收藏」那个私聊的 chat id）。loadTop 用它把收藏钉在
  // 常用联系人第一位；渲染层用它认出该行换标题和书签头像。
  private selfId: number = 0;

  selfChatId(): number {
    return this.selfId;
  }

  constructor(client: TdClient) {
    this.client = client;
  }

  subscribe(l: Listener): () => void {
    this.listeners = [...this.listeners, l];
    l();
    return (): void => { this.listeners = this.listeners.filter((x: Listener) => x !== l); };
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }

  open(): void {
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => {
      const f = u['file'] as TdObject | undefined;
      if (f !== undefined) {
        this.applyFile(f);
      }
    }));
    this.loadTop();
    this.loadRecent();
    this.loadRecentlyOpened();
    this.loadJoinedChannels();
    this.loadSimilarChannels();
    this.loadApps();
  }

  // 频道 tab landing: the channels the user has joined (from the main list).
  private loadJoinedChannels(): void {
    this.joinedLoaded = false;
    this.joinedFailed = false;
    this.joinedResolvePending = 0;
    this.notify();
    const req: TdRequest = { '@type': 'getChats' };
    req['chat_list'] = { '@type': 'chatListMain' } as TdObject;
    req['limit'] = 400;
    this.client.send(req).then((res: TdObject) => {
      const ids = (res['chat_ids'] as number[] | undefined) ?? [];
      this.joinedChannels = [];
      this.joinedResolvePending = ids.length;
      this.joinedLoaded = ids.length === 0;
      this.notify();
      for (const id of ids) {
        this.appendIfChannel('joined', id);
      }
    }).catch((e: TdError) => {
      this.joinedLoaded = true;
      this.joinedFailed = true;
      this.notify();
      logE(`GlobalSearchStore.getChats failed: ${e.message}`);
    });
  }

  // 频道 tab landing: server-recommended channels.
  private loadSimilarChannels(): void {
    this.similarLoaded = false;
    this.similarFailed = false;
    this.similarResolvePending = 0;
    this.notify();
    const req: TdRequest = { '@type': 'getRecommendedChats' };
    this.client.send(req).then((res: TdObject) => {
      const ids = (res['chat_ids'] as number[] | undefined) ?? [];
      this.similarChannels = [];
      this.similarResolvePending = ids.length;
      this.similarLoaded = ids.length === 0;
      this.notify();
      for (const id of ids) {
        this.appendIfChannel('similar', id);
      }
    }).catch((e: TdError) => {
      this.similarLoaded = true;
      this.similarFailed = true;
      this.notify();
      logE(`GlobalSearchStore.getRecommendedChats failed: ${e.message}`);
    });
  }

  // Resolve a chat and append it to a channel bucket only if it IS a channel.
  private appendIfChannel(bucket: Bucket, chatId: number): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    this.client.send(req).then((chat: TdObject) => {
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      const isChannel = typeName === 'chatTypeSupergroup'
        && (((type as TdObject)['is_channel'] as boolean | undefined) ?? false);
      if (!isChannel) {
        this.finishChannelResolve(bucket);
        return;
      }
      const title = (chat['title'] as string | undefined) ?? '';
      const row: SearchRow = {
        chatId, userId: 0, title,
        initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?',
        avatarPath: '', subtitle: str('gn_channel'), isChannel: true
      };
      this.setBucket(bucket, [...this.getBucket(bucket), row]);
      this.notify();
      this.finishChannelResolve(bucket);
      const sgId = ((type as TdObject)['supergroup_id'] as number | undefined) ?? 0;
      if (sgId > 0) {
        this.resolveSubscriberCount(bucket, chatId, sgId);
      }
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      this.download(fileId, (p: string) => {
        this.patch(bucket, chatId, (r: SearchRow): SearchRow => ({
          chatId: r.chatId, userId: r.userId, title: r.title, initials: r.initials,
          avatarPath: p, subtitle: r.subtitle, isChannel: r.isChannel
        }));
      });
    }).catch((e: TdError) => {
      this.finishChannelResolve(bucket);
      logE(`GlobalSearchStore.appendIfChannel(${chatId}) failed: ${e.message}`);
    });
  }

  private finishChannelResolve(bucket: Bucket): void {
    if (bucket === 'joined') {
      this.joinedResolvePending = Math.max(0, this.joinedResolvePending - 1);
      if (this.joinedResolvePending === 0) {
        this.joinedLoaded = true;
        this.notify();
      }
    } else if (bucket === 'similar') {
      this.similarResolvePending = Math.max(0, this.similarResolvePending - 1);
      if (this.similarResolvePending === 0) {
        this.similarLoaded = true;
        this.notify();
      }
    }
  }

  private resolveSubscriberCount(bucket: Bucket, chatId: number, supergroupId: number): void {
    const req: TdRequest = { '@type': 'getSupergroup' };
    req['supergroup_id'] = supergroupId;
    this.client.send(req).then((sg: TdObject) => {
      const count = (sg['member_count'] as number | undefined) ?? 0;
      if (count > 0) {
        this.patch(bucket, chatId, (r: SearchRow): SearchRow => ({
          chatId: r.chatId, userId: r.userId, title: r.title, initials: r.initials,
          avatarPath: r.avatarPath, subtitle: str('subtitle_subscribers', formatMemberCount(count)), isChannel: r.isChannel
        }));
      }
    }).catch((e: TdError) => {
      logE(`GlobalSearchStore.getSupergroup failed: ${e.message}`);
    });
  }

  // 应用 tab: top-grossing Telegram mini apps (bots).
  private loadApps(): void {
    this.appsLoaded = false;
    this.appsFailed = false;
    this.notify();
    const req: TdRequest = { '@type': 'getGrossingWebAppBots' };
    req['offset'] = '';
    req['limit'] = 30;
    this.client.send(req).then((res: TdObject) => {
      const ids = (res['user_ids'] as number[] | undefined) ?? [];
      this.apps = ids.map((id: number): SearchRow => ({
        chatId: 0, userId: id, title: '', initials: '?', avatarPath: '', subtitle: '', isChannel: false
      }));
      this.appsLoaded = true;
      this.notify();
      for (const id of ids) {
        this.resolveAppUser(id);
      }
    }).catch((e: TdError) => {
      this.appsLoaded = true;
      this.appsFailed = true;
      this.notify();
      logE(`GlobalSearchStore.getGrossingWebAppBots failed: ${e.message}`);
    });
  }

  private resolveAppUser(userId: number): void {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = userId;
    this.client.send(req).then((user: TdObject) => {
      const first = (user['first_name'] as string | undefined) ?? '';
      const last = (user['last_name'] as string | undefined) ?? '';
      const title = `${first}${last !== '' ? ' ' + last : ''}`;
      const type = user['type'] as TdObject | undefined;
      const active = type !== undefined ? ((type['active_user_count'] as number | undefined) ?? 0) : 0;
      const subtitle = active > 0 ? str('gs_monthly_users', formatMemberCount(active)) : str('gs_mini_app');
      this.apps = this.apps.map((r: SearchRow): SearchRow => r.userId === userId
        ? {
          chatId: r.chatId, userId: r.userId, title,
          initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?',
          avatarPath: r.avatarPath, subtitle, isChannel: false
        } : r);
      this.notify();
      const photo = user['profile_photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      this.download(fileId, (p: string) => {
        this.apps = this.apps.map((r: SearchRow): SearchRow => r.userId === userId
          ? {
            chatId: r.chatId, userId: r.userId, title: r.title, initials: r.initials,
            avatarPath: p, subtitle: r.subtitle, isChannel: false
          } : r);
        this.notify();
      });
    }).catch((e: TdError) => {
      this.apps = this.apps.filter((r: SearchRow) => r.userId !== userId);
      this.notify();
      logE(`GlobalSearchStore.resolveAppUser(${userId}) failed: ${e.message}`);
    });
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.listeners = [];
  }

  private loadTop(): void {
    this.topLoaded = false;
    this.topFailed = false;
    this.notify();
    const req: TdRequest = { '@type': 'getTopChats' };
    req['category'] = { '@type': 'topChatCategoryUsers' } as TdObject;
    req['limit'] = 10;
    // 先拿自己的 id（getMe 在 TDLib 侧是缓存命中，几乎无代价），把「我的收藏」
    // 钉在常用联系人第一位——官方客户端的搜索页就是这个顺序。getMe 失败就退回
    // 纯 getTopChats，别让收藏把整个横排拖死。
    const me: TdRequest = { '@type': 'getMe' };
    this.client.send(me).then((user: TdObject) => {
      this.selfId = (user['id'] as number | undefined) ?? 0;
      if (this.selfId > 0) {
        // 收藏会话可能从未创建过（chat id == user id，但对象未必存在）。
        // createPrivateChat 幂等，确保点进去有的可开。
        const cp: TdRequest = { '@type': 'createPrivateChat' };
        cp['user_id'] = this.selfId;
        this.client.send(cp).catch((e: TdError): void => {
          logE(`GlobalSearchStore.createPrivateChat(self) failed: ${e.message}`);
        });
      }
      return this.client.send(req);
    }).then((res: TdObject) => {
      this.topLoaded = true;
      const ids = ((res['chat_ids'] as number[] | undefined) ?? [])
        .filter((id: number): boolean => id !== this.selfId);
      this.fillBucket('top', this.selfId > 0 ? [this.selfId, ...ids] : ids);
    }).catch((e: TdError) => {
      this.topLoaded = true;
      this.topFailed = true;
      this.notify();
      logE(`GlobalSearchStore.getTopChats failed: ${e.message}`);
    });
  }

  private loadRecent(): void {
    this.recentLoaded = false;
    this.recentFailed = false;
    this.notify();
    // Empty searchChats returns the "recently found" list used by Telegram's
    // global-search landing. It is the same data source clearRecentlyFoundChats
    // clears; getRecentlyOpenedChats is a different, non-clearable history.
    const req: TdRequest = { '@type': 'searchChats' };
    req['query'] = '';
    req['limit'] = 20;
    this.client.send(req).then((res: TdObject) => {
      this.recentLoaded = true;
      this.fillBucket('recent', (res['chat_ids'] as number[] | undefined) ?? []);
    }).catch((e: TdError) => {
      this.recentLoaded = true;
      this.recentFailed = true;
      this.notify();
      logE(`GlobalSearchStore.loadRecent failed: ${e.message}`);
    });
  }

  private loadRecentlyOpened(): void {
    this.openedLoaded = false;
    this.openedFailed = false;
    this.notify();
    const req: TdRequest = { '@type': 'getRecentlyOpenedChats' };
    req['limit'] = 30;
    this.client.send(req).then((res: TdObject) => {
      this.openedLoaded = true;
      this.fillBucket('opened', (res['chat_ids'] as number[] | undefined) ?? []);
    }).catch((e: TdError) => {
      this.openedLoaded = true;
      this.openedFailed = true;
      this.notify();
      logE(`GlobalSearchStore.getRecentlyOpenedChats failed: ${e.message}`);
    });
  }

  clearRecent(): Promise<void> {
    const previous = [...this.recent];
    this.recent = [];
    this.notify();
    const req: TdRequest = { '@type': 'clearRecentlyFoundChats' };
    return this.client.send(req).then((): void => {}).catch((e: TdError) => {
      this.recent = previous;
      this.notify();
      logE(`GlobalSearchStore.clearRecentlyFoundChats failed: ${e.message}`);
      return Promise.reject(e);
    });
  }

  rememberFoundChat(chatId: number): void {
    if (chatId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'addRecentlyFoundChat' };
    req['chat_id'] = chatId;
    this.client.send(req).then((): void => {
      this.loadRecent();
    }).catch((e: TdError) => {
      logE(`GlobalSearchStore.addRecentlyFoundChat failed: ${e.message}`);
    });
  }

  retryLanding(): void {
    if (!this.topLoaded || this.topFailed) {
      this.loadTop();
    }
    if (!this.recentLoaded || this.recentFailed) {
      this.loadRecent();
    }
    if (!this.openedLoaded || this.openedFailed) {
      this.loadRecentlyOpened();
    }
  }

  retryChannels(): void {
    if (!this.joinedLoaded || this.joinedFailed) {
      this.loadJoinedChannels();
    }
    if (!this.similarLoaded || this.similarFailed) {
      this.loadSimilarChannels();
    }
  }

  retryApps(): void {
    if (!this.appsLoaded || this.appsFailed) {
      this.loadApps();
    }
  }

  // Name search: local known chats first, then public usernames; merged, deduped.
  searchChats(query: string): void {
    const q = query.trim();
    const seq = ++this.searchSeq;
    if (q === '') {
      this.results = [];
      this.searching = false;
      this.searchFailed = false;
      this.notify();
      return;
    }
    this.searching = true;
    this.searchFailed = false;
    this.notify();
    const local: TdRequest = { '@type': 'searchChats' };
    local['query'] = q;
    local['limit'] = 20;
    const pub: TdRequest = { '@type': 'searchPublicChats' };
    pub['query'] = q;
    this.client.send(local).then((localRes: TdObject) => {
      if (seq !== this.searchSeq) {
        return;
      }
      const ids = (localRes['chat_ids'] as number[] | undefined) ?? [];
      this.client.send(pub).then((pubRes: TdObject) => {
        if (seq !== this.searchSeq) {
          return;
        }
        const pubIds = (pubRes['chat_ids'] as number[] | undefined) ?? [];
        const merged: number[] = [...ids];
        for (const id of pubIds) {
          if (merged.indexOf(id) < 0) {
            merged.push(id);
          }
        }
        this.searching = false;
        this.searchFailed = false;
        this.fillBucket('results', merged);
      }).catch((e: TdError) => {
        // Public lookup can fail (e.g. too-short query) — local results still count.
        logE(`GlobalSearchStore.searchPublicChats failed: ${e.message}`);
        if (seq === this.searchSeq) {
          this.searching = false;
          this.searchFailed = false;
          this.fillBucket('results', ids);
        }
      });
    }).catch((e: TdError) => {
      logE(`GlobalSearchStore.searchChats failed: ${e.message}`);
      if (seq === this.searchSeq) {
        this.searching = false;
        this.searchFailed = true;
        this.results = [];
        this.notify();
      }
    });
  }

  // Replace a bucket with placeholder rows for the ids, then resolve each chat.
  private fillBucket(bucket: Bucket, ids: number[]): void {
    const rows: SearchRow[] = ids.map((id: number): SearchRow => ({
      chatId: id, userId: 0, title: '', initials: '?', avatarPath: '', subtitle: '', isChannel: false
    }));
    this.setBucket(bucket, rows);
    this.notify();
    for (const id of ids) {
      this.resolveChat(bucket, id);
    }
  }

  private setBucket(bucket: Bucket, rows: SearchRow[]): void {
    if (bucket === 'top') {
      this.topUsers = rows;
    } else if (bucket === 'recent') {
      this.recent = rows;
    } else if (bucket === 'opened') {
      this.recentlyOpened = rows;
    } else if (bucket === 'joined') {
      this.joinedChannels = rows;
    } else if (bucket === 'similar') {
      this.similarChannels = rows;
    } else if (bucket === 'apps') {
      this.apps = rows;
    } else {
      this.results = rows;
    }
  }

  private getBucket(bucket: Bucket): SearchRow[] {
    if (bucket === 'top') {
      return this.topUsers;
    } else if (bucket === 'recent') {
      return this.recent;
    } else if (bucket === 'opened') {
      return this.recentlyOpened;
    } else if (bucket === 'joined') {
      return this.joinedChannels;
    } else if (bucket === 'similar') {
      return this.similarChannels;
    } else if (bucket === 'apps') {
      return this.apps;
    }
    return this.results;
  }

  private patch(bucket: Bucket, chatId: number, fn: (r: SearchRow) => SearchRow): void {
    this.setBucket(bucket, this.getBucket(bucket).map((r: SearchRow): SearchRow =>
      r.chatId === chatId ? fn(r) : r));
    this.notify();
  }

  private resolveChat(bucket: Bucket, chatId: number): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    this.client.send(req).then((chat: TdObject) => {
      const rawTitle = (chat['title'] as string | undefined) ?? '';
      // 和自己的私聊就是「我的收藏」。TDLib 对它没有任何特殊标记（标题是自己的
      // 昵称，见 issue #8），只能按 chatId === selfId 认。
      const isSelf: boolean = this.selfId > 0 && chatId === this.selfId;
      const title = isSelf ? str('cl_saved_messages')
        : (rawTitle !== '' ? rawTitle : str('deleted_account'));
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      const isChannel = typeName === 'chatTypeSupergroup'
        && (((type as TdObject)['is_channel'] as boolean | undefined) ?? false);
      let subtitle = '';
      if (typeName === 'chatTypeSupergroup') {
        subtitle = isChannel ? str('gn_channel') : str('gn_group');
      } else if (typeName === 'chatTypeBasicGroup') {
        subtitle = str('gn_group');
      }
      this.patch(bucket, chatId, (r: SearchRow): SearchRow => ({
        chatId: r.chatId, userId: r.userId, title,
        initials: rawTitle.length > 0 ? rawTitle.substring(0, 1).toUpperCase() : '?',
        avatarPath: r.avatarPath, subtitle: subtitle !== '' ? subtitle : r.subtitle, isChannel
      }));
      if (typeName === 'chatTypePrivate' && !isSelf) {
        const uid = ((type as TdObject)['user_id'] as number | undefined) ?? 0;
        if (uid > 0) {
          this.resolveUserSubtitle(bucket, chatId, uid);
        }
      }
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      this.download(fileId, (p: string) => {
        this.patch(bucket, chatId, (r: SearchRow): SearchRow => ({
          chatId: r.chatId, userId: r.userId, title: r.title, initials: r.initials,
          avatarPath: p, subtitle: r.subtitle, isChannel: r.isChannel
        }));
      });
    }).catch((e: TdError) => {
      this.setBucket(bucket, this.getBucket(bucket).filter((r: SearchRow) => r.chatId !== chatId));
      this.notify();
      logE(`GlobalSearchStore.getChat(${chatId}) failed: ${e.message}`);
    });
  }

  // Private chat subtitle: 机器人 for bots, otherwise the last-seen status.
  private resolveUserSubtitle(bucket: Bucket, chatId: number, userId: number): void {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = userId;
    this.client.send(req).then((user: TdObject) => {
      const type = user['type'] as TdObject | undefined;
      const isBot = type !== undefined && ((type['@type'] as string | undefined) ?? '') === 'userTypeBot';
      const subtitle = isBot ? str('fe_bots')
        : formatUserStatus(user['status'] as TdObject | undefined, Math.floor(Date.now() / 1000));
      this.patch(bucket, chatId, (r: SearchRow): SearchRow => ({
        chatId: r.chatId, userId: r.userId, title: r.title, initials: r.initials,
        avatarPath: r.avatarPath, subtitle, isChannel: r.isChannel
      }));
    }).catch((e: TdError) => {
      logE(`GlobalSearchStore.getUser(${userId}) failed: ${e.message}`);
    });
  }

  private download(fileId: number, apply: (path: string) => void): void {
    if (fileId <= 0) {
      return;
    }
    this.fileApply.set(fileId, apply);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = DL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((e: TdError) => {
      logE(`GlobalSearchStore.downloadFile failed: ${e.message}`);
    });
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const apply = this.fileApply.get(id);
    if (apply === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    const done = local !== undefined ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    if (done && path !== '') {
      apply(path);
    }
  }
}
