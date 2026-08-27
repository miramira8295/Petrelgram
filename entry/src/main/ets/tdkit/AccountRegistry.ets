import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import fs from '@ohos.file.fs';
import { str } from '../util/strings';
import { logE, logW } from '../util/log';

const STORE_NAME: string = 'td_accounts';
const KEY_ACTIVE_SLOT: string = 'active_slot';
const KEY_ACCOUNTS_JSON: string = 'accounts_json';
const PRIMARY_SLOT: string = 'primary';

// 一个 TDLib 库里 td.binlog 的大小，用来区分"真的登录过"和"开了一下就废"。
// 实测：登录过的约 927KB 并带 profile_photos/stickers/thumbnails 等子目录；
// 没走完登录的空槽只有 9.6KB、且一个子目录都没有。取 64KB 做界，两者相差
// 两个数量级，不需要更精细。
const LIVE_BINLOG_BYTES: number = 64 * 1024;

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
  private baseFilesDir: string = '';

  // 磁盘上这个库是不是真的登录过。
  private static hasLiveSession(databaseDirectory: string): boolean {
    try {
      const binlog = `${databaseDirectory}/td.binlog`;
      if (!fs.accessSync(binlog)) {
        return false;
      }
      return fs.statSync(binlog).size >= LIVE_BINLOG_BYTES;
    } catch (caught) {
      logE(`AccountRegistry.hasLiveSession failed: ${caught}`);
      return false;
    }
  }

  // 按磁盘自愈：注册表里没有、但库里确实有会话的槽位补回来。
  //
  // 起因是一次真实的数据丢失：主账号的条目从 accounts_json 里消失了，而它
  // 206MB 的库原封不动躺在磁盘上——init() 只有在 JSON 整个为空时才补 primary，
  // 于是那个账号再也进不去。**条目可以丢，数据不能丢**：数据库才是"这里有个
  // 账号"的事实来源，JSON 只是它的元信息缓存。
  //
  // 主动退登过的槽位不会被误捡：TDLib 退登时会把库清空，binlog 掉回 10KB
  // 量级，hasLiveSession 直接判否。
  private recoverOrphanedSlots(baseFilesDir: string): number {
    let added: number = 0;
    const candidates: string[] = [PRIMARY_SLOT];
    try {
      const root = `${baseFilesDir}/td_accounts`;
      if (fs.accessSync(root)) {
        for (const name of fs.listFileSync(root)) {
          candidates.push(name);
        }
      }
    } catch (caught) {
      logE(`AccountRegistry.recoverOrphanedSlots list failed: ${caught}`);
    }
    for (const slotId of candidates) {
      if (this.hasSlot(slotId)) {
        continue;
      }
      const dirs = this.directories(baseFilesDir, slotId);
      if (!AccountRegistry.hasLiveSession(dirs.databaseDirectory)) {
        continue;
      }
      // 名字和头像等它被激活后由 updateActiveProfile 填上；这里只保证进得去。
      this.accounts = [...this.accounts, {
        slotId,
        userId: 0,
        name: slotId === PRIMARY_SLOT ? str('settings_current_account') : str('ar_new_account'),
        phone: '',
        username: '',
        avatarPath: '',
        pendingLogin: false,
        previousSlotId: ''
      }];
      added++;
      logE(`AccountRegistry: recovered orphaned slot ${slotId}`);
    }
    return added;
  }

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
      this.baseFilesDir = context.filesDir;
      this.recoverOrphanedSlots(context.filesDir);
      const storedActive = this.store.getSync(KEY_ACTIVE_SLOT, PRIMARY_SLOT) as string;
      this.activeSlot = this.hasSlot(storedActive) ? storedActive : this.accounts[0].slotId;
      this.persist();
    } catch (caught) {
      logE(`AccountRegistry.init failed: ${caught}`);
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

  // 除当前槽外，还有没有一个「登录过」的槽可以回去。
  //
  // 「返回原账号」原来只认 previousSlotForActivePending()，即当前槽必须是
  // pendingLogin 且记着来路。真机上出现过第三种状态：清理重复登录时 logOut()
  // 成功、后续切回失败，活跃槽停在一个已登出的空库上、pendingLogin 还是 false
  // ——按钮不显示、冷启动自愈也够不着，用户被锁在登录页（本条就是那次事故）。
  // 判据放宽成「还有别的可用槽」，出口就一直在。
  otherUsableSlotId(): string {
    const activeId = this.activeSlot;
    const hit = this.accounts.find((item: TdAccountSummary): boolean =>
      item.slotId !== activeId && !item.pendingLogin && item.userId !== 0);
    return hit !== undefined ? hit.slotId : '';
  }

  // 切换失败时该退到哪：previousSlotId 本身登录过就退回去，否则找别的登录过的
  // 槽；一个都没有返回 ''（issue #101：退回一个刚登出的空槽等于锁在登录页）。
  usableFallbackSlot(previousSlotId: string): string {
    const previous = this.accounts.find(
      (item: TdAccountSummary): boolean => item.slotId === previousSlotId);
    if (previous !== undefined && !previous.pendingLogin && previous.userId !== 0) {
      return previousSlotId;
    }
    return this.otherUsableSlotId();
  }

  // 活跃槽的摘要里有没有用户身份。它为真却又停在登录页，说明摘要与 TDLib 对不上。
  activeSummaryHasUser(): boolean {
    return this.active().userId !== 0;
  }

  previousSlotForActivePending(): string {
    const current = this.active();
    // 诊断：登录页左上角的「返回原账号」不显示（用户报）。三个条件哪个空了，
    // 光看现象分不出来——pendingLogin 没立、previousSlotId 没记、还是原槽没了。
    logW(`[AddAcct] slot=${current.slotId} pending=${current.pendingLogin}`
      + ` prev=${current.previousSlotId === '' ? '(empty)' : current.previousSlotId}`
      + ` prevExists=${current.previousSlotId !== '' && this.hasSlot(current.previousSlotId)}`
      + ` userId=${current.userId} slots=${this.all().length}`);
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
    const recorded = current.previousSlotId;
    // 没记来路（重复登录清理把它写成了 ''）就找别的登录过的槽（issue #101）。
    const previous = (recorded !== '' && this.hasSlot(recorded)) ? recorded : this.otherUsableSlotId();
    if (previous === '') {
      return '';
    }
    this.activeSlot = previous;
    this.dropSlots([current.slotId], 'abandonStalePending');
    return previous;
  }

  discardPending(slotId: string): void {
    const account = this.accounts.find(
      (item: TdAccountSummary): boolean => item.slotId === slotId
    );
    if (account === undefined || !account.pendingLogin || this.activeSlot === slotId) {
      return;
    }
    this.dropSlots([slotId], 'discardPending');
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
    this.dropSlots([slotId], 'removeAccount');
  }

  removeDuplicatesForActive(): number {
    const active = this.accounts.find(
      (account: TdAccountSummary): boolean => account.slotId === this.activeSlot
    );
    if (active === undefined || active.userId === 0 || active.pendingLogin) {
      return 0;
    }
    // 同一个 userId 的其它槽位，**只清理没有活会话的空壳**。
    //
    // 原来是一律删掉，代价很实：删的是一行元信息，留下的是几百 MB 的库——
    // 实测把 primary（206MB、完整数据）从列表里抹掉，账号再也进不去。同一个
    // 账号在两个槽位各有一份数据时，哪一份更该留不是这里能判断的，所以一份
    // 都不动，交给用户自己在账号列表里处理。
    const duplicates = this.accounts
      .filter((account: TdAccountSummary): boolean =>
        account.slotId !== active.slotId && account.userId === active.userId)
      .filter((account: TdAccountSummary): boolean => {
        const dirs = this.directories(this.baseFilesDir, account.slotId);
        return !AccountRegistry.hasLiveSession(dirs.databaseDirectory);
      })
      .map((account: TdAccountSummary): string => account.slotId);
    return this.dropSlots(duplicates, 'dedupe');
  }

  // 所有删除条目的路径都走这里。
  //
  // 不需要"墓碑"记住谁被删过：真正的退登会让 TDLib 把库清空（binlog 从
  // 900KB 回落到 10KB 量级），自愈扫描据此自然跳过它。反过来，自动去重那类
  // 删除并不动库，被误删的账号下次启动就会被捡回来——这正是我们要的。
  //
  // 曾经加过墓碑，结果把"数据完好、只是被自动去重误删"的账号永久挡在门外，
  // 恰好是它要防的那个损失。数据目录一律留在原地。
  private dropSlots(slotIds: string[], reason: string): number {
    if (slotIds.length === 0) {
      return 0;
    }
    const next = this.accounts.filter(
      (item: TdAccountSummary): boolean => slotIds.indexOf(item.slotId) < 0
    );
    const removed = this.accounts.length - next.length;
    if (removed <= 0 || next.length === 0) {
      return 0;
    }
    this.accounts = next;
    logE(`AccountRegistry.dropSlots(${reason}): ${slotIds.join(',')}`);
    this.persist();
    this.bumpRegistryEpoch();
    return removed;
  }

  // 手动移除一个账号：条目和数据一起删。
  //
  // 数据必须一起删，否则下次启动自愈会按磁盘把它捡回来——那是给"误删条目"
  // 兜底的，分不清这次是用户自己要删的。这也是全项目唯一会删 TDLib 库的地方。
  //
  // 拒绝删当前账号：正在跑的运行时还开着这个库。
  removeAccountAndData(slotId: string): boolean {
    if (slotId === this.activeSlot || !this.hasSlot(slotId) || this.accounts.length <= 1) {
      return false;
    }
    const dirs = this.directories(this.baseFilesDir, slotId);
    this.dropSlots([slotId], 'removeAccountAndData');
    for (const dir of [dirs.databaseDirectory, dirs.filesDirectory]) {
      try {
        if (fs.accessSync(dir)) {
          fs.rmdirSync(dir);
        }
      } catch (caught) {
        // 条目已经摘掉，数据删不掉只是留了一坨占空间的文件，不该让整个操作失败。
        logE(`AccountRegistry.removeAccountAndData rmdir ${dir} failed: ${caught}`);
      }
    }
    return true;
  }

  private persist(): void {
    if (this.store === null) { return; }
    try {
      this.store.putSync(KEY_ACTIVE_SLOT, this.activeSlot);
      this.store.putSync(KEY_ACCOUNTS_JSON, JSON.stringify(this.accounts));
      this.store.flushSync();
    } catch (caught) {
      logE(`AccountRegistry.persist failed: ${caught}`);
    }
  }

  private bumpRegistryEpoch(): void {
    const previous = AppStorage.get<number>(TD_ACCOUNT_REGISTRY_EPOCH) ?? 0;
    AppStorage.setOrCreate(TD_ACCOUNT_REGISTRY_EPOCH, previous + 1);
  }
}

export const accountRegistry: AccountRegistry = new AccountRegistry();
