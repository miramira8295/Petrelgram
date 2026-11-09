import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { GroupPermissions, permissionValue } from '../util/chatPermissions';
import { firstDeniedPermission, SEND_PERMISSION_KEYS } from '../util/sendPermissions';
import { readSendPermissions, SendPermissionPort } from '../store/SendPermissionApi';

// One picker session: bounded local TDLib reads, no polling, never show unchecked targets.
export class TargetSendFilter {
  private candidates: Set<number> = new Set();
  private permissions: Map<number, GroupPermissions | null> = new Map();
  private pending: Set<number> = new Set();
  private groupRefs: Map<number, string> = new Map();
  private keys: string[] | null = null;
  private sourceFailed: boolean = false;
  private generation: number = 0;
  private running: number = 0;
  private disposed: boolean = false;
  private off: (() => void)[] = [];

  constructor(privatePort: SendPermissionPort, privateLoad: () => Promise<string[]>,
    privateChanged: () => void, privateActive: () => boolean) {
    this.port = privatePort; this.load = privateLoad; this.changed = privateChanged; this.active = privateActive;
  }
  private port: SendPermissionPort;
  private load: () => Promise<string[]>;
  private changed: () => void;
  private active: () => boolean;

  bind(client: TdClient): void {
    this.off = ['updateChatPermissions', 'updateSupergroup', 'updateBasicGroup'].map((type: string): (() => void) =>
      client.onUpdate(type, (update: TdObject): void => {
        if (type === 'updateChatPermissions') {
          if (this.candidates.has(update['chat_id'] as number)) { this.invalidate(); }
          return;
        }
        const group = update[type === 'updateSupergroup' ? 'supergroup' : 'basic_group'] as TdObject | undefined;
        const ref: string = `${type}:${group?.['id']}`;
        if (Array.from(this.groupRefs.values()).includes(ref)) { this.invalidate(); }
      }));
    this.reload();
  }
  reload(): void {
    const generation = ++this.generation;
    this.keys = null; this.sourceFailed = false; this.permissions.clear(); this.pending.clear();
    this.notify();
    this.load().then((keys: string[]): void => {
      if (!this.current(generation)) { return; }
      this.keys = keys; this.pump(); this.notify();
    }).catch((): void => {
      if (!this.current(generation)) { return; }
      this.sourceFailed = true; this.notify();
    });
  }
  invalidate(): void {
    if (this.disposed) { return; }
    if (this.keys === null) { this.reload(); return; }
    this.generation++; this.permissions.clear(); this.pending.clear();
    this.pump(); this.notify();
  }
  include(ids: number[]): void {
    let added: boolean = false;
    for (const id of ids) {
      if (id !== 0 && !this.candidates.has(id)) { this.candidates.add(id); added = true; }
    }
    if (added) { this.pump(); this.notify(); }
  }
  // The long-lived snapshot publisher only needs the current shortlist.
  retain(ids: number[]): void {
    const keep: Set<number> = new Set(ids);
    for (const id of this.candidates) {
      if (!keep.has(id)) { this.candidates.delete(id); this.permissions.delete(id); this.groupRefs.delete(id); }
    }
    this.include(ids);
  }
  allowedIds(): number[] {
    if (this.keys === null) { return []; }
    return Array.from(this.permissions.keys()).filter((id: number): boolean => {
      const permissions = this.permissions.get(id);
      return permissions !== undefined && permissions !== null && firstDeniedPermission(permissions, this.keys!) === '';
    });
  }
  permissionKeys(id: number): string[] | null {
    const value = this.permissions.get(id);
    return value === undefined || value === null ? null :
      SEND_PERMISSION_KEYS.filter((key: string): boolean => permissionValue(value, key));
  }
  checking(): boolean {
    return !this.sourceFailed && (this.keys === null || Array.from(this.candidates).some((id: number): boolean =>
      !this.permissions.has(id)));
  }
  failed(): boolean { return this.sourceFailed; }
  dispose(): void {
    this.disposed = true; this.generation++; this.off.forEach((off: () => void): void => off()); this.off = [];
  }
  private current(generation: number): boolean { return !this.disposed && this.active() && generation === this.generation; }
  private notify(): void { if (!this.disposed && this.active()) { this.changed(); } }
  private pump(): void {
    if (this.disposed || !this.active() || this.keys === null) { return; }
    for (const id of this.candidates) {
      if (this.running >= 6) { break; }
      if (this.permissions.has(id) || this.pending.has(id)) { continue; }
      const generation = this.generation;
      this.pending.add(id); this.running++;
      readSendPermissions(async (request: TdRequest): Promise<TdObject> => {
        const response = await this.port(request);
        if (request['@type'] === 'getChat' && this.current(generation) && this.candidates.has(id)) {
          const type = response['type'] as TdObject | undefined;
          if (type?.['@type'] === 'chatTypeSupergroup') {
            this.groupRefs.set(id, `updateSupergroup:${type['supergroup_id']}`);
          } else if (type?.['@type'] === 'chatTypeBasicGroup') {
            this.groupRefs.set(id, `updateBasicGroup:${type['basic_group_id']}`);
          }
        }
        return response;
      }, id).then((value: GroupPermissions): void => {
        if (this.current(generation) && this.candidates.has(id)) { this.permissions.set(id, value); }
      }).catch((): void => {
        if (this.current(generation) && this.candidates.has(id)) { this.permissions.set(id, null); }
      }).finally((): void => {
        this.running--;
        if (this.current(generation)) { this.pending.delete(id); }
        this.pump(); this.notify();
      });
    }
  }
}
