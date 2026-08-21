import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatLastSeen } from '../util/formatLastSeen';
import { str } from '../util/strings';
import { logE } from '../util/log';

const DL_PRIORITY: number = 1;

export interface ContactItem {
  id: number;
  name: string;
  initials: string;
  avatarPath: string;
  statusText: string;
  online: boolean;
  sortKey: number; // was_online ts for offline; huge for online; small negatives for coarse buckets
}

type Listener = () => void;

// Backing store for the contacts tab: getContacts → per-user name/status/avatar,
// sorted by last-seen (online first), kept live via updateUserStatus.
export class ContactsStore {
  private client: TdClient;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private fileApply: Map<number, (path: string) => void> = new Map();
  private avatarFileByUser: Map<number, number> = new Map();
  private byId: Map<number, ContactItem> = new Map();
  private loadSequence: number = 0;

  contacts: ContactItem[] = [];
  loading: boolean = true;
  errorMessage: string = '';

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
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => {
      const uid = u['user_id'] as number | undefined;
      if (uid !== undefined && this.byId.has(uid)) {
        this.updateStatus(uid, u['status'] as TdObject | undefined);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateUser', (u: TdObject) => {
      const user = u['user'] as TdObject | undefined;
      if (user !== undefined) {
        this.applyUserUpdate(user);
      }
    }));
    this.reload();
  }

  close(): void {
    this.loadSequence++;
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    this.listeners = [];
    this.fileApply.clear();
  }

  reload(): void {
    const sequence = ++this.loadSequence;
    this.loading = true;
    this.errorMessage = '';
    this.byId.clear();
    this.contacts = [];
    this.fileApply.clear();
    this.avatarFileByUser.clear();
    this.notify();
    const req: TdRequest = { '@type': 'getContacts' };
    this.client.send(req, 8000).then((res: TdObject): void => {
      if (sequence !== this.loadSequence) {
        return;
      }
      const ids = (res['user_ids'] as number[] | undefined) ?? [];
      const loads: Promise<boolean>[] = [];
      for (const id of ids) {
        loads.push(this.loadUser(id, sequence));
      }
      // Do not report "refresh complete" while getUser calls are still
      // trickling in. Publishing one complete snapshot also prevents rows
      // jumping around as faster requests overtake slower ones.
      Promise.all(loads).then((results: boolean[]): void => {
        if (sequence !== this.loadSequence) {
          return;
        }
        this.loading = false;
        if (ids.length > 0 && !results.some((loaded: boolean): boolean => loaded)) {
          this.errorMessage = str('cs_contact_load_failed');
        }
        this.rebuild();
        this.notify();
      });
    }).catch((e: TdError) => {
      if (sequence !== this.loadSequence) {
        return;
      }
      logE(`ContactsStore.getContacts failed: ${e.message}`);
      this.loading = false;
      this.errorMessage = str('contacts_load_failed');
      this.notify();
    });
  }

  removeContact(userId: number): Promise<void> {
    const req: TdRequest = { '@type': 'removeContacts' };
    req['user_ids'] = [userId];
    return this.client.send(req, 8000).then((): void => {
      if (this.byId.delete(userId)) {
        this.avatarFileByUser.delete(userId);
        this.rebuild();
        this.notify();
      }
    });
  }

  private loadUser(id: number, sequence: number): Promise<boolean> {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = id;
    return this.client.send(req, 8000).then((user: TdObject): boolean => {
      if (sequence !== this.loadSequence) {
        return false;
      }
      this.applyUser(user);
      return true;
    }).catch((e: TdError) => {
      logE(`ContactsStore.getUser failed: ${e.message}`);
      return false;
    });
  }

  private applyUserUpdate(user: TdObject): void {
    const id = user['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const isContact = (user['is_contact'] as boolean | undefined) ?? false;
    if (!isContact) {
      if (this.byId.delete(id)) {
        this.avatarFileByUser.delete(id);
        if (!this.loading) {
          this.rebuild();
          this.notify();
        }
      }
      return;
    }
    this.applyUser(user);
    if (!this.loading) {
      this.rebuild();
      this.notify();
    }
  }

  private applyUser(user: TdObject): void {
    const id = user['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const name = `${first}${last !== '' ? ' ' + last : ''}`.trim();
    const status = user['status'] as TdObject | undefined;
    const previous = this.byId.get(id);
    const item: ContactItem = {
      id,
      name: name !== '' ? name : str('cs_unnamed'),
      initials: name.length > 0 ? name.substring(0, 1).toUpperCase() : '?',
      avatarPath: previous !== undefined ? previous.avatarPath : '',
      statusText: formatLastSeen(status, Math.floor(Date.now() / 1000)),
      online: (status !== undefined) && (status['@type'] === 'userStatusOnline'),
      sortKey: this.sortKey(status)
    };
    this.byId.set(id, item);
    const photo = user['profile_photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
    if (fileId <= 0) {
      item.avatarPath = '';
      this.avatarFileByUser.delete(id);
      return;
    }
    if (this.avatarFileByUser.get(id) === fileId && item.avatarPath !== '') {
      return;
    }
    this.avatarFileByUser.set(id, fileId);
    this.download(fileId, (path: string): void => {
      // A late download from an older profile photo must not overwrite the
      // user's newer avatar.
      if (this.avatarFileByUser.get(id) !== fileId) {
        return;
      }
      const current = this.byId.get(id);
      if (current !== undefined) {
        current.avatarPath = path;
        if (!this.loading) {
          this.rebuild();
          this.notify();
        }
      }
    });
  }

  private updateStatus(id: number, status: TdObject | undefined): void {
    const it = this.byId.get(id);
    if (it === undefined) {
      return;
    }
    it.statusText = formatLastSeen(status, Math.floor(Date.now() / 1000));
    it.online = (status !== undefined) && (status['@type'] === 'userStatusOnline');
    it.sortKey = this.sortKey(status);
    if (!this.loading) {
      this.rebuild();
      this.notify();
    }
  }

  private sortKey(status: TdObject | undefined): number {
    if (status === undefined) {
      return -4;
    }
    const type = status['@type'] as string | undefined;
    if (type === 'userStatusOnline') {
      return Number.MAX_SAFE_INTEGER;
    }
    if (type === 'userStatusOffline') {
      return (status['was_online'] as number | undefined) ?? 0;
    }
    if (type === 'userStatusRecently') {
      return -1;
    }
    if (type === 'userStatusLastWeek') {
      return -2;
    }
    if (type === 'userStatusLastMonth') {
      return -3;
    }
    return -4;
  }

  // Rebuild the sorted array with a fresh identity so ArkUI re-renders the list.
  private rebuild(): void {
    const arr: ContactItem[] = [];
    this.byId.forEach((v: ContactItem) => { arr.push(v); });
    arr.sort((a: ContactItem, b: ContactItem): number => {
      const byLastSeen = b.sortKey - a.sortKey;
      return byLastSeen !== 0 ? byLastSeen : a.name.localeCompare(b.name);
    });
    this.contacts = arr;
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
      logE(`ContactsStore.downloadFile failed: ${e.message}`);
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
      this.fileApply.delete(id);
      apply(path);
    }
  }
}
