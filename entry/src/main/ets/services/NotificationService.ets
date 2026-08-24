import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from '../store/ChatStore';
import { UserStore } from '../store/UserStore';
import { FileService } from './FileService';
import { CallSession, CallSnapshot } from './CallSession';
import { formatPreview } from '../util/formatPreview';
import { systemCallUi } from './SystemCallUi';
import {
  KEY_NOTIFY_PRIVATE, KEY_NOTIFY_GROUP, KEY_NOTIFY_CHANNEL
} from '../store/AppSettings';
import { str } from '../util/strings';
import { logE } from '../util/log';
import { scopeMuted, scopeOfTdType, setScopeMuted } from '../store/ScopeMuteStore';

// 来电通知固定 id（TDLib notification id 为正整数，取远离区间的常量）。
export const CALL_NOTIFICATION_ID: number = 999001;

export interface LocalNotice {
  id: number;      // TDLib notification id（来电为 CALL_NOTIFICATION_ID）
  groupId: number; // TDLib notification group id（来电为 0）
  chatId: number;
  title: string;
  text: string;
  isCall: boolean;
  avatarPath: string; // 会话头像本地路径（''=无，发布方回退默认图标）
}

export interface NotificationPublisher {
  publish(notice: LocalNotice): void;
  cancel(id: number): void;
  cancelAll(): void;
}

// 本地通知渲染层：消费 TDLib 内置通知管理器的事件（静音/例外/预览隐藏等
// 规则均由 TDLib 处理），把结果翻译成系统通知。前台时不打扰。
export class NotificationService {
  private client: TdClient;
  private chats: ChatStore;
  private publisher: NotificationPublisher;
  private isForeground: () => boolean;
  // 群/频道消息的发信人头像要经这两个：UserStore 给 file id，FileService 给
  // 本地路径。可选 —— 测试里不传，退回会话头像。
  private users: UserStore | null = null;
  private files: FileService | null = null;
  private unsubs: Array<() => void> = [];
  private unsubCall: (() => void) | null = null;
  private callNoticeShown: boolean = false;

  constructor(client: TdClient, chats: ChatStore, publisher: NotificationPublisher,
    isForeground: () => boolean) {
    this.client = client;
    this.chats = chats;
    this.publisher = publisher;
    this.isForeground = isForeground;
    this.unsubs.push(client.onUpdate('updateNotificationGroup',
      (u: TdObject) => this.onNotificationGroup(u)));
    // 通知发布统一由 updateNewMessage 驱动：TDLib 的通知组只在启动同步等
    // 特定时机产出，不能作为唯一来源。
    this.unsubs.push(client.onUpdate('updateNewMessage', (u: TdObject): void => {
      const message = u['message'] as TdObject | undefined;
      const chatId: number = message !== undefined
        ? ((message['chat_id'] as number | undefined) ?? 0) : 0;
      const outgoing: boolean = message !== undefined
        ? ((message['is_outgoing'] as boolean | undefined) ?? false) : false;
      this.considerFallbackNotice(message, chatId, outgoing);
    }));
    // 分类通知设置变更（通知设置页或其他设备修改）→ 刷新缓存。
    this.unsubs.push(client.onUpdate('updateScopeNotificationSettings',
      (u: TdObject): void => {
        const scope = u['scope'] as TdObject | undefined;
        const typeName: string = scope !== undefined
          ? ((scope['@type'] as string | undefined) ?? '') : '';
        const settings = u['notification_settings'] as TdObject | undefined;
        const muted: boolean = settings !== undefined
          ? (((settings['mute_for'] as number | undefined) ?? 0) > 0) : false;
        // 写进共享缓存，会话列表和资料页读的是同一份——本服务自己判断"要不要
        // 弹通知"用的也是它，两边不会再各算各的（issue #110）。
        const scopeKey: string = scopeOfTdType(typeName);
        if (scopeKey !== '') {
          setScopeMuted(scopeKey, muted);
        }
      }));
    // 会话级通知设置：记录它是否覆盖了分类默认。
    this.unsubs.push(client.onUpdate('updateChatNotificationSettings',
      (u: TdObject): void => {
        this.trackChatNotificationSettings(
          (u['chat_id'] as number | undefined) ?? 0,
          u['notification_settings'] as TdObject | undefined);
      }));
    this.unsubs.push(client.onUpdate('updateNewChat', (u: TdObject): void => {
      const chat = u['chat'] as TdObject | undefined;
      if (chat === undefined) {
        return;
      }
      this.trackChatNotificationSettings(
        (chat['id'] as number | undefined) ?? 0,
        chat['notification_settings'] as TdObject | undefined);
    }));
    // 会话读完（在本机或其他设备）→ 撤掉它已弹出的通知。TDLib 通知组的
    // removed_notification_ids 用的是它自己的 id，与我们发布的 id 无法映射，
    // 因此改用已读水位驱动撤销。
    this.unsubs.push(client.onUpdate('updateChatReadInbox', (u: TdObject): void => {
      const unread: number = (u['unread_count'] as number | undefined) ?? 0;
      if (unread > 0) {
        return;
      }
      const chatId: number = (u['chat_id'] as number | undefined) ?? 0;
      const shown = this.noticeIdsByChat.get(chatId);
      if (shown === undefined) {
        return;
      }
      this.noticeIdsByChat.delete(chatId);
      for (const id of shown) {
        this.publisher.cancel(id);
      }
    }));
  }

  // 启用 TDLib 通知管理器。必须在 td_init 完成（Auth Ready）后调用 ——
  // 构造时 td 还没初始化，setOption 会 "tdSend before tdInit" 失败，
  // 之后 TDLib 就不推 updateNotificationGroup。
  enable(): void {
    this.enableTdNotifications();
    this.refreshScopeMute();
  }

  // 群消息通知要显示发信人头像/名字，需要这两个来源。构造函数不带它们是为了
  // 不动既有测试装配 —— 不挂就是原来的行为（会话头像、无前缀）。
  attachSenderSources(users: UserStore, files: FileService): void {
    this.users = users;
    this.files = files;
  }

  attachCallSession(session: CallSession): void {
    this.unsubCall = session.subscribe((s: CallSnapshot): void => this.onCallSnapshot(s));
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    if (this.unsubCall !== null) {
      this.unsubCall();
      this.unsubCall = null;
    }
  }

  // TDLib 只有在这两个 option 非 0 时才会推 updateNotificationGroup。
  private enableTdNotifications(): void {
    this.setOption('notification_group_count_max', 5);
    this.setOption('notification_group_size_max', 10);
  }

  private setOption(name: string, value: number): void {
    const optionValue: TdObject = { '@type': 'optionValueInteger' };
    optionValue['value'] = `${value}`;
    const req: TdRequest = { '@type': 'setOption' };
    req['name'] = name;
    req['value'] = optionValue;
    this.client.send(req).catch((e: TdError): void => {
      logE(`NotificationService.setOption(${name}) failed: ${e.message}`);
    });
  }

  private onNotificationGroup(u: TdObject): void {
    const removed: number[] = (u['removed_notification_ids'] as number[] | undefined) ?? [];
    for (const id of removed) {
      this.publisher.cancel(id);
    }
    // 发布统一走 considerFallbackNotice（updateNewMessage 驱动）：本机 td
    // 的通知组只在特定时机产出，不能作为唯一来源；两条路径同时发布会重复。
  }

  private buildNotice(notification: TdObject, groupId: number,
    chatId: number): LocalNotice | null {
    const id: number = (notification['id'] as number | undefined) ?? 0;
    if (id <= 0) {
      return null;
    }
    const type = notification['type'] as TdObject | undefined;
    const typeName: string = type !== undefined
      ? ((type['@type'] as string | undefined) ?? '') : '';
    const entry = this.chats.entryOf(chatId);
    const title: string = entry !== undefined && entry.title !== '' ? entry.title : str('ns_new_message');
    if (typeName === 'notificationTypeNewMessage') {
      const message = type!['message'] as TdObject | undefined;
      const preview: string = formatPreview(message ?? null);
      const text: string = preview !== '' ? preview : str('ns_new_message_body');
      const who: string = message !== undefined ? this.senderPrefix(message, chatId) : '';
      return {
        id: id, groupId: groupId, chatId: chatId,
        title: title, text: who !== '' ? `${who}: ${text}` : text, isCall: false,
        avatarPath: message !== undefined
          ? this.senderAvatarPath(message, chatId)
          : (entry !== undefined ? entry.avatarPath : '')
      };
    }
    if (typeName === 'notificationTypeNewCall') {
      return {
        id: id, groupId: groupId, chatId: chatId,
        title: title, text: str('ns_incoming_call'), isCall: true,
        avatarPath: entry !== undefined ? entry.avatarPath : ''
      };
    }
    if (typeName === 'notificationTypeNewSecretChat') {
      return {
        id: id, groupId: groupId, chatId: chatId,
        title: title, text: str('ns_new_secret_chat'), isCall: false,
        avatarPath: entry !== undefined ? entry.avatarPath : ''
      };
    }
    // notificationTypeNewPushMessage 仅在推送场景出现，本方案不会收到。
    return null;
  }

  // 通知发布的唯一来源。本机 td 的 updateNotificationGroup 只在启动同步等
  // 特定时机产出，后台实时消息期间并不推送，因此不能依赖它发布；改为直接
  // 从 updateNewMessage 生成，静音判定用 ChatStore 已同步的 isMuted。
  // 已发通知按会话记录，会话被读完时统一撤销。
  private noticeIdsByChat: Map<number, number[]> = new Map();
  // 分类默认静音已搬到 store/ScopeMuteStore——界面也要读它（会话列表画不画
  // 铃铛）。留在服务实例里的那份别人拿不到，结果就是"通知不弹、列表却显示
  // 未静音"这种自相矛盾。
  // chatId → 该会话是否使用分类默认值 / 自身 mute_for（来自 updateChat*）。
  private chatUsesDefaultMute: Map<number, boolean> = new Map();
  private chatOwnMuted: Map<number, boolean> = new Map();

  private scopeKeyOf(chatId: number): string {
    const entry = this.chats.entryOf(chatId);
    const kind: string = entry !== undefined ? entry.kind : 'private';
    if (kind === 'channel') {
      return 'channel';
    }
    if (kind === 'basicGroup' || kind === 'supergroup') {
      return 'group';
    }
    return 'private';
  }

  // 本机按类型的通知开关（设置 → 通知）。关掉即不弹，优先于服务端设置。
  private typeAllowed(chatId: number): boolean {
    const scope: string = this.scopeKeyOf(chatId);
    if (scope === 'group') {
      return AppStorage.get<boolean>(KEY_NOTIFY_GROUP) ?? true;
    }
    if (scope === 'channel') {
      return AppStorage.get<boolean>(KEY_NOTIFY_CHANNEL) ?? true;
    }
    return AppStorage.get<boolean>(KEY_NOTIFY_PRIVATE) ?? true;
  }

  // 会话是否应当静音：优先会话自身设置，未覆盖时回落到分类默认。
  private isChatMuted(chatId: number): boolean {
    const usesDefault: boolean = this.chatUsesDefaultMute.get(chatId) ?? true;
    if (!usesDefault) {
      return this.chatOwnMuted.get(chatId) ?? false;
    }
    return scopeMuted(this.scopeKeyOf(chatId));
  }

  private trackChatNotificationSettings(chatId: number, settings: TdObject | undefined): void {
    if (settings === undefined || chatId === 0) {
      return;
    }
    const usesDefault: boolean =
      (settings['use_default_mute_for'] as boolean | undefined) ?? true;
    this.chatUsesDefaultMute.set(chatId, usesDefault);
    this.chatOwnMuted.set(chatId, ((settings['mute_for'] as number | undefined) ?? 0) > 0);
  }

  private refreshScopeMute(): void {
    const scopes: string[] = ['private', 'group', 'channel'];
    const typeNames: string[] = [
      'notificationSettingsScopePrivateChats',
      'notificationSettingsScopeGroupChats',
      'notificationSettingsScopeChannelChats'
    ];
    for (let i = 0; i < scopes.length; i++) {
      const req: TdRequest = { '@type': 'getScopeNotificationSettings' };
      req['scope'] = { '@type': typeNames[i] } as TdObject;
      const key: string = scopes[i];
      this.client.send(req).then((res: TdObject): void => {
        const muted: boolean = ((res['mute_for'] as number | undefined) ?? 0) > 0;
        setScopeMuted(key, muted);
      }).catch((e: TdError): void => {
        logE(`NotificationService.getScopeNotificationSettings(${key}): ${e.message}`);
      });
    }
  }

  private considerFallbackNotice(message: TdObject | undefined, chatId: number,
    outgoing: boolean): void {
    if (message === undefined || outgoing || chatId === 0 || this.isForeground()) {
      return;
    }
    // 判定顺序：本机类型开关 → 服务端（会话/分类）静音状态。
    if (!this.typeAllowed(chatId) || this.isChatMuted(chatId)) {
      return;
    }
    const entry = this.chats.entryOf(chatId);
    const messageId: number = (message['id'] as number | undefined) ?? 0;
    if (messageId === 0) {
      return;
    }
    // TDLib 通知 id 是小整数；用会话内消息序号压缩到安全范围避免冲突。
    const noticeId: number = Math.abs(Math.floor(messageId / 1048576)) % 900000 + 1000;
    const shown: number[] = this.noticeIdsByChat.get(chatId) ?? [];
    if (shown.indexOf(noticeId) < 0) {
      this.noticeIdsByChat.set(chatId, [...shown, noticeId]);
    }
    const preview: string = formatPreview(message);
    const who: string = this.senderPrefix(message, chatId);
    this.publisher.publish({
      id: noticeId,
      groupId: 0,
      chatId: chatId,
      title: entry !== undefined && entry.title !== '' ? entry.title : str('ns_new_message'),
      text: who !== '' ? `${who}: ${preview}` : preview,
      isCall: false,
      avatarPath: this.senderAvatarPath(message, chatId)
    });
  }

  // 群/频道消息的头像应该是发信人的，不是会话的 —— 官方客户端就是这样，
  // 一屏全是同一个群头像根本认不出谁在说话。私聊里 chatId 就是对方，两者
  // 本来就同一张图，不必绕。
  //
  // 取不到发信人头像时回退会话头像，并顺手把它拉下来，下一条通知就有了。
  // 不为它推迟发布：通知的时效性比头像重要。
  private senderAvatarPath(message: TdObject, chatId: number): string {
    const entry = this.chats.entryOf(chatId);
    const chatPath: string = entry !== undefined ? entry.avatarPath : '';
    const kind: string = entry !== undefined ? entry.kind : 'private';
    if (kind === 'private' || kind === 'secret') {
      return chatPath;
    }
    const files = this.files;
    if (files === null) {
      return chatPath;
    }
    const fileId: number = this.senderPhotoFileId(message);
    if (fileId === 0) {
      return chatPath;
    }
    const path: string = files.avatarPathOf(fileId);
    if (path !== '') {
      return path;
    }
    files.prefetchAvatar(fileId);
    return chatPath;
  }

  private senderPhotoFileId(message: TdObject): number {
    const sender = message['sender_id'] as TdObject | undefined;
    if (sender === undefined) {
      return 0;
    }
    const senderType: string = (sender['@type'] as string | undefined) ?? '';
    if (senderType === 'messageSenderUser') {
      const userId: number = (sender['user_id'] as number | undefined) ?? 0;
      const users = this.users;
      if (userId === 0 || users === null) {
        return 0;
      }
      // TDLib 没推过这个用户时 photoFileId 是 0；ensure 拉一次，下条通知能用。
      users.ensure(userId);
      return users.photoFileId(userId);
    }
    if (senderType === 'messageSenderChat') {
      const senderChatId: number = (sender['chat_id'] as number | undefined) ?? 0;
      return senderChatId !== 0 ? this.chats.photoFileIdOf(senderChatId) : 0;
    }
    return 0;
  }

  // 群里换成发信人头像后，正文得点出是谁 —— 否则只剩一张陌生的脸。
  // 频道以自己身份发帖（messageSenderChat 且就是本会话）时不加前缀。
  private senderPrefix(message: TdObject, chatId: number): string {
    const entry = this.chats.entryOf(chatId);
    const kind: string = entry !== undefined ? entry.kind : 'private';
    if (kind === 'private' || kind === 'secret') {
      return '';
    }
    const sender = message['sender_id'] as TdObject | undefined;
    if (sender === undefined) {
      return '';
    }
    const senderType: string = (sender['@type'] as string | undefined) ?? '';
    if (senderType === 'messageSenderUser') {
      const userId: number = (sender['user_id'] as number | undefined) ?? 0;
      const users = this.users;
      const name: string = userId !== 0 && users !== null ? users.displayName(userId) : '';
      return name;
    }
    if (senderType === 'messageSenderChat') {
      const senderChatId: number = (sender['chat_id'] as number | undefined) ?? 0;
      if (senderChatId === chatId || senderChatId === 0) {
        return ''; // 频道以自己的身份发帖
      }
      const senderEntry = this.chats.entryOf(senderChatId);
      return senderEntry !== undefined ? senderEntry.title : '';
    }
    return '';
  }

  private onCallSnapshot(s: CallSnapshot): void {
    const ringing: boolean = s.phase === 'ringing' && !s.isOutgoing;
    // 尝试交给系统来电界面（锁屏也能显示）；不被接受时下面的通知照常兜底。
    if (ringing) {
      // 私聊 chatId 即对端 userId，头像由 ChatStore 同步下载后给出本地路径。
      const peer = this.chats.entryOf(s.peerUserId);
      systemCallUi.reportIncoming(s.callId, s.peerName, s.isVideo,
        peer !== undefined ? peer.avatarPath : '');
    } else if (s.phase === 'active') {
      systemCallUi.reportActive();
    } else if (s.phase === 'ended' || s.phase === 'idle') {
      systemCallUi.reportEnded();
    }
    if (ringing && !this.isForeground()) {
      this.callNoticeShown = true;
      const caller = this.chats.entryOf(s.peerUserId);
      this.publisher.publish({
        id: CALL_NOTIFICATION_ID, groupId: 0, chatId: s.peerUserId,
        title: s.peerName !== '' ? s.peerName : str('ns_incoming_call'),
        text: s.isVideo ? str('ns_incoming_video_call') : str('ns_incoming_voice_call'), isCall: true,
        avatarPath: caller !== undefined ? caller.avatarPath : ''
      });
      return;
    }
    if (!ringing && this.callNoticeShown) {
      this.callNoticeShown = false;
      this.publisher.cancel(CALL_NOTIFICATION_ID);
    }
  }
}
