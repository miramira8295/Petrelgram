import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { MemberRole, memberRoleOf, memberRoleRank } from '../util/memberRole';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatMemberCount } from '../util/formatMemberCount';
import { formatPreview } from '../util/formatPreview';
import { formatFileSize } from '../util/formatFileSize';
import { formatTime } from '../util/formatTime';
import { plural, str } from '../util/strings';
import { logE } from '../util/log';

type Listener = () => void;

const DL_PRIORITY: number = 1;
const MEMBER_PAGE: number = 30;
const CONTENT_PAGE: number = 36;
const GIFT_SCAN_PAGE: number = 60;
const MAX_GIFT_AUTO_PAGES: number = 6;

export const PROFILE_TAB_MEMBERS: string = 'members';
export const PROFILE_TAB_MEDIA: string = 'media';
export const PROFILE_TAB_FILES: string = 'files';
export const PROFILE_TAB_LINKS: string = 'links';
export const PROFILE_TAB_MUSIC: string = 'music';
export const PROFILE_TAB_POLLS: string = 'polls';
export const PROFILE_TAB_VOICE: string = 'voice';
export const PROFILE_TAB_VIDEO_NOTES: string = 'videoNotes';
export const PROFILE_TAB_GIFS: string = 'gifs';
export const PROFILE_TAB_GIFTS: string = 'gifts';

export interface MemberItem {
  userId: number;
  name: string;
  initials: string;
  avatarPath: string;
  status: string;
  // 身份标签：'' / 'creator' / 'admin'，以及可选的自定义头衔。见 util/memberRole。
  role: string;
  roleTitle: string;
  // 群成员标签（chatMember.tag）。TDLib 语义：普通成员的标签，或管理员的
  // 头衔——二合一字段，直接可显示。
  tag: string;
}

export interface ProfileContentItem {
  messageId: number;
  date: number;
  contentType: string;
  title: string;
  preview: string;
  meta: string;
  thumbPath: string;
  isVideo: boolean;
  duration: string;
}

function durationLabel(totalSeconds: number): string {
  const seconds = Math.max(0, totalSeconds);
  const minutes = Math.floor(seconds / 60);
  const remain = seconds % 60;
  return `${minutes}:${remain < 10 ? '0' : ''}${remain}`;
}

function fileSize(file: TdObject | undefined): number {
  if (file === undefined) {
    return 0;
  }
  return ((file['size'] as number | undefined) ?? 0) ||
    ((file['expected_size'] as number | undefined) ?? 0);
}

function formattedText(value: TdObject | undefined): string {
  return value !== undefined ? ((value['text'] as string | undefined) ?? '') : '';
}

function isGiftMessage(type: string): boolean {
  return type === 'messageGiftedPremium' || type === 'messageGiftedStars' ||
    type === 'messageGiftedTon' || type === 'messagePremiumGiftCode' ||
    type === 'messageGift' || type === 'messageUpgradedGift';
}

// Data assembly for the group/channel detail page (ChatProfilePage) — mirrors
// ProfileStore's subscribe/notify + download patterns.
export class ChatProfileStore {
  loadState: string = 'loading'; // loading | ready | error
  errorText: string = '';
  title: string = '';
  initials: string = '?';
  avatarPath: string = '';
  avatarAnimPath: string = ''; // animated chat photo (MPEG4), '' if none
  subtitle: string = '';      // "N 位成员" / "N 位订阅者"
  description: string = '';
  username: string = '';
  isChannel: boolean = false;
  isMuted: boolean = false;
  canManageVideoChats: boolean = false;
  canManageChat: boolean = false; // creator or admin with usable admin rights
  // 自己在这个群里的身份与逐项权限。成员长按菜单按这几项决定出哪些条目——
  // canManageChat 是"有任意一项管理权限"，用它一刀切会给只会封禁的管理员
  // 显示提权入口，点了必然失败。
  isCreator: boolean = false;
  canPromoteMembers: boolean = false;
  canRestrictMembers: boolean = false;
  canDeleteMessages: boolean = false;
  canManageTags: boolean = false;
  // 自己的用户 id。菜单要靠它认出"这一行就是我"，0 表示 getMe 还没回来。
  selfUserId: number = 0;
  liveGroupCallId: number = 0;
  membershipState: string = 'checking'; // checking | writable | joinable | blocked
  joinByRequest: boolean = false;
  members: MemberItem[] = [];
  membersState: string = 'loading'; // loading | ready | restricted | error
  contentTab: string = PROFILE_TAB_MEMBERS;
  contentItems: ProfileContentItem[] = [];
  contentState: string = 'idle'; // idle | loading | ready | error
  contentErrorText: string = '';
  contentHasMore: boolean = false;
  contentPaging: boolean = false;
  contentPagingError: boolean = false;
  contentTotalCount: number = 0;
  availableTabs: string[] = [];
  tabsState: string = 'loading'; // loading | ready

  private client: TdClient;
  private chatId: number;
  private supergroupId: number = 0;
  private basicGroupId: number = 0;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private fileApply: Map<number, (path: string) => void> = new Map();
  private contentSeq: number = 0;
  private contentNextMessageId: number = 0;
  private tabProbeSeq: number = 0;
  private tabProbePending: number = 0;
  private tabAvailability: Map<string, boolean> = new Map<string, boolean>();
  private membersAvailable: boolean = false;

  constructor(client: TdClient, chatId: number) {
    this.client = client;
    this.chatId = chatId;
  }

  subscribe(l: Listener): () => void {
    this.listeners = [...this.listeners, l];
    l();
    return (): void => { this.listeners = this.listeners.filter((x: Listener) => x !== l); };
  }

  open(): void {
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => {
      const f = u['file'] as TdObject | undefined;
      if (f !== undefined) {
        this.applyFile(f);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateChatNotificationSettings', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.applyNotificationSettings(u['notification_settings'] as TdObject | undefined);
        this.notify();
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateChatVideoChat', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.applyVideoChat(u['video_chat'] as TdObject | undefined);
        this.notify();
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateSupergroup', (u: TdObject) => {
      const supergroup = u['supergroup'] as TdObject | undefined;
      if (supergroup !== undefined &&
        ((supergroup['id'] as number | undefined) ?? 0) === this.supergroupId) {
        this.applySupergroup(supergroup);
        this.notify();
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateBasicGroup', (u: TdObject) => {
      const basicGroup = u['basic_group'] as TdObject | undefined;
      if (basicGroup !== undefined &&
        ((basicGroup['id'] as number | undefined) ?? 0) === this.basicGroupId) {
        this.applyMemberStatus(basicGroup['status'] as TdObject | undefined);
        this.notify();
      }
    }));
    this.loadMe();
    this.loadChat();
  }

  // 自己的用户 id。菜单要用它把"我自己"这一行排除掉，拿不到就当 0——菜单会
  // 少排除一行，但不会误操作（对自己提权/踢自己会被 TDLib 拒）。
  private loadMe(): void {
    this.client.send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
      this.selfUserId = (me['id'] as number | undefined) ?? 0;
      this.notify();
    }).catch((e: TdError): void => {
      logE(`ChatProfileStore.getMe failed: ${e.message}`);
    });
  }

  close(): void {
    this.contentSeq++;
    this.tabProbeSeq++;
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.listeners = [];
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }

  private send(req: TdRequest, tag: string, onOk: (res: TdObject) => void): void {
    this.client.send(req).then(onOk).catch((e: TdError) => {
      logE(`ChatProfileStore.${tag} failed: ${e.message}`);
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

  private rebuildAvailableTabs(): void {
    const order: string[] = [
      PROFILE_TAB_MEMBERS, PROFILE_TAB_MEDIA, PROFILE_TAB_FILES, PROFILE_TAB_LINKS,
      PROFILE_TAB_MUSIC, PROFILE_TAB_POLLS, PROFILE_TAB_VOICE,
      PROFILE_TAB_VIDEO_NOTES, PROFILE_TAB_GIFS, PROFILE_TAB_GIFTS
    ];
    const next: string[] = [];
    for (const tab of order) {
      const available = tab === PROFILE_TAB_MEMBERS
        ? this.membersAvailable : (this.tabAvailability.get(tab) ?? false);
      if (available) {
        next.push(tab);
      }
    }
    this.availableTabs = next;
  }

  private probeContentTabs(): void {
    const tabs: string[] = [
      PROFILE_TAB_MEDIA, PROFILE_TAB_FILES, PROFILE_TAB_LINKS, PROFILE_TAB_MUSIC,
      PROFILE_TAB_POLLS, PROFILE_TAB_VOICE, PROFILE_TAB_VIDEO_NOTES, PROFILE_TAB_GIFS
    ];
    const seq = ++this.tabProbeSeq;
    this.tabsState = 'loading';
    // Native-count tabs decide when the strip may appear. Gift probing scans
    // message history and can take longer, so a gift result may append later
    // without holding every ordinary category behind a spinner.
    this.tabProbePending = tabs.length;
    this.tabAvailability.clear();
    this.rebuildAvailableTabs();
    this.notify();
    for (const tab of tabs) {
      const req: TdRequest = { '@type': 'getChatMessageCount' };
      req['chat_id'] = this.chatId;
      req['filter'] = { '@type': this.contentFilter(tab) } as TdObject;
      req['return_local'] = false;
      this.client.send(req).then((res: TdObject): void => {
        if (seq !== this.tabProbeSeq) {
          return;
        }
        const count = (res['count'] as number | undefined) ?? 0;
        this.finishTabProbe(tab, count > 0);
      }).catch((e: TdError): void => {
        if (seq !== this.tabProbeSeq) {
          return;
        }
        logE(`ChatProfileStore.getChatMessageCount(${tab}) failed: ${e.message}`);
        // A failed capability probe must not create a dead tab. It stays hidden
        // until a future page refresh can establish that the category exists.
        this.finishTabProbe(tab, false);
      });
    }
    this.probeGiftPage(seq, 0, 0);
  }

  private finishTabProbe(tab: string, available: boolean): void {
    this.tabAvailability.set(tab, available);
    this.tabProbePending = Math.max(0, this.tabProbePending - 1);
    if (this.tabProbePending === 0) {
      this.tabsState = 'ready';
    }
    this.rebuildAvailableTabs();
    this.notify();
  }

  private probeGiftPage(seq: number, fromMessageId: number, scannedPages: number): void {
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['from_message_id'] = fromMessageId;
    req['offset'] = 0;
    req['limit'] = GIFT_SCAN_PAGE;
    this.client.send(req).then((res: TdObject): void => {
      if (seq !== this.tabProbeSeq) {
        return;
      }
      const raw = (res['messages'] as TdObject[] | undefined) ?? [];
      for (const message of raw) {
        const content = message['content'] as TdObject | undefined;
        const type = (content?.['@type'] as string | undefined) ?? '';
        if (isGiftMessage(type)) {
          this.finishTabProbe(PROFILE_TAB_GIFTS, true);
          return;
        }
      }
      const next = raw.length >= GIFT_SCAN_PAGE && raw.length > 0
        ? ((raw[raw.length - 1]['id'] as number | undefined) ?? 0) : 0;
      if (next > 0 && next !== fromMessageId && scannedPages + 1 < MAX_GIFT_AUTO_PAGES) {
        this.probeGiftPage(seq, next, scannedPages + 1);
        return;
      }
      this.finishTabProbe(PROFILE_TAB_GIFTS, false);
    }).catch((e: TdError): void => {
      if (seq !== this.tabProbeSeq) {
        return;
      }
      logE(`ChatProfileStore.probeGifts failed: ${e.message}`);
      this.finishTabProbe(PROFILE_TAB_GIFTS, false);
    });
  }

  // Chat detail tabs are backed by TDLib's native per-chat message filters.
  // Gifts are the only exception: this TDLib build has no gift filter, so that
  // category scans ordinary message pages and keeps just gift message types.
  selectContentTab(tab: string): void {
    if (tab === this.contentTab &&
      (tab === PROFILE_TAB_MEMBERS || this.contentState !== 'idle')) {
      return;
    }
    this.contentSeq++;
    this.contentTab = tab;
    this.contentItems = [];
    this.contentErrorText = '';
    this.contentHasMore = false;
    this.contentPaging = false;
    this.contentPagingError = false;
    this.contentTotalCount = 0;
    this.contentNextMessageId = 0;
    if (tab === PROFILE_TAB_MEMBERS) {
      this.contentState = 'idle';
      this.notify();
      return;
    }
    this.contentState = 'loading';
    this.notify();
    this.fetchContentPage(0, true, 0);
  }

  retryContent(): void {
    if (this.contentTab === PROFILE_TAB_MEMBERS || this.contentState === 'loading') {
      return;
    }
    this.contentSeq++;
    this.contentItems = [];
    this.contentState = 'loading';
    this.contentErrorText = '';
    this.contentHasMore = false;
    this.contentPaging = false;
    this.contentPagingError = false;
    this.contentNextMessageId = 0;
    this.notify();
    this.fetchContentPage(0, true, 0);
  }

  loadMoreContent(): void {
    if (this.contentTab === PROFILE_TAB_MEMBERS || this.contentState !== 'ready' ||
      this.contentPaging || !this.contentHasMore || this.contentNextMessageId <= 0) {
      return;
    }
    this.contentPaging = true;
    this.contentPagingError = false;
    this.notify();
    this.fetchContentPage(this.contentNextMessageId, false, 0);
  }

  private contentFilter(tab: string): string {
    if (tab === PROFILE_TAB_MEDIA) {
      return 'searchMessagesFilterPhotoAndVideo';
    }
    if (tab === PROFILE_TAB_FILES) {
      return 'searchMessagesFilterDocument';
    }
    if (tab === PROFILE_TAB_LINKS) {
      return 'searchMessagesFilterUrl';
    }
    if (tab === PROFILE_TAB_MUSIC) {
      return 'searchMessagesFilterAudio';
    }
    if (tab === PROFILE_TAB_POLLS) {
      return 'searchMessagesFilterPoll';
    }
    if (tab === PROFILE_TAB_VOICE) {
      return 'searchMessagesFilterVoiceNote';
    }
    if (tab === PROFILE_TAB_VIDEO_NOTES) {
      return 'searchMessagesFilterVideoNote';
    }
    if (tab === PROFILE_TAB_GIFS) {
      return 'searchMessagesFilterAnimation';
    }
    return '';
  }

  private mergeContent(fresh: ProfileContentItem[], replace: boolean): void {
    const merged: ProfileContentItem[] = replace ? [] : [...this.contentItems];
    const seen: Set<number> = new Set<number>();
    for (const item of merged) {
      seen.add(item.messageId);
    }
    for (const item of fresh) {
      if (!seen.has(item.messageId)) {
        seen.add(item.messageId);
        merged.push(item);
      }
    }
    this.contentItems = merged;
  }

  private fetchContentPage(fromMessageId: number, replace: boolean, scannedPages: number): void {
    const seq = this.contentSeq;
    const tab = this.contentTab;
    const giftScan = tab === PROFILE_TAB_GIFTS;
    const limit = giftScan ? GIFT_SCAN_PAGE : CONTENT_PAGE;
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['from_message_id'] = fromMessageId;
    req['offset'] = 0;
    req['limit'] = limit;
    const filter = this.contentFilter(tab);
    if (filter !== '') {
      req['filter'] = { '@type': filter } as TdObject;
    }
    this.client.send(req).then((res: TdObject): void => {
      if (seq !== this.contentSeq || tab !== this.contentTab) {
        return;
      }
      const raw = (res['messages'] as TdObject[] | undefined) ?? [];
      const fresh: ProfileContentItem[] = [];
      for (const message of raw) {
        const content = message['content'] as TdObject | undefined;
        const type = (content?.['@type'] as string | undefined) ?? '';
        if (giftScan && !isGiftMessage(type)) {
          continue;
        }
        const item = this.parseContentItem(message);
        if (item !== null) {
          fresh.push(item);
        }
      }
      this.mergeContent(fresh, replace);
      const lastId = raw.length > 0
        ? ((raw[raw.length - 1]['id'] as number | undefined) ?? 0) : 0;
      const responseNext = (res['next_from_message_id'] as number | undefined) ?? 0;
      const next = responseNext > 0 ? responseNext
        : (raw.length >= limit ? lastId : 0);
      this.contentNextMessageId = next !== fromMessageId ? next : 0;
      this.contentHasMore = this.contentNextMessageId > 0;
      this.contentTotalCount = giftScan
        ? this.contentItems.length
        : ((res['total_count'] as number | undefined) ?? this.contentItems.length);
      this.contentErrorText = '';
      this.contentPagingError = false;

      const shouldKeepScanning = giftScan && this.contentHasMore &&
        this.contentItems.length < 12 && scannedPages + 1 < MAX_GIFT_AUTO_PAGES;
      if (shouldKeepScanning) {
        this.contentState = this.contentItems.length === 0 ? 'loading' : 'ready';
        this.contentPaging = this.contentItems.length > 0;
        this.notify();
        this.fetchContentPage(this.contentNextMessageId, false, scannedPages + 1);
        return;
      }
      this.contentState = 'ready';
      this.contentPaging = false;
      this.notify();
    }).catch((e: TdError): void => {
      if (seq !== this.contentSeq || tab !== this.contentTab) {
        return;
      }
      logE(`ChatProfileStore.searchChatMessages(${tab}) failed: ${e.message}`);
      this.contentPaging = false;
      if (replace || this.contentItems.length === 0) {
        this.contentState = 'error';
        this.contentErrorText = str('cps_category_failed');
        this.contentHasMore = false;
      } else {
        this.contentState = 'ready';
        this.contentPagingError = true;
      }
      this.notify();
    });
  }

  private parseContentItem(message: TdObject): ProfileContentItem | null {
    const messageId = (message['id'] as number | undefined) ?? 0;
    const content = message['content'] as TdObject | undefined;
    if (messageId <= 0 || content === undefined) {
      return null;
    }
    const type = (content['@type'] as string | undefined) ?? '';
    const date = (message['date'] as number | undefined) ?? 0;
    const preview = formatPreview(message);
    let title = preview !== '' ? preview : str('cps_messages');
    let detail = '';
    let size = 0;
    let duration = 0;
    let thumbnailId = 0;
    let isVideo = false;

    if (type === 'messagePhoto') {
      title = str('storage_photo');
      detail = formattedText(content['caption'] as TdObject | undefined);
      const photo = content['photo'] as TdObject | undefined;
      const sizes = (photo?.['sizes'] as TdObject[] | undefined) ?? [];
      let picked: TdObject | undefined = undefined;
      for (const candidate of sizes) {
        if ((candidate['type'] as string | undefined) === 'm') {
          picked = candidate;
        }
      }
      if (picked === undefined && sizes.length > 0) {
        picked = sizes[Math.max(0, sizes.length - 2)];
      }
      const file = picked?.['photo'] as TdObject | undefined;
      thumbnailId = (file?.['id'] as number | undefined) ?? 0;
    } else if (type === 'messageVideo') {
      title = str('storage_video');
      detail = formattedText(content['caption'] as TdObject | undefined);
      const video = content['video'] as TdObject | undefined;
      const thumb = video?.['thumbnail'] as TdObject | undefined;
      const thumbFile = thumb?.['file'] as TdObject | undefined;
      const videoFile = video?.['video'] as TdObject | undefined;
      thumbnailId = (thumbFile?.['id'] as number | undefined) ?? 0;
      duration = (video?.['duration'] as number | undefined) ?? 0;
      size = fileSize(videoFile);
      isVideo = true;
    } else if (type === 'messageDocument') {
      const document = content['document'] as TdObject | undefined;
      const file = document?.['document'] as TdObject | undefined;
      title = (document?.['file_name'] as string | undefined) ?? str('storage_file');
      detail = formattedText(content['caption'] as TdObject | undefined);
      size = fileSize(file);
    } else if (type === 'messageAudio') {
      const audio = content['audio'] as TdObject | undefined;
      const file = audio?.['audio'] as TdObject | undefined;
      const audioTitle = (audio?.['title'] as string | undefined) ?? '';
      const fileName = (audio?.['file_name'] as string | undefined) ?? '';
      title = audioTitle !== '' ? audioTitle : (fileName !== '' ? fileName : str('storage_audio'));
      detail = (audio?.['performer'] as string | undefined) ?? '';
      duration = (audio?.['duration'] as number | undefined) ?? 0;
      size = fileSize(file);
      const cover = audio?.['album_cover_thumbnail'] as TdObject | undefined;
      const coverFile = cover?.['file'] as TdObject | undefined;
      thumbnailId = (coverFile?.['id'] as number | undefined) ?? 0;
    } else if (type === 'messageVoiceNote') {
      const voice = content['voice_note'] as TdObject | undefined;
      title = str('ns_voice_message');
      detail = formattedText(content['caption'] as TdObject | undefined);
      duration = (voice?.['duration'] as number | undefined) ?? 0;
      size = fileSize(voice?.['voice'] as TdObject | undefined);
    } else if (type === 'messageVideoNote') {
      const note = content['video_note'] as TdObject | undefined;
      title = str('cp_video_message');
      duration = (note?.['duration'] as number | undefined) ?? 0;
      size = fileSize(note?.['video'] as TdObject | undefined);
      const thumb = note?.['thumbnail'] as TdObject | undefined;
      const thumbFile = thumb?.['file'] as TdObject | undefined;
      thumbnailId = (thumbFile?.['id'] as number | undefined) ?? 0;
      isVideo = true;
    } else if (type === 'messageAnimation') {
      const animation = content['animation'] as TdObject | undefined;
      title = (animation?.['file_name'] as string | undefined) ?? str('cps_gifs');
      if (title === '') {
        title = str('cps_gifs');
      }
      detail = formattedText(content['caption'] as TdObject | undefined);
      duration = (animation?.['duration'] as number | undefined) ?? 0;
      size = fileSize(animation?.['animation'] as TdObject | undefined);
      const thumb = animation?.['thumbnail'] as TdObject | undefined;
      const thumbFile = thumb?.['file'] as TdObject | undefined;
      thumbnailId = (thumbFile?.['id'] as number | undefined) ?? 0;
      isVideo = true;
    } else if (type === 'messagePoll') {
      const poll = content['poll'] as TdObject | undefined;
      const question = poll?.['question'] as TdObject | undefined;
      title = formattedText(question);
      if (title === '') {
        title = str('poll_word');
      }
      const voters = (poll?.['total_voter_count'] as number | undefined) ?? 0;
      detail = voters > 0 ? plural('poll_voters', voters, voters) : '';
    } else if (this.contentTab === PROFILE_TAB_LINKS) {
      title = str('cps_links');
      detail = preview;
    } else if (isGiftMessage(type)) {
      title = preview !== '' ? preview : str('gift_regular_title');
      const directSticker = content['sticker'] as TdObject | undefined;
      const gift = content['gift'] as TdObject | undefined;
      const model = gift?.['model'] as TdObject | undefined;
      const sticker = directSticker ?? (gift?.['sticker'] as TdObject | undefined)
        ?? (model?.['sticker'] as TdObject | undefined);
      const thumb = sticker?.['thumbnail'] as TdObject | undefined;
      const thumbFile = thumb?.['file'] as TdObject | undefined;
      thumbnailId = (thumbFile?.['id'] as number | undefined) ?? 0;
    }

    const metaParts: string[] = [];
    if (duration > 0) {
      metaParts.push(durationLabel(duration));
    }
    if (size > 0) {
      metaParts.push(formatFileSize(size));
    }
    const dateLabel = formatTime(date, Math.floor(Date.now() / 1000));
    if (dateLabel !== '') {
      metaParts.push(dateLabel);
    }
    const item: ProfileContentItem = {
      messageId,
      date,
      contentType: type,
      title,
      preview: detail !== '' && detail !== title ? detail : '',
      meta: metaParts.join(' · '),
      thumbPath: '',
      isVideo,
      duration: duration > 0 ? durationLabel(duration) : ''
    };
    if (thumbnailId > 0) {
      this.download(thumbnailId, (path: string): void => {
        this.contentItems = this.contentItems.map((existing: ProfileContentItem): ProfileContentItem =>
          existing.messageId === messageId ? {
            messageId: existing.messageId,
            date: existing.date,
            contentType: existing.contentType,
            title: existing.title,
            preview: existing.preview,
            meta: existing.meta,
            thumbPath: path,
            isVideo: existing.isVideo,
            duration: existing.duration
          } : existing);
      });
    }
    return item;
  }

  private loadChat(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    this.client.send(req).then((chat: TdObject): void => {
      this.title = (chat['title'] as string | undefined) ?? '';
      this.initials = this.title.length > 0 ? this.title.substring(0, 1).toUpperCase() : '?';
      const photo = chat['photo'] as TdObject | undefined;
      const big = photo !== undefined ? (photo['big'] as TdObject | undefined) : undefined;
      this.download(big !== undefined ? ((big['id'] as number | undefined) ?? 0) : 0,
        (p: string) => { this.avatarPath = p; });
      this.applyNotificationSettings(chat['notification_settings'] as TdObject | undefined);
      this.applyVideoChat(chat['video_chat'] as TdObject | undefined);
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      if (typeName === 'chatTypeSupergroup') {
        this.supergroupId = ((type as TdObject)['supergroup_id'] as number | undefined) ?? 0;
        this.loadSupergroup();
      } else if (typeName === 'chatTypeBasicGroup') {
        this.basicGroupId = ((type as TdObject)['basic_group_id'] as number | undefined) ?? 0;
        this.loadBasicGroup();
      }
      this.probeContentTabs();
      this.loadState = 'ready';
      this.errorText = '';
      this.notify();
    }).catch((e: TdError): void => {
      logE(`ChatProfileStore.getChat failed: ${e.message}`);
      this.loadState = 'error';
      this.errorText = str('cps_details_failed');
      this.notify();
    });
  }

  // Muted = explicit non-default settings with a positive mute window.
  private applyNotificationSettings(ns: TdObject | undefined): void {
    if (ns === undefined) {
      return;
    }
    const useDefault = (ns['use_default_mute_for'] as boolean | undefined) ?? true;
    const muteFor = (ns['mute_for'] as number | undefined) ?? 0;
    this.isMuted = !useDefault && muteFor > 0;
  }

  private applyVideoChat(videoChat: TdObject | undefined): void {
    this.liveGroupCallId = videoChat !== undefined
      ? ((videoChat['group_call_id'] as number | undefined) ?? 0) : 0;
  }

  private applyMemberStatus(status: TdObject | undefined): void {
    const type = (status?.['@type'] as string | undefined) ?? '';
    if (type === 'chatMemberStatusLeft') {
      this.membershipState = 'joinable';
    } else if (type === 'chatMemberStatusRestricted') {
      const isMember = (status?.['is_member'] as boolean | undefined) ?? false;
      this.membershipState = isMember ? 'writable' : 'joinable';
    } else if (type === 'chatMemberStatusBanned') {
      this.membershipState = 'blocked';
    } else if (type !== '') {
      this.membershipState = 'writable';
    }
    if (type === 'chatMemberStatusCreator') {
      this.canManageVideoChats = true;
      this.canManageChat = true;
      this.isCreator = true;
      this.canPromoteMembers = true;
      this.canRestrictMembers = true;
      this.canDeleteMessages = true;
      this.canManageTags = true;
      return;
    }
    if (type === 'chatMemberStatusAdministrator') {
      const rights = status?.['rights'] as TdObject | undefined;
      const flag = (key: string): boolean =>
        (rights?.[key] as boolean | undefined) ?? false;
      this.canManageVideoChats = flag('can_manage_video_chats');
      this.isCreator = false;
      this.canPromoteMembers = flag('can_promote_members');
      this.canRestrictMembers = flag('can_restrict_members');
      this.canDeleteMessages = flag('can_delete_messages');
      this.canManageTags = flag('can_manage_tags');
      // Any of these rights makes at least part of the admin page usable.
      this.canManageChat = flag('can_manage_chat') || flag('can_change_info') ||
        this.canRestrictMembers || flag('can_invite_users') || this.canPromoteMembers;
      return;
    }
    this.canManageVideoChats = false;
    this.canManageChat = false;
    this.isCreator = false;
    this.canManageTags = false;
    this.canPromoteMembers = false;
    this.canRestrictMembers = false;
    this.canDeleteMessages = false;
  }

  private applySupergroup(supergroup: TdObject): void {
    this.isChannel = (supergroup['is_channel'] as boolean | undefined) ?? false;
    this.applyMemberStatus(supergroup['status'] as TdObject | undefined);
    const usernames = supergroup['usernames'] as TdObject | undefined;
    const editable = usernames !== undefined
      ? ((usernames['editable_username'] as string | undefined) ?? '') : '';
    const active = usernames !== undefined
      ? (usernames['active_usernames'] as string[] | undefined) : undefined;
    this.username = editable !== ''
      ? editable : (active !== undefined && active.length > 0 ? active[0] : '');
    const count = (supergroup['member_count'] as number | undefined) ?? 0;
    if (count > 0) {
      this.subtitle = str('subtitle_member_count', formatMemberCount(count), this.isChannel ? str('subscribers_word') : str('members_word'));
    }
  }

  private loadSupergroup(): void {
    const req: TdRequest = { '@type': 'getSupergroup' };
    req['supergroup_id'] = this.supergroupId;
    this.send(req, 'getSupergroup', (sg: TdObject) => {
      this.applySupergroup(sg);
      this.notify();

      const full: TdRequest = { '@type': 'getSupergroupFullInfo' };
      full['supergroup_id'] = this.supergroupId;
      this.send(full, 'getSupergroupFullInfo', (fi: TdObject) => {
        this.description = (fi['description'] as string | undefined) ?? '';
        this.joinByRequest = (fi['join_by_request'] as boolean | undefined) ?? false;
        this.parsePhotoAnimation(fi['photo'] as TdObject | undefined);
        const memberCount = (fi['member_count'] as number | undefined) ?? 0;
        if (memberCount > 0) {
          this.subtitle = str('subtitle_member_count', formatMemberCount(memberCount), this.isChannel ? str('subscribers_word') : str('members_word'));
        }
        this.notify();
        const canGetMembers = (fi['can_get_members'] as boolean | undefined) ?? false;
        this.membersAvailable = canGetMembers && memberCount > 0;
        this.rebuildAvailableTabs();
        if (canGetMembers) {
          this.loadSupergroupMembers();
        } else {
          // Ordinary channel subscribers aren't exposed to every account.
          // Keep that distinct from a network error or a genuinely empty list.
          this.membersState = this.isChannel ? 'restricted' : 'ready';
          this.notify();
        }
      });
    });
  }

  // Full-info photo is a chatPhoto; its optional `animation` is a small MPEG4
  // loop (the chat's chatPhotoInfo only carries a has_animation flag).
  private parsePhotoAnimation(photo: TdObject | undefined): void {
    const anim = photo !== undefined ? (photo['animation'] as TdObject | undefined) : undefined;
    const file = anim !== undefined ? (anim['file'] as TdObject | undefined) : undefined;
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    this.download(fileId, (p: string) => { this.avatarAnimPath = p; });
  }

  private memberOffset: number = 0;
  private membersPending: boolean = false;
  private memberIds: Set<number> = new Set<number>();
  hasMoreMembers: boolean = false;

  private loadSupergroupMembers(): void {
    this.memberOffset = 0;
    this.members = [];
    this.memberIds.clear();
    this.membersState = 'loading';
    this.fetchMembersPage();
  }

  // 成员被移出后重拉整份名单。TDLib 不会为"某人被移出"单独推更新到这个
  // 列表，所以只能重取；分页游标也必须一起归零，否则新名单会接在旧偏移后面。
  reloadMembers(): void {
    if (this.supergroupId !== 0) {
      this.loadSupergroupMembers();
      return;
    }
    // 基础群的成员挂在 basicGroupFullInfo 上，没有单独的分页接口，也收不到
    // "某人被移出"的推送，只能整份重取；去重集合要一起清，否则新名单会被
    // 当成"已经有了"而整份丢掉。
    if (this.basicGroupId !== 0) {
      this.members = [];
      this.memberIds.clear();
      this.membersState = 'loading';
      this.notify();
      this.loadBasicGroup();
    }
  }

  // Scroll-driven: the profile page calls this near the list's end.
  loadMoreMembers(): void {
    if (!this.hasMoreMembers || this.membersPending || this.supergroupId === 0) {
      return;
    }
    this.fetchMembersPage();
  }

  private fetchMembersPage(): void {
    this.membersPending = true;
    const req: TdRequest = { '@type': 'getSupergroupMembers' };
    req['supergroup_id'] = this.supergroupId;
    req['offset'] = this.memberOffset;
    req['limit'] = MEMBER_PAGE;
    this.client.send(req).then((res: TdObject): void => {
      const raw = (res['members'] as TdObject[] | undefined) ?? [];
      this.memberOffset += raw.length;
      this.hasMoreMembers = raw.length === MEMBER_PAGE;
      this.membersPending = false;
      this.membersState = 'ready';
      this.notify();
      this.resolveMembers(raw);
    }).catch((e: TdError): void => {
      logE(`ChatProfileStore.getSupergroupMembers failed: ${e.message}`);
      this.membersPending = false;
      this.hasMoreMembers = false;
      this.membersState = this.members.length > 0 ? 'ready' : 'error';
      this.notify();
    });
  }

  private loadBasicGroup(): void {
    const group: TdRequest = { '@type': 'getBasicGroup' };
    group['basic_group_id'] = this.basicGroupId;
    this.send(group, 'getBasicGroup', (basicGroup: TdObject) => {
      this.applyMemberStatus(basicGroup['status'] as TdObject | undefined);
      this.notify();
    });

    const req: TdRequest = { '@type': 'getBasicGroupFullInfo' };
    req['basic_group_id'] = this.basicGroupId;
    this.send(req, 'getBasicGroupFullInfo', (fi: TdObject) => {
      this.description = (fi['description'] as string | undefined) ?? '';
      this.parsePhotoAnimation(fi['photo'] as TdObject | undefined);
      const members = (fi['members'] as TdObject[] | undefined) ?? [];
      this.membersAvailable = members.length > 0;
      this.rebuildAvailableTabs();
      if (members.length > 0) {
        this.subtitle = str('subtitle_members_only', formatMemberCount(members.length));
      }
      this.membersState = 'ready';
      this.notify();
      this.resolveMembers(members);
    });
  }

  // chatMember[] → MemberItem[] via getUser (name/status/avatar) per member.
  private resolveMembers(raw: TdObject[]): void {
    for (const m of raw) {
      const sender = m['member_id'] as TdObject | undefined;
      if (sender === undefined || (sender['@type'] as string | undefined) !== 'messageSenderUser') {
        continue;
      }
      const uid = (sender['user_id'] as number | undefined) ?? 0;
      if (uid <= 0) {
        continue;
      }
      // 身份就在这条 chatMember 里，不用为它再发一次请求。
      const role: MemberRole = memberRoleOf(m['status'] as TdObject | undefined);
      const memberTag: string = ((m['tag'] as string | undefined) ?? '').trim();
      if (this.memberIds.has(uid)) {
        continue;
      }
      this.memberIds.add(uid);
      const req: TdRequest = { '@type': 'getUser' };
      req['user_id'] = uid;
      this.send(req, 'getUser', (user: TdObject) => {
        const first = (user['first_name'] as string | undefined) ?? '';
        const last = (user['last_name'] as string | undefined) ?? '';
        const name = `${first} ${last}`.trim();
        if (name === '') {
          return;
        }
        const item: MemberItem = {
          userId: uid,
          name,
          initials: name.substring(0, 1).toUpperCase(),
          avatarPath: '',
          status: formatUserStatus(user['status'] as TdObject | undefined, Math.floor(Date.now() / 1000)),
          role: role.kind,
          roleTitle: role.title,
          tag: memberTag
        };
        // 创建者和管理员排在前面。稳定排序：同档之间保持 TDLib 给的顺序，
        // 否则每来一个成员整列都会重排一次。
        this.members = [...this.members, item].sort(
          (a: MemberItem, b: MemberItem): number =>
            memberRoleRank(a.role) - memberRoleRank(b.role));
        const photo = user['profile_photo'] as TdObject | undefined;
        const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
        this.download(small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0,
          (p: string) => {
            this.members = this.members.map((x: MemberItem): MemberItem =>
              x.userId === uid ? {
                userId: x.userId, name: x.name, initials: x.initials, avatarPath: p,
                status: x.status, role: x.role, roleTitle: x.roleTitle, tag: x.tag
              } : x);
          });
        this.notify();
      });
    }
  }
}
