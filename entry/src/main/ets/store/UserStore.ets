import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from '../util/log';

// Names and profile-photo file ids for users, filled from updateUser pushes and,
// for users TDLib never pushed, by asking for them once (see ensure).
export class UserStore {
  private client: TdClient;
  private names: Map<number, string> = new Map();
  private photos: Map<number, number> = new Map();
  private accents: Map<number, number> = new Map(); // accent_color_id per user
  private requested: Set<number> = new Set();  // getUser sent

  constructor(client: TdClient) {
    this.client = client;
    client.onUpdate('updateUser', (u: TdObject) => this.onUser(u));
  }

  displayName(userId: number): string {
    return this.names.get(userId) ?? '';
  }

  // Small profile-photo file id for a user (0 if none / not yet known).
  photoFileId(userId: number): number {
    return this.photos.get(userId) ?? 0;
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
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    this.names.set(id, `${first} ${last}`.trim());
    this.photos.set(id, this.smallFileId(user['profile_photo'] as TdObject | undefined));
    this.accents.set(id, (user['accent_color_id'] as number | undefined) ?? -1);
  }
}
