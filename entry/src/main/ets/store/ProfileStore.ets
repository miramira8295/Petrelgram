import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatMemberCount } from '../util/formatMemberCount';
import { formatPreview } from '../util/formatPreview';
import { str } from '../util/strings';
import { monthDay } from '../util/intlFormat';
import { logE, logI } from '../util/log';

const DL_PRIORITY: number = 1;
const WEEK_MINUTES: number = 7 * 24 * 60;
const STATUS_REFRESH_INTERVAL_MS: number = 30 * 1000;

export interface CommonGroup {
  id: number;
  title: string;
  initials: string;
  avatarPath: string;
}

export interface StoryItem {
  id: number;
  thumbPath: string;
  duration: number; // seconds, 0 for photos
  isVideo: boolean;
}

interface ParsedStory {
  item: StoryItem;
  thumbFileId: number;
}

export interface GiftItem {
  id: string;
  stickerPath: string;
}

// A gift from the catalog that can be sent (price in Telegram Stars).
export interface AvailGift {
  id: string; // int64 — kept as the raw JSON string to avoid precision loss
  stickerPath: string;
  stars: number;
}

type Listener = () => void;

// Backing store for the user profile page: user card, business info, personal
// channel, common groups, profile stories and received gifts.
export class ProfileStore {
  private client: TdClient;
  private userId: number;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  // file id → apply(path) for every thumbnail/avatar this store downloads
  private fileApply: Map<number, (path: string) => void> = new Map();
  private avatarVersion: number = 0;
  private avatarAnimationVersion: number = 0;
  private statusEmojiVersion: number = 0;
  private storiesVersion: number = 0;
  private archivedStoriesVersion: number = 0;
  private userStatus: TdObject | undefined = undefined;
  private statusRefreshTimer: number = -1;
  private active: boolean = false;

  name: string = '';
  initials: string = '?';
  avatarPath: string = '';
  avatarAnimPath: string = ''; // animated profile photo (MPEG4), '' if none
  // Premium emoji status (the animated custom emoji beside the name).
  statusEmojiPath: string = '';
  statusEmojiFormat: string = ''; // 'tgs' | 'webm' | 'webp'
  statusText: string = '';
  phone: string = '';
  usernames: string[] = [];
  isContact: boolean = false;
  bio: string = '';
  bioEntities: TdObject[] = []; // formattedText entities (links/mentions in the bio)
  birthday: string = ''; // "3月1日" from userFullInfo.birthdate, '' if not shared
  privateChatId: number = 0;
  personalChatId: number = 0;
  bizOpen: boolean = false;
  bizHoursText: string = '';
  bizAddress: string = '';
  bizLat: number = 0;
  bizLng: number = 0;
  chTitle: string = '';
  chInitials: string = '?';
  chAvatarPath: string = '';
  chSubs: string = '';
  chPreview: string = '';
  groups: CommonGroup[] = [];
  stories: StoryItem[] = [];
  storiesLoading: boolean = true;
  storiesError: string = '';
  archivedStories: StoryItem[] = [];
  archivedStoriesLoading: boolean = false;
  archivedStoriesLoaded: boolean = false;
  archivedStoriesError: string = '';
  gifts: GiftItem[] = [];
  availableGifts: AvailGift[] = [];
  private availableLoaded: boolean = false;

  constructor(client: TdClient, userId: number) {
    this.client = client;
    this.userId = userId;
  }

  subscribe(l: Listener): () => void {
    this.listeners = [...this.listeners, l];
    l();
    return (): void => { this.listeners = this.listeners.filter((x: Listener) => x !== l); };
  }

  open(): void {
    this.active = true;
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => {
      const f = u['file'] as TdObject | undefined;
      if (f !== undefined) {
        this.applyFile(f);
      }
    }));
    // Emoji status / name / photo edits arrive as updateUser; without this the
    // page keeps the snapshot from the first getUser until the store is rebuilt.
    this.unsubs.push(this.client.onUpdate('updateUser', (u: TdObject) => {
      const user = u['user'] as TdObject | undefined;
      if (user !== undefined && (user['id'] as number | undefined) === this.userId) {
        this.applyUser(user);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => {
      if ((u['user_id'] as number | undefined) === this.userId) {
        this.applyUserStatus(u['status'] as TdObject | undefined, true);
      }
    }));
    // A posted story only becomes real when TDLib says so. Both spellings are
    // subscribed because the update was renamed across TDLib versions and an
    // unknown name simply never fires.
    for (const name of ['updateStoryPostSucceeded', 'updateStorySendSucceeded',
      'updateStoryDeleted']) {
      this.unsubs.push(this.client.onUpdate(name, (): void => { this.refreshStories(); }));
    }
    this.loadUser();
    this.loadFullInfo();
    this.loadStories();
    this.loadGifts();
  }

  close(): void {
    this.active = false;
    this.storiesVersion++;
    this.archivedStoriesVersion++;
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.stopStatusRefresh();
    this.listeners = [];
  }

  // Re-fetch user + full info (e.g. after the profile photo or bio changed).
  reload(): void {
    this.loadUser();
    this.loadFullInfo();
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }

  private applyUserStatus(status: TdObject | undefined, notifyChange: boolean): void {
    this.userStatus = status;
    const next = formatUserStatus(status, Math.floor(Date.now() / 1000));
    const changed = next !== this.statusText;
    this.statusText = next;
    this.updateStatusRefresh();
    if (notifyChange && changed) {
      this.notify();
    }
  }

  private updateStatusRefresh(): void {
    if (!this.active) {
      this.stopStatusRefresh();
      return;
    }
    const type = this.userStatus !== undefined
      ? (this.userStatus['@type'] as string | undefined) : undefined;
    if (type !== 'userStatusOffline') {
      this.stopStatusRefresh();
      return;
    }
    if (this.statusRefreshTimer !== -1) {
      return;
    }
    this.statusRefreshTimer = setInterval((): void => {
      const next = formatUserStatus(this.userStatus, Math.floor(Date.now() / 1000));
      if (next !== this.statusText) {
        this.statusText = next;
        this.notify();
      }
    }, STATUS_REFRESH_INTERVAL_MS);
  }

  private stopStatusRefresh(): void {
    if (this.statusRefreshTimer !== -1) {
      clearInterval(this.statusRefreshTimer);
      this.statusRefreshTimer = -1;
    }
  }

  private send(req: TdRequest, tag: string, onOk: (res: TdObject) => void,
    onError?: (error: TdError) => void): void {
    this.client.send(req).then(onOk).catch((e: TdError) => {
      logE(`ProfileStore.${tag} failed: ${e.message}`);
      if (onError !== undefined) {
        onError(e);
      }
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
    this.send(req, 'downloadFile', (f: TdObject) => this.applyFile(f));
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
      this.notify();
    }
  }

  private loadUser(): void {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = this.userId;
    this.send(req, 'getUser', (user: TdObject) => this.applyUser(user));
  }

  private applyUser(user: TdObject): void {
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    this.name = `${first}${last !== '' ? ' ' + last : ''}`;
    this.initials = this.name.length > 0 ? this.name.substring(0, 1).toUpperCase() : '?';
    this.phone = (user['phone_number'] as string | undefined) ?? '';
    this.isContact = (user['is_contact'] as boolean | undefined) ?? false;
    this.applyUserStatus(user['status'] as TdObject | undefined, false);
    const un = user['usernames'] as TdObject | undefined;
    this.usernames = un !== undefined ? ((un['active_usernames'] as string[] | undefined) ?? []) : [];
    const photo = user['profile_photo'] as TdObject | undefined;
    const big = photo !== undefined ? (photo['big'] as TdObject | undefined) : undefined;
    const fileId = big !== undefined ? ((big['id'] as number | undefined) ?? 0) : 0;
    const avatarVersion = ++this.avatarVersion;
    if (fileId <= 0) {
      this.avatarPath = '';
    } else {
      this.download(fileId, (p: string) => {
        if (avatarVersion === this.avatarVersion) {
          this.avatarPath = p;
        }
      });
    }
    this.parseEmojiStatus(user['emoji_status'] as TdObject | undefined);
    this.notify();
  }

  // emoji_status.custom_emoji_id (older TDLib) or emoji_status.type.custom_emoji_id
  // (newer) → getCustomEmojiStickers → the sticker file behind the status.
  private parseEmojiStatus(es: TdObject | undefined): void {
    const statusEmojiVersion = ++this.statusEmojiVersion;
    this.statusEmojiPath = '';
    this.statusEmojiFormat = '';
    if (es === undefined) {
      return;
    }
    const nestedType = es['type'] as TdObject | undefined;
    const rawId = (nestedType !== undefined ? nestedType['custom_emoji_id'] : undefined)
      ?? es['custom_emoji_id'];
    const ceId = rawId !== undefined ? `${rawId}` : '';
    if (ceId === '' || ceId === '0') {
      return;
    }
    const req: TdRequest = { '@type': 'getCustomEmojiStickers' };
    req['custom_emoji_ids'] = [ceId];
    this.send(req, 'getCustomEmojiStickers', (res: TdObject) => {
      if (statusEmojiVersion !== this.statusEmojiVersion) {
        return;
      }
      const stickers = (res['stickers'] as TdObject[] | undefined) ?? [];
      if (stickers.length === 0) {
        return;
      }
      const st = stickers[0];
      const fmt = st['format'] as TdObject | undefined;
      const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
      this.statusEmojiFormat = fmtName === 'stickerFormatWebp' ? 'webp'
        : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
      const file = st['sticker'] as TdObject | undefined;
      const stickerId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      this.download(stickerId, (p: string) => {
        if (statusEmojiVersion === this.statusEmojiVersion) {
          this.statusEmojiPath = p;
        }
      });
    });
  }

  private loadFullInfo(): void {
    const req: TdRequest = { '@type': 'getUserFullInfo' };
    req['user_id'] = this.userId;
    this.send(req, 'getUserFullInfo', (full: TdObject) => {
      const bioFt = full['bio'] as TdObject | undefined;
      this.bio = bioFt !== undefined ? ((bioFt['text'] as string | undefined) ?? '') : '';
      this.bioEntities = bioFt !== undefined ? ((bioFt['entities'] as TdObject[] | undefined) ?? []) : [];
      // Bots have no bio; surface the bot description in its place.
      if (this.bio === '') {
        const botInfo = full['bot_info'] as TdObject | undefined;
        const botDesc = botInfo !== undefined ? ((botInfo['short_description'] as string | undefined) ?? '') : '';
        const botFull = botInfo !== undefined ? ((botInfo['description'] as string | undefined) ?? '') : '';
        this.bio = botDesc !== '' ? botDesc : botFull;
      }
      // Animated profile photo: userFullInfo.photo is a chatPhoto whose
      // optional `animation` is a small MPEG4 loop (getUser only carries the
      // static profilePhoto + a has_animation flag, not the file itself).
      const photoFull = (full['photo'] as TdObject | undefined)
        ?? (full['personal_photo'] as TdObject | undefined)
        ?? (full['public_photo'] as TdObject | undefined);
      const anim = photoFull !== undefined ? (photoFull['animation'] as TdObject | undefined) : undefined;
      const animFile = anim !== undefined ? (anim['file'] as TdObject | undefined) : undefined;
      const animId = animFile !== undefined ? ((animFile['id'] as number | undefined) ?? 0) : 0;
      const animationVersion = ++this.avatarAnimationVersion;
      // 诊断：用户报"别人的动态头像会动，自己的不动"，而两页走的是同一个
      // store、同一段代码。把这段的输入全打出来，自己的和别人的各开一次就
      // 能看出差在哪一环。
      if (animId <= 0) {
        this.avatarAnimPath = '';
      } else {
        this.download(animId, (p: string) => {
          if (animationVersion === this.avatarAnimationVersion) {
            this.avatarAnimPath = p;
          }
        });
      }
      this.personalChatId = (full['personal_chat_id'] as number | undefined) ?? 0;
      const bd = full['birthdate'] as TdObject | undefined;
      if (bd !== undefined) {
        const day = (bd['day'] as number | undefined) ?? 0;
        const month = (bd['month'] as number | undefined) ?? 0;
        // A birthday has no year; Intl needs a Date, so the year is arbitrary
        // and never rendered. The month/day order is locale business.
        this.birthday = (day > 0 && month > 0)
          ? monthDay(new Date(2000, month - 1, day)) : '';
      } else {
        this.birthday = '';
      }
      this.parseBusiness(full['business_info'] as TdObject | undefined);
      if (this.personalChatId !== 0) {
        this.loadChannel(this.personalChatId);
      }
      const groupCount = (full['group_in_common_count'] as number | undefined) ?? 0;
      logI(`ProfileStore: fullInfo groups=${groupCount} gifts=${(full['gift_count'] as number | undefined) ?? 0} personalChat=${this.personalChatId}`);
      if (groupCount > 0) {
        this.loadGroupsInCommon();
      }
      this.notify();
    });
  }

  // "营业中 / 7 × 24 小时营业" from Telegram Business opening hours.
  private parseBusiness(biz: TdObject | undefined): void {
    if (biz === undefined) {
      return;
    }
    this.bizOpen = ((biz['next_close_in'] as number | undefined) ?? 0) > 0;
    const hours = (biz['local_opening_hours'] as TdObject | undefined)
      ?? (biz['opening_hours'] as TdObject | undefined);
    if (hours !== undefined) {
      const intervals = (hours['opening_hours'] as TdObject[] | undefined) ?? [];
      let total = 0;
      for (const iv of intervals) {
        total += ((iv['end_minute'] as number | undefined) ?? 0) - ((iv['start_minute'] as number | undefined) ?? 0);
      }
      this.bizHoursText = total >= WEEK_MINUTES ? str('ps_open_24_7') : str('ps_view_hours');
    }
    const loc = biz['location'] as TdObject | undefined;
    this.bizAddress = loc !== undefined ? ((loc['address'] as string | undefined) ?? '') : '';
    const point = loc !== undefined ? (loc['location'] as TdObject | undefined) : undefined;
    this.bizLat = point !== undefined ? ((point['latitude'] as number | undefined) ?? 0) : 0;
    this.bizLng = point !== undefined ? ((point['longitude'] as number | undefined) ?? 0) : 0;
  }

  private loadChannel(chatId: number): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    this.send(req, 'getChat(channel)', (chat: TdObject) => {
      this.chTitle = (chat['title'] as string | undefined) ?? '';
      this.chInitials = this.chTitle.length > 0 ? this.chTitle.substring(0, 1).toUpperCase() : '?';
      this.chPreview = formatPreview(chat['last_message'] as TdObject | undefined ?? null);
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      this.download(small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0,
        (p: string) => { this.chAvatarPath = p; });
      const type = chat['type'] as TdObject | undefined;
      const sgId = type !== undefined ? ((type['supergroup_id'] as number | undefined) ?? 0) : 0;
      if (sgId !== 0) {
        const sg: TdRequest = { '@type': 'getSupergroupFullInfo' };
        sg['supergroup_id'] = sgId;
        this.send(sg, 'getSupergroupFullInfo', (f: TdObject) => {
          const c = (f['member_count'] as number | undefined) ?? 0;
          if (c > 0) {
            this.chSubs = str('subtitle_subscribers', formatMemberCount(c));
            this.notify();
          }
        });
      }
      this.notify();
    });
  }

  // Page through ALL groups in common (the API caps each page; keep requesting
  // from the last chat id until a page comes back empty).
  private loadGroupsInCommon(offsetChatId: number = 0): void {
    const req: TdRequest = { '@type': 'getGroupsInCommon' };
    req['user_id'] = this.userId;
    req['offset_chat_id'] = offsetChatId;
    req['limit'] = 100;
    this.send(req, 'getGroupsInCommon', (res: TdObject) => {
      const ids = (res['chat_ids'] as number[] | undefined) ?? [];
      logI(`ProfileStore: groupsInCommon page=${ids.length} offset=${offsetChatId}`);
      if (ids.length > 0) {
        this.loadGroupsInCommon(ids[ids.length - 1]);
      }
      for (const id of ids) {
        const cr: TdRequest = { '@type': 'getChat' };
        cr['chat_id'] = id;
        this.send(cr, 'getChat(group)', (chat: TdObject) => {
          const title = (chat['title'] as string | undefined) ?? '';
          const g: CommonGroup = {
            id,
            title,
            initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?',
            avatarPath: ''
          };
          this.groups = [...this.groups, g];
          const photo = chat['photo'] as TdObject | undefined;
          const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
          this.download(small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0,
            (p: string) => {
              this.groups = this.groups.map((x: CommonGroup): CommonGroup => x.id === id
                ? { id: x.id, title: x.title, initials: x.initials, avatarPath: p } : x);
            });
          this.notify();
        });
      }
    });
  }

  // Profile ("posted to chat page") stories — the 动态 grid.
  private loadStories(): void {
    const version = ++this.storiesVersion;
    this.stories = [];
    this.storiesLoading = true;
    this.storiesError = '';
    this.notify();
    // Both requests go out at once.
    //
    // The stories query never needed the chat object: a user's chat id equals
    // the user id, and that is what loadStoriesNow() sends. Chaining it behind
    // createPrivateChat put a full round trip in front of every profile open —
    // the "stories take ages to load" — and made a createPrivateChat failure
    // blank the grid for a reason that has nothing to do with stories.
    // createPrivateChat still runs: privateChatId feeds the shared-content
    // store and message jumps. It just no longer gates this.
    this.loadStoriesNow(version);
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = this.userId;
    create['force'] = false;
    this.send(create, 'createPrivateChat', (chat: TdObject): void => {
      this.privateChatId = (chat['id'] as number | undefined) ?? this.userId;
      this.notify();
    }, (): void => {
      logE(`ProfileStore.createPrivateChat(${this.userId}) failed`);
    });
  }

  reloadStories(): void {
    if (!this.storiesLoading) {
      this.loadStories();
    }
  }

  // Re-query the grid without clearing it first.
  //
  // postStory resolves as soon as TDLib accepts the upload, not when the story
  // exists server-side, so the reload the caller fires right after it came back
  // without the new story and the grid sat stale until the page was reopened.
  // The authoritative signal is the update below; this refresh has to be silent
  // because loadStories() blanks the list and would flash an empty grid every
  // time one arrives.
  private refreshStories(): void {
    if (this.storiesLoading) {
      return;
    }
    this.loadStoriesNow(++this.storiesVersion);
  }

  private failStories(version: number): void {
    if (version !== this.storiesVersion) {
      return;
    }
    this.storiesLoading = false;
    this.storiesError = str('ps_stories_failed');
    this.notify();
  }

  private parseStory(story: TdObject): ParsedStory | null {
    const id = (story['id'] as number | undefined) ?? 0;
    const content = story['content'] as TdObject | undefined;
    const contentType = content !== undefined
      ? ((content['@type'] as string | undefined) ?? '') : '';
    let thumbFileId = 0;
    let duration = 0;
    let isVideo = false;
    if (contentType === 'storyContentVideo') {
      isVideo = true;
      const video = content!['video'] as TdObject | undefined;
      duration = video !== undefined
        ? Math.round((video['duration'] as number | undefined) ?? 0) : 0;
      const thumb = video !== undefined ? (video['thumbnail'] as TdObject | undefined) : undefined;
      const file = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
      thumbFileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    } else if (contentType === 'storyContentPhoto') {
      const photo = content!['photo'] as TdObject | undefined;
      const sizes = photo !== undefined ? ((photo['sizes'] as TdObject[] | undefined) ?? []) : [];
      if (sizes.length > 0) {
        const file = sizes[0]['photo'] as TdObject | undefined;
        thumbFileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      }
    } else {
      return null;
    }
    if (id <= 0) {
      return null;
    }
    return {
      item: { id, thumbPath: '', duration, isVideo },
      thumbFileId
    };
  }

  private applyStoryResults(parsed: ParsedStory[], archived: boolean, version: number): void {
    if ((archived && version !== this.archivedStoriesVersion) ||
      (!archived && version !== this.storiesVersion)) {
      return;
    }
    const items = parsed.map((entry: ParsedStory): StoryItem => entry.item);
    if (archived) {
      this.archivedStories = items;
      this.archivedStoriesLoading = false;
      this.archivedStoriesLoaded = true;
      this.archivedStoriesError = '';
    } else {
      this.stories = items;
      this.storiesLoading = false;
      this.storiesError = '';
    }
    this.notify();
    for (const entry of parsed) {
      if (entry.thumbFileId <= 0) {
        continue;
      }
      const storyId = entry.item.id;
      this.download(entry.thumbFileId, (path: string): void => {
        if (archived) {
          if (version !== this.archivedStoriesVersion) {
            return;
          }
          this.archivedStories = this.archivedStories.map((item: StoryItem): StoryItem =>
            item.id === storyId
              ? { id: item.id, thumbPath: path, duration: item.duration, isVideo: item.isVideo }
              : item);
        } else {
          if (version !== this.storiesVersion) {
            return;
          }
          this.stories = this.stories.map((item: StoryItem): StoryItem =>
            item.id === storyId
              ? { id: item.id, thumbPath: path, duration: item.duration, isVideo: item.isVideo }
              : item);
        }
      });
    }
  }

  private loadStoriesNow(version: number): void {
    const req: TdRequest = { '@type': 'getChatPostedToChatPageStories' };
    req['chat_id'] = this.userId; // a user's chat id equals the user id
    req['from_story_id'] = 0;
    req['limit'] = 30;
    this.send(req, 'getStories', (res: TdObject): void => {
      if (version !== this.storiesVersion) {
        return;
      }
      const arr = (res['stories'] as TdObject[] | undefined) ?? [];
      const parsed: ParsedStory[] = [];
      for (const story of arr) {
        const entry = this.parseStory(story);
        if (entry !== null) {
          parsed.push(entry);
        }
      }
      this.applyStoryResults(parsed, false, version);
    }, (): void => {
      this.failStories(version);
    });
  }

  loadArchivedStories(force: boolean = false): void {
    if (this.archivedStoriesLoading || (this.archivedStoriesLoaded && !force)) {
      return;
    }
    const version = ++this.archivedStoriesVersion;
    this.archivedStoriesLoading = true;
    this.archivedStoriesError = '';
    if (force) {
      this.archivedStories = [];
    }
    this.notify();
    // A user's own archive is different from storyListArchive (the latter is
    // the list of active stories belonging to archived chats). Materialize the
    // Saved Messages/private chat first, then request stories posted by it.
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = this.userId;
    create['force'] = false;
    this.send(create, 'createPrivateChatForArchive', (chat: TdObject): void => {
      if (version !== this.archivedStoriesVersion) {
        return;
      }
      const chatId = (chat['id'] as number | undefined) ?? this.userId;
      this.loadArchivedStoriesNow(version, chatId);
    }, (): void => {
      if (version !== this.archivedStoriesVersion) {
        return;
      }
      this.archivedStoriesLoading = false;
      this.archivedStoriesError = str('ps_archived_failed');
      this.notify();
    });
  }

  private loadArchivedStoriesNow(version: number, chatId: number): void {
    const req: TdRequest = { '@type': 'getChatArchivedStories' };
    req['chat_id'] = chatId;
    req['from_story_id'] = 0;
    req['limit'] = 30;
    this.send(req, 'getArchivedStories', (res: TdObject): void => {
      if (version !== this.archivedStoriesVersion) {
        return;
      }
      const arr = (res['stories'] as TdObject[] | undefined) ?? [];
      const parsed: ParsedStory[] = [];
      for (const story of arr) {
        const entry = this.parseStory(story);
        if (entry !== null) {
          parsed.push(entry);
        }
      }
      this.applyStoryResults(parsed, true, version);
    }, (): void => {
      if (version !== this.archivedStoriesVersion) {
        return;
      }
      this.archivedStoriesLoading = false;
      this.archivedStoriesError = str('ps_archived_failed');
      this.notify();
    });
  }

  // Raster file id for a sticker: prefer the thumbnail (TGS/WEBM animated
  // stickers can't be rendered by Image); WEBP stickers may use the file itself.
  private stickerRasterFileId(sticker: TdObject | undefined): number {
    if (sticker === undefined) {
      return 0;
    }
    const thumb = sticker['thumbnail'] as TdObject | undefined;
    const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
    let fileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      const fmt = sticker['format'] as TdObject | undefined;
      if (fmt !== undefined && fmt['@type'] === 'stickerFormatWebp') {
        const file = sticker['sticker'] as TdObject | undefined;
        fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      }
    }
    return fileId;
  }

  // Gift catalog for the send-gift picker (prices are in Telegram Stars).
  loadAvailableGifts(): void {
    if (this.availableLoaded) {
      return;
    }
    this.availableLoaded = true;
    const req: TdRequest = { '@type': 'getAvailableGifts' };
    this.send(req, 'getAvailableGifts', (res: TdObject) => {
      const arr = (res['gifts'] as TdObject[] | undefined) ?? [];
      logI(`ProfileStore: availableGifts=${arr.length}`);
      for (const ag of arr) {
        const gift = ag['gift'] as TdObject | undefined;
        if (gift === undefined) {
          continue;
        }
        const id = `${gift['id']}`; // int64 arrives as a string in TDLib JSON
        const stars = (gift['star_count'] as number | undefined) ?? 0;
        const item: AvailGift = { id, stickerPath: '', stars };
        this.availableGifts = [...this.availableGifts, item];
        this.download(this.stickerRasterFileId(gift['sticker'] as TdObject | undefined), (p: string) => {
          this.availableGifts = this.availableGifts.map((x: AvailGift): AvailGift => x.id === id
            ? { id: x.id, stickerPath: p, stars: x.stars } : x);
        });
      }
      this.notify();
    });
  }

  // Send a catalog gift to this user, paying with the account's Star balance.
  sendGift(giftId: string, onResult: (error: string) => void): void {
    const owner: TdObject = { '@type': 'messageSenderUser' };
    owner['user_id'] = this.userId;
    const text: TdObject = { '@type': 'formattedText' };
    text['text'] = '';
    const req: TdRequest = { '@type': 'sendGift' };
    req['gift_id'] = giftId;
    req['owner_id'] = owner;
    req['text'] = text;
    req['is_private'] = false;
    req['pay_for_upgrade'] = false;
    this.client.send(req).then(() => {
      onResult('');
    }).catch((e: TdError) => {
      logE(`ProfileStore.sendGift failed: ${e.message}`);
      onResult(e.message);
    });
  }

  private loadGifts(): void {
    const sender: TdObject = { '@type': 'messageSenderUser' };
    sender['user_id'] = this.userId;
    const req: TdRequest = { '@type': 'getReceivedGifts' };
    req['business_connection_id'] = '';
    req['owner_id'] = sender;
    req['collection_id'] = 0;
    req['exclude_unsaved'] = false;
    req['exclude_saved'] = false;
    req['exclude_unlimited'] = false;
    req['exclude_upgradable'] = false;
    req['exclude_non_upgradable'] = false;
    req['exclude_upgraded'] = false;
    req['sort_by_price'] = false;
    req['offset'] = '';
    req['limit'] = 30;
    this.send(req, 'getReceivedGifts', (res: TdObject) => {
      const arr = (res['gifts'] as TdObject[] | undefined) ?? [];
      logI(`ProfileStore: gifts total=${(res['total_count'] as number | undefined) ?? 0} page=${arr.length}`);
      for (const rg of arr) {
        const rid = (rg['received_gift_id'] as string | undefined) ?? '';
        const sent = rg['gift'] as TdObject | undefined;
        const st = sent !== undefined ? ((sent['@type'] as string | undefined) ?? '') : '';
        if (st !== 'sentGiftRegular') {
          continue; // upgraded gifts carry a different model; keep it simple
        }
        const gift = sent!['gift'] as TdObject | undefined;
        const sticker = gift !== undefined ? (gift['sticker'] as TdObject | undefined) : undefined;
        // Gift stickers are usually TGS (Lottie) which Image can't render —
        // prefer the raster thumbnail; fall back to the sticker file only for WEBP.
        let fileId = 0;
        if (sticker !== undefined) {
          const thumb = sticker['thumbnail'] as TdObject | undefined;
          const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
          fileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
          if (fileId === 0) {
            const fmt = sticker['format'] as TdObject | undefined;
            if (fmt !== undefined && fmt['@type'] === 'stickerFormatWebp') {
              const file = sticker['sticker'] as TdObject | undefined;
              fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
            }
          }
        }
        const item: GiftItem = { id: rid, stickerPath: '' };
        this.gifts = [...this.gifts, item];
        this.download(fileId, (p: string) => {
          this.gifts = this.gifts.map((x: GiftItem): GiftItem => x.id === rid
            ? { id: x.id, stickerPath: p } : x);
        });
      }
      this.notify();
    });
  }
}
