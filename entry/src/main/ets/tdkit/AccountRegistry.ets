import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { str } from '../util/strings';

const STORE_NAME: string = 'td_accounts';
const KEY_ACTIVE_SLOT: string = 'active_slot';
const KEY_ACCOUNTS_JSON: string = 'accounts_json';
const PRIMARY_SLOT: string = 'primary';

export const TD_ACCOUNT_REGISTRY_EPOCH: string = 'tdAccountRegistryEpoch';
export const TD_SESSION_EPOCH: string = 'tdSessionEpoch';
export const TD_ACCOUNT_SWITCHING: string = 'tdAccountSwitching';

export interface TdAccountSummary {
  slotId: string;
  userId: number;
  name: string;
  phone: string;
  username: string;
  avatarPath: string;
  pendingLogin: boolean;
  previousSlotId: string;
}

export interface TdAccountDirectories {
  databaseDirectory: string;
  filesDirectory: string;
}

function primaryAccount(): TdAccountSummary {
  return {
    slotId: PRIMARY_SLOT,
    userId: 0,
    name: str('settings_current_account'),
    phone: '',
    username: '',
    avatarPath: '',
    pendingLogin: false,
    previousSlotId: ''
  };
}

function copyAccount(account: TdAccountSummary): TdAccountSummary {
  return {
    slotId: account.slotId,
    userId: account.userId,
    name: account.name,
    phone: account.phone,
    username: account.username,
    avatarPath: account.avatarPath,
    pendingLogin: account.pendingLogin,
    previousSlotId: account.previousSlotId
  };
}

class AccountRegistry {
  private store: preferences.Preferences | null = null;
  private accounts: TdAccountSummary[] = [];
  private activeSlot: string = PRIMARY_SLOT;

  init(context: common.Context): void {
    AppStorage.setOrCreate(TD_ACCOUNT_REGISTRY_EPOCH, 0);
    AppStorage.setOrCreate(TD_SESSION_EPOCH, 0);
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
    try {
      this.store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const raw = this.store.getSync(KEY_ACCOUNTS_JSON, '') as string;
      if (raw !== '') {
        this.accounts = JSON.parse(raw) as TdAccountSummary[];
      }
      if (this.accounts.length === 0) {
        this.accounts = [primaryAccount()];
      }
      const storedActive = this.store.getSync(KEY_ACTIVE_SLOT, PRIMARY_SLOT) as string;
      this.activeSlot = this.hasSlot(storedActive) ? storedActive : this.accounts[0].slotId;
      this.persist();
    } catch (caught) {
      console.error(`AccountRegistry.init failed: ${caught}`);
      this.accounts = [primaryAccount()];
      this.activeSlot = PRIMARY_SLOT;
    }
  }

  all(): TdAccountSummary[] {
    return this.accounts.map((account: TdAccountSummary): TdAccountSummary => copyAccount(account));
  }

  activeSlotId(): string {
    return this.activeSlot;
  }

  active(): TdAccountSummary {
    const account = this.accounts.find(
      (item: TdAccountSummary): boolean => item.slotId === this.activeSlot
    );
    return copyAccount(account ?? this.accounts[0] ?? primaryAccount());
  }

  hasSlot(slotId: string): boolean {
    return this.accounts.some(
      (account: TdAccountSummary): boolean => account.slotId === slotId
    );
  }

  findOtherLoggedInSlot(userId: number, excludingSlotId: string): string {
    if (userId === 0) { return ''; }
    const duplicate = this.accounts.find(
      (account: TdAccountSummary): boolean =>
        account.slotId !== excludingSlotId &&
        account.userId === userId &&
        !account.pendingLogin
    );
    return duplicate?.slotId ?? '';
  }

  setActive(slotId: string): boolean {
    if (!this.hasSlot(slotId)) { return false; }
    if (this.activeSlot === slotId) { return true; }
    this.activeSlot = slotId;
    this.persist();
    this.bumpRegistryEpoch();
    return true;
  }

  addPendingAccount(): TdAccountSummary {
    const slotId = `account_${Date.now()}`;
    const account: TdAccountSummary = {
      slotId,
      userId: 0,
      name: str('ar_new_account'),
      phone: '',
      username: '',
      avatarPath: '',
      pendingLogin: true,
      previousSlotId: this.activeSlot
    };
    this.accounts = [...this.accounts, account];
    this.activeSlot = slotId;
    this.persist();
    this.bumpRegistryEpoch();
    return copyAccount(account);
  }

  updateActiveProfile(
    userId: number, name: string, phone: string, username: string, avatarPath: string
  ): void {
    const index = this.accounts.findIndex(
      (account: TdAccountSummary): boolean => account.slotId === this.activeSlot
    );
    if (index < 0) { return; }
    const current = this.accounts[index];
    const nextName = name !== '' ? name : current.name;
    const nextAvatar = avatarPath !== '' ? avatarPath : current.avatarPath;
    if (current.userId === userId && current.name === nextName &&
      current.phone === phone && current.username === username &&
      current.avatarPath === nextAvatar && !current.pendingLogin &&
      current.previousSlotId === '') {
      return;
    }
    const next: TdAccountSummary = {
      slotId: current.slotId,
      userId,
      name: nextName,
      phone,
      username,
      avatarPath: nextAvatar,
      pendingLogin: false,
      previousSlotId: ''
    };
    const copy = [...this.accounts];
    copy[index] = next;
    this.accounts = copy;
    this.persist();
    this.bumpRegistryEpoch();
  }

  directories(baseFilesDir: string, slotId: string): TdAccountDirectories {
    if (slotId === PRIMARY_SLOT) {
      // Keep the original database paths for a migration-free first upgrade.
      return {
        databaseDirectory: `${baseFilesDir}/tdlib`,
        filesDirectory: `${baseFilesDir}/tdlib_files`
      };
    }
    const root = `${baseFilesDir}/td_accounts/${slotId}`;
    return {
      databaseDirectory: `${root}/tdlib`,
      filesDirectory: `${root}/tdlib_files`
    };
  }

  previousSlotForActivePending(): string {
    const current = this.active();
    if (!current.pendingLogin || current.previousSlotId === '' ||
      !this.hasSlot(current.previousSlotId)) {
      return '';
    }
    return current.previousSlotId;
  }

  // 冷启动自愈：一个没完成的「加账号」不该在重启后还占着 active 槽位。
  //
  // 用户在登录页杀掉进程后，那个空槽位仍是 active，重开 app 只会回到登录页，
  // 而唯一的出口「返回原账号」是**页面上的一个按钮**——它依赖 UI 走到那一步。
  // 一旦没走到，原账号就再也进不去了。这里在建运行时之前把它清掉。
  //
  // userId === 0 是硬保险：只有从没拿到过用户身份的槽位才丢。真正登录成功过
  // 的账号即便 pendingLogin 标志因故没清干净，也绝不会被删。
  //
  // 返回接手的槽位 id，没有可回退的目标时返回 ''（例如首次登录本身就是
  // pending，那时不该动任何东西）。
  abandonStalePending(): string {
    const current = this.active();
    if (!current.pendingLogin || current.userId !== 0) {
      return '';
    }
    const previous = current.previousSlotId;
    if (previous === '' || !this.hasSlot(previous)) {
      return '';
    }
    this.activeSlot = previous;
    this.accounts = this.accounts.filter(
      (item: TdAccountSummary): boolean => item.slotId !== current.slotId
    );
    this.persist();
    this.bumpRegistryEpoch();
    return previous;
  }

  discardPending(slotId: string): void {
    const account = this.accounts.find(
      (item: TdAccountSummary): boolean => item.slotId === slotId
    );
    if (account === undefined || !account.pendingLogin || this.activeSlot === slotId) {
      return;
    }
    this.accounts = this.accounts.filter(
      (item: TdAccountSummary): boolean => item.slotId !== slotId
    );
    this.persist();
    this.bumpRegistryEpoch();
  }

  markLoggedOut(slotId: string): void {
    const index = this.accounts.findIndex(
      (item: TdAccountSummary): boolean => item.slotId === slotId
    );
    if (index < 0) { return; }
    const current = this.accounts[index];
    const copy = [...this.accounts];
    copy[index] = {
      slotId: current.slotId,
      userId: 0,
      name: str('ar_new_account'),
      phone: '',
      username: '',
      avatarPath: '',
      pendingLogin: true,
      previousSlotId: ''
    };
    this.accounts = copy;
    this.persist();
    this.bumpRegistryEpoch();
  }

  removeAccount(slotId: string): void {
    if (this.activeSlot === slotId || this.accounts.length <= 1) { return; }
    const next = this.accounts.filter(
      (item: TdAccountSummary): boolean => item.slotId !== slotId
    );
    if (next.length === this.accounts.length || next.length === 0) { return; }
    this.accounts = next;
    this.persist();
    this.bumpRegistryEpoch();
  }

  removeDuplicatesForActive(): number {
    const active = this.accounts.find(
      (account: TdAccountSummary): boolean => account.slotId === this.activeSlot
    );
    if (active === undefined || active.userId === 0 || active.pendingLogin) {
      return 0;
    }
    const next = this.accounts.filter(
      (account: TdAccountSummary): boolean =>
        account.slotId === active.slotId || account.userId !== active.userId
    );
    const removed = this.accounts.length - next.length;
    if (removed <= 0 || next.length === 0) { return 0; }
    this.accounts = next;
    this.persist();
    this.bumpRegistryEpoch();
    return removed;
  }

  private persist(): void {
    if (this.store === null) { return; }
    try {
      this.store.putSync(KEY_ACTIVE_SLOT, this.activeSlot);
      this.store.putSync(KEY_ACCOUNTS_JSON, JSON.stringify(this.accounts));
      this.store.flushSync();
    } catch (caught) {
      console.error(`AccountRegistry.persist failed: ${caught}`);
    }
  }

  private bumpRegistryEpoch(): void {
    const previous = AppStorage.get<number>(TD_ACCOUNT_REGISTRY_EPOCH) ?? 0;
    AppStorage.setOrCreate(TD_ACCOUNT_REGISTRY_EPOCH, previous + 1);
  }
}

export const accountRegistry: AccountRegistry = new AccountRegistry();
