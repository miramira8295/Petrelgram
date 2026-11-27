import { isDeletedUser } from '../util/deletedUser';
import { str } from '../util/strings';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from '../util/log';
import { photoHasAnimation } from '../util/photoAnimation';
import { BotTopicFlags, botTopicFlagsOf } from '../util/botTopicMode';
import { senderChannelKey } from '../util/senderAvatarChannel';
import { invalidateSenderAnimation } from '../util/senderAnimationChannel';

// Names and profile-photo file ids for users, filled from updateUser pushes and,
// for users TDLib never pushed, by asking for them once (see ensure).
export class UserStore {
  private client: TdClient;
  private deleted: Set<number> = new Set<number>();
  private bots: Set<number> = new Set<number>();
  private onlineUsers: Set<number> = new Set<number>();
  private names: Map<number, string> = new Map();
  private usernames: Map<number, string[]> = new Map();
  private photos: Map<number, number> = new Map();
  private accents: Map<number, number> = new Map(); // accent_color_id per user
  // profile_photo.has_animation：群聊气泡左侧要不要去取动态头像（issue #140）。
  private animated: Set<number> = new Set();
  // 开了话题模式的 Bot / 其中允许用户自己建话题的（issue #206）。
  private topicBots: Set<number> = new Set();
  private userTopicBots: Set<number> = new Set();
  private requested: Set<number> = new Set();  // getUser sent

  constructor(client: TdClient) {
    this.client = client;
    client.onUpdate('updateUser', (u: TdObject) => this.onUser(u));
    client.onUpdate('updateUserStatus', (u: TdObject) => this.onUserStatus(u));
  }

  displayName(userId: number): string {
    return this.deleted.has(userId) ? str('deleted_account') : this.names.get(userId) ?? '';
  }

  usernamesOf(userId: number): string[] {
    return this.usernames.get(userId) ?? [];
  }

  primaryUsername(userId: number): string {
    const list: string[] = this.usernames.get(userId) ?? [];
    return list.length > 0 ? list[0] : '';
  }

  isDeleted(userId: number): boolean { return this.deleted.has(userId); }

  isOnline(userId: number): boolean {
    return !this.deleted.has(userId) && !this.bots.has(userId) && this.onlineUsers.has(userId);
  }

  // Small profile-photo file id for a user (0 if none / not yet known).
  photoFileId(userId: number): number {
    return this.photos.get(userId) ?? 0;
  }

  // 头像是不是动态的。profilePhoto 只带这个标志，MP4 要另取完整资料。
  hasAnimatedPhoto(userId: number): boolean {
    return this.animated.has(userId);
  }

  // Bot 私聊开没开话题模式。
  botHasTopics(userId: number): boolean {
    return this.topicBots.has(userId);
  }

  // 用户能不能在这个 Bot 的私聊里自己建/删话题。
  botAllowsUserTopics(userId: number): boolean {
    return this.userTopicBots.has(userId);
  }

  knows(userId: number): boolean {
    return this.names.has(userId);
  }

  // Telegram name accent color id (-1 when the user isn't known yet).
  accentColorId(userId: number): number {
    return this.accents.get(userId) ?? -1;
  }

  // TDLib only pushes updateUser for users it has surfaced to us. Senders in a
  // chat we reached some other way (global search) may never be pushed, leaving
  // their name and avatar blank forever. Pull them once — the getUser reply
  // arrives as an updateUser and lands in onUser like any other. Gated on the
  // photo rather than the name: a stripped-down user carries a name but no
  // photo, and gating on the name would skip exactly the users that need this.
  ensure(userId: number): void {
    if (userId <= 0 || (this.photos.get(userId) ?? 0) > 0 || this.requested.has(userId)) {
      return;
    }
    this.requested.add(userId);
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = userId;
    this.client.send(req).catch((e: TdError) => {
      this.requested.delete(userId);
      logE(`UserStore.getUser(${userId}) failed: ${e.message}`);
    });
  }

  // chatPhoto / profilePhoto both expose the thumbnail under `small`.
  private smallFileId(photo: TdObject | undefined): number {
    if (photo === undefined) {
      return 0;
    }
    const small = photo['small'] as TdObject | undefined;
    return small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
  }

  private onUser(update: TdObject): void {
    const user = update['user'] as TdObject | undefined;
    if (user === undefined) {
      return;
    }
    const id = user['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    if (isDeletedUser(user)) { this.deleted.add(id); } else { this.deleted.delete(id); }
    const userType = user['type'] as TdObject | undefined;
    if ((userType?.['@type'] as string | undefined) === 'userTypeBot') {
      this.bots.add(id);
    } else {
      this.bots.delete(id);
    }
    this.applyUserStatus(id, user['status'] as TdObject | undefined);
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    this.names.set(id, `${first} ${last}`.trim());
    const unameObj = user['usernames'] as TdObject | undefined;
    const collected: string[] = [];
    if (unameObj !== undefined) {
      const editable: string = (unameObj['editable_username'] as string | undefined) ?? '';
      if (editable !== '') {
        collected.push(editable.toLowerCase());
      }
      const active = unameObj['active_usernames'] as string[] | undefined;
      if (active !== undefined) {
        for (const u of active) {
          const low: string = u.toLowerCase();
          if (low !== '' && collected.indexOf(low) < 0) {
            collected.push(low);
          }
        }
      }
    }
    if (collected.length > 0) {
      this.usernames.set(id, collected);
    } else {
      this.usernames.delete(id);
    }
    const profilePhoto = this.deleted.has(id) ? undefined : user['profile_photo'] as TdObject | undefined;
    const photoId: number = this.smallFileId(profilePhoto);
    const previousPhotoId: number | undefined = this.photos.get(id);
    this.photos.set(id, photoId);
    if (photoHasAnimation(profilePhoto)) {
      this.animated.add(id);
    } else {
      this.animated.delete(id);
    }
    if (previousPhotoId !== undefined && previousPhotoId !== photoId) {
      // 换了头像：已经取到的动态头像是旧的。
      invalidateSenderAnimation(senderChannelKey(id, true));
    }
    this.accents.set(id, (user['accent_color_id'] as number | undefined) ?? -1);
    const topicFlags: BotTopicFlags = botTopicFlagsOf(user);
    if (topicFlags.hasTopics) {
      this.topicBots.add(id);
    } else {
      this.topicBots.delete(id);
    }
    if (topicFlags.allowsUserTopics) {
      this.userTopicBots.add(id);
    } else {
      this.userTopicBots.delete(id);
    }
  }

  private onUserStatus(update: TdObject): void {
    const id = (update['user_id'] as number | undefined) ?? 0;
    if (id <= 0) {
      return;
    }
    this.applyUserStatus(id, update['status'] as TdObject | undefined);
  }

  private applyUserStatus(userId: number, status: TdObject | undefined): void {
    if ((status?.['@type'] as string | undefined) === 'userStatusOnline') {
      this.onlineUsers.add(userId);
    } else {
      this.onlineUsers.delete(userId);
    }
  }
}
