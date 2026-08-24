import testNapi from 'libentry.so';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TdClient } from './TdClient';
import { AuthService, AuthStage } from './AuthService';
import { UserStore } from '../store/UserStore';
import { ChatStore } from '../store/ChatStore';
import { ChatEntry } from '../store/ChatEntry';
import { FileService } from '../services/FileService';
import { FolderStore } from '../store/FolderStore';
import { UnreadCountStore } from '../store/UnreadCountStore';
import { ChatThemeStore } from '../store/ChatThemeStore';
import { AccentColorStore } from '../store/AccentColorStore';
import { CallSession, setCallLibraryVersions } from '../services/CallSession';
import { NativeCallMedia, nativeCallVersionsJson } from '../services/NativeCallMedia';
import { NotificationService } from '../services/NotificationService';
import { SystemNotificationPublisher } from '../services/SystemNotificationPublisher';
import { registerMessageSyncWork } from '../services/MessageSyncWork';
import { WebPushConfig, registerWebPush, validateWebPushConfig } from '../services/WebPushRegistration';
import { ensureHmsPushRegistered } from '../services/HmsRelayRegistration';
import { resetScopeMute } from '../store/ScopeMuteStore';
import {
  KEY_WEBPUSH_AUTH, KEY_WEBPUSH_ENABLED, KEY_WEBPUSH_ENDPOINT, KEY_WEBPUSH_P256DH
} from '../store/AppSettings';
import { StoryStore } from '../store/StoryStore';
import { systemCallUi } from '../services/SystemCallUi';
import { common } from '@kit.AbilityKit';
import { TdObject, TdRequest } from './TdTypes';
import {
  accountRegistry, TD_ACCOUNT_SWITCHING, TD_SESSION_EPOCH,
  TdAccountDirectories, TdAccountSummary
} from './AccountRegistry';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

let client: TdClient | undefined = undefined;
let auth: AuthService | undefined = undefined;
let users: UserStore | undefined = undefined;
let chats: ChatStore | undefined = undefined;
let files: FileService | undefined = undefined;
let folders: FolderStore | undefined = undefined;
let unread: UnreadCountStore | undefined = undefined;
let chatThemes: ChatThemeStore | undefined = undefined;
let accentColors: AccentColorStore | undefined = undefined;
let callSession: CallSession | undefined = undefined;
let storyStore: StoryStore | undefined = undefined;
let notifications: NotificationService | undefined = undefined;
let appBundleName: string = '';
let baseFilesDir: string = '';
let activeTdFilesDirectory: string = '';
let switchInFlight: Promise<void> | null = null;
let desiredOnline: boolean = false;
let runtimeReady: boolean = false;

export function initTdKit(context: common.Context): void {
  if (client !== undefined) {
    return;
  }
  baseFilesDir = context.filesDir;
  appBundleName = context.applicationInfo.name;
  accountRegistry.init(context);
  // 上次在登录页被杀掉的「加账号」流程会留下一个空的 active 槽位，重开 app
  // 就只剩登录页、原账号再也进不去。建运行时之前先把它交还给来源账号。
  const recovered: string = accountRegistry.abandonStalePending();
  if (recovered !== '') {
    logE(`Globals: abandoned a stale pending login, back to slot ${recovered}`);
  }
  createRuntime(accountRegistry.activeSlotId());
}

// TDLib expects <files>/temp to be its download scratch DIRECTORY. On one
// device a 1.9MB regular file appeared at exactly that path during first
// login, and from then on every download failed with ENOTDIR ("Not a
// directory") — images never loaded again for that account. Whatever wrote
// it, the repair is the same: clear anything that occupies the path as a
// plain file before TDLib initializes, so it can mkdir its scratch space.
function repairTdTempDirectory(filesDirectory: string): void {
  const tempPath = `${filesDirectory}/temp`;
  try {
    if (fs.accessSync(tempPath) && !fs.statSync(tempPath).isDirectory()) {
      fs.unlinkSync(tempPath);
      logE(`Globals: removed a plain file squatting on ${tempPath}`);
    }
  } catch (e) {
    logE(`Globals.repairTdTempDirectory failed: ${e}`);
  }
}

type RuntimeStopMode = 'close' | 'destroy';

function createRuntime(slotId: string): void {
  runtimeReady = false;
  const directories: TdAccountDirectories = accountRegistry.directories(baseFilesDir, slotId);
  activeTdFilesDirectory = directories.filesDirectory;
  repairTdTempDirectory(directories.filesDirectory);
  client = new TdClient({ init: testNapi.tdInit, send: testNapi.tdSend });
  trackConnectionState(client);
  auth = new AuthService(client, directories.databaseDirectory, directories.filesDirectory);
  users = new UserStore(client);
  chats = new ChatStore(client, users);
  files = new FileService(client, chats);
  folders = new FolderStore(client);
  unread = new UnreadCountStore(client);
  chatThemes = new ChatThemeStore(client);
  accentColors = new AccentColorStore(client);
  try {
    setCallLibraryVersions(JSON.parse(nativeCallVersionsJson()) as string[]);
  } catch (e) {
    logE('call versions parse failed, using fallback list');
  }
  callSession = new CallSession(client, users, new NativeCallMedia());
  // 系统来电界面上的接听/拒接/挂断/静音回传到通话会话。
  const session = callSession;
  systemCallUi.bindActions({
    accept: (): void => session.accept(),
    decline: (): void => session.decline(),
    hangup: (): void => session.hangup(),
    setMuted: (muted: boolean): void => session.setMuted(muted)
  });
  storyStore = new StoryStore(client);
  // 本地通知：应用后台但进程存活时，新消息/来电经系统通知触达。
  if (notifications !== undefined) {
    notifications.close();
  }
  notifications = new NotificationService(
    client, chats, new SystemNotificationPublisher(appBundleName, 'EntryAbility'),
    (): boolean => AppStorage.get<boolean>('appIsForeground') ?? true);
  notifications.attachSenderSources(users, files);
  notifications.attachCallSession(callSession);
  const fileService = files;
  const chatStore = chats;
  // Request avatars for EVERY cached chat, not just the main list — otherwise
  // chats surfaced only under a folder tab never get their photo downloaded.
  chatStore.subscribe(() => {
    for (const e of chatStore.allEntries()) {
      if (e.photoFileId !== 0 && e.avatarPath === '') {
        fileService.requestAvatar(e.id, e.photoFileId);
      }
    }
  });
  const runtimeClient = client;
  const runtimeAuth = auth;
  runtimeAuth.onStageChange((stage: AuthStage): void => {
    if (stage === AuthStage.Ready && client === runtimeClient && auth === runtimeAuth) {
      runtimeReady = true;
      registerMessageSyncWork(appBundleName);
      notifications!.enable();
      reregisterWebPush(runtimeClient);
      storyStore!.open();
      applyDesiredOnlineState(runtimeClient);
      refreshActiveAccountSummary(runtimeClient);
    } else if (client === runtimeClient && auth === runtimeAuth && stage !== AuthStage.Init) {
      runtimeReady = false;
    }
  });
  try {
    client.start();
  } catch (caught) {
    const startError = caught as Error;
    // A native receiver-thread allocation failure is reported as an ArkTS
    // exception. Tear down the half-built runtime so account switching can
    // retry or restore the previous slot instead of retaining unusable stores.
    notifications?.close();
    notifications = undefined;
    callSession?.close();
    callSession = undefined;
    auth.dispose();
    client.dispose();
    client = undefined;
    auth = undefined;
    users = undefined;
    chats = undefined;
    files = undefined;
    folders = undefined;
    unread = undefined;
    chatThemes = undefined;
    accentColors = undefined;
    storyStore = undefined;
    try {
      testNapi.tdDestroy();
    } catch (_cleanupError) {
      // Preserve the original startup error; it names the failed resource.
    }
    throw startError;
  }
}

// --- 连接状态 --------------------------------------------------------------
//
// updateConnectionState 是一次性推送，订阅晚了就再也收不到当前值。登录页
// 挂载的时机恰好在这些更新之间，所以这里在建 client 时就订阅并缓存，页面按
// 需读取即可（AuthService.onStageChange 的回放思路）。

let connectionState: string = '';

function trackConnectionState(target: TdClient): void {
  connectionState = '';
  target.onUpdate('updateConnectionState', (u: TdObject): void => {
    const state = u['state'] as TdObject | undefined;
    connectionState = (state?.['@type'] as string | undefined) ?? '';
  });
}

export function getConnectionState(): string {
  return connectionState;
}

// 连上了才发得出请求。冷启动时 DC 握手要几百毫秒到几秒（走代理更久），这段
// 时间里发出去的 setAuthenticationPhoneNumber / requestQrCodeAuthentication
// 只会挂到 TdClient 的 15 秒超时然后报错 —— 用户实测"先去选个区域再点就好"，
// 选区域真正做的事就是把这段时间等过去。
//
// connectionStateUpdating 也算连上了：那是在拉更新，请求照发不误。
export function waitForConnection(timeoutMs: number = 20000): Promise<boolean> {
  if (connectionState === 'connectionStateReady' || connectionState === 'connectionStateUpdating') {
    return Promise.resolve(true);
  }
  return new Promise<boolean>((resolve: (ok: boolean) => void): void => {
    const startedAt: number = Date.now();
    const tick = (): void => {
      if (connectionState === 'connectionStateReady' ||
        connectionState === 'connectionStateUpdating') {
        resolve(true);
        return;
      }
      if (Date.now() - startedAt >= timeoutMs) {
        resolve(false); // 等不到也放行：宁可让 TDLib 自己报错，也别把用户卡死
        return;
      }
      setTimeout(tick, 200);
    };
    setTimeout(tick, 200);
  });
}

// device token 是按账号注册的：切账号或重启后都要对当前账号重新注册一次，
// 否则新账号根本没订阅，用户却看到开关是开着的。
function reregisterWebPush(client: TdClient): void {
  // **先试华为通道，再回到已保存的配置。**
  //
  // 顺序是有意的：能取到设备 token 就说明这台机器装的是我们自己签的包，华为
  // 通道对它可用，那条路由系统弹通知、应用被杀也能到，体验优于 MeoW。取不到就
  // 什么都不做（未签名包必然如此），照旧走下面已保存的那份配置。
  //
  // 不 await：这里在 AuthStage.Ready 的回调里，登录流程不该等一次网络往返。
  // ensureHmsPushRegistered 内部全程静默失败，不会把异常漏出来。
  ensureHmsPushRegistered(client).then((ok: boolean): void => {
    if (ok) {
      return;
    }
    reregisterStoredWebPush(client);
  }).catch((e: Object): void => {
    logE(`HMS push registration threw: ${JSON.stringify(e)}`);
    reregisterStoredWebPush(client);
  });
}

// 用已保存的三元组重新向 Telegram 注册。华为通道走不通时的原有行为，一行未改。
function reregisterStoredWebPush(client: TdClient): void {
  if (!(AppStorage.get<boolean>(KEY_WEBPUSH_ENABLED) ?? false)) {
    return;
  }
  const config: WebPushConfig = {
    endpoint: AppStorage.get<string>(KEY_WEBPUSH_ENDPOINT) ?? '',
    p256dh: AppStorage.get<string>(KEY_WEBPUSH_P256DH) ?? '',
    auth: AppStorage.get<string>(KEY_WEBPUSH_AUTH) ?? ''
  };
  if (!validateWebPushConfig(config).valid) {
    return;
  }
  registerWebPush(client, config).then((receiverId: string): void => {
    logI(`WebPush re-registered, receiver id ${receiverId}`);
  }).catch((e: Object): void => {
    logE(`WebPush re-register failed: ${JSON.stringify(e)}`);
  });
}

// 停掉当前运行时。
//
// mode 决定**本地数据的去留**，这是两者唯一但要命的区别：
//   'close'   只关库，binlog 原样留着 —— 账号切换要的就是这个，切回来还能用。
//   'destroy' 删掉本地授权数据 —— 只有卡在扫码授权态、必须从零重来时才用
//             （见 util/authError.ets 的 needsAuthorizationReset）。
async function stopRuntime(mode: RuntimeStopMode): Promise<void> {
  const currentAuth = auth;
  const currentClient = client;
  const currentReady = runtimeReady;
  runtimeReady = false;
  if (currentClient !== undefined && currentReady) {
    try {
      await sendOnlineOption(currentClient, false);
    } catch (caught) {
      const error = caught as Error;
      logE(`Globals.stopRuntime set offline failed: ${error.message}`);
    }
  }
  if (currentAuth !== undefined) {
    if (mode === 'destroy') {
      await currentAuth.destroyAuthorization();
    } else {
      await currentAuth.closeDatabase();
    }
    currentAuth.dispose();
  }
  currentClient?.dispose();
  try {
    testNapi.tdDestroy();
  } catch (caught) {
    logE(`Globals.stopRuntime tdDestroy failed: ${caught}`);
  }
  client = undefined;
  auth = undefined;
  users = undefined;
  chats = undefined;
  files = undefined;
  folders = undefined;
  unread = undefined;
  // 分类默认静音是**按账号**的：上一个账号把频道整类静音了，新账号未必。
  // 它住在模块级的 Map 里，不随运行时一起销毁，必须显式清。
  resetScopeMute();
}

function sendOnlineOption(runtimeClient: TdClient, online: boolean): Promise<void> {
  const request: TdRequest = { '@type': 'setOption' };
  request['name'] = 'online';
  request['value'] = {
    '@type': 'optionValueBoolean',
    'value': online
  } as TdObject;
  return runtimeClient.send(request).then((): void => {});
}

function applyDesiredOnlineState(runtimeClient: TdClient): void {
  const target = desiredOnline;
  sendOnlineOption(runtimeClient, target).catch((caught: Error): void => {
    if (client !== runtimeClient) {
      return;
    }
    logE(`Globals.setOnline(${target}) failed: ${caught.message}`);
  });
}

export function setTdOnlineState(online: boolean): void {
  desiredOnline = online;
  const runtimeClient = client;
  if (runtimeClient === undefined || !runtimeReady) {
    return;
  }
  applyDesiredOnlineState(runtimeClient);
}

function bumpSessionEpoch(): void {
  const previous = AppStorage.get<number>(TD_SESSION_EPOCH) ?? 0;
  AppStorage.setOrCreate(TD_SESSION_EPOCH, previous + 1);
}

async function restartOnSlot(slotId: string, previousSlotId: string): Promise<void> {
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  try {
    await stopRuntime('close');
    createRuntime(slotId);
    bumpSessionEpoch();
  } catch (caught) {
    const error = caught as Error;
    logE(`Globals.restartOnSlot(${slotId}) failed: ${error.message}`);
    if (previousSlotId !== '' && accountRegistry.hasSlot(previousSlotId)) {
      accountRegistry.setActive(previousSlotId);
      if (client === undefined) {
        createRuntime(previousSlotId);
        bumpSessionEpoch();
      }
    }
    throw error;
  } finally {
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  }
}

// 卡在扫码授权态时，把本地授权数据清掉、在**同一个账号槽**上重建运行时。
//
// 为什么需要这个：TDLib 把扫码授权态持久化在 binlog 里，冷启动会原样恢复，
// setAuthenticationPhoneNumber 从此被永久拒绝——用户再也用不了手机号登录，
// 只能去系统设置里清除应用数据。判定条件与实证见 util/authError.ets 的
// needsAuthorizationReset，那里说明了为什么必须两个条件同时成立才动手。
//
// **复用账号切换那把锁（switchInFlight）**：两者都要拆掉再重建整个运行时，
// 同时跑会让 client / auth / 各 store 互相踩。切换在途时直接让出——用户此刻
// 在切账号，登录页的这次重置没有意义。
//
// 槽位不变：这不是换账号，是把当前这个还没登录成功的槽从头来过。
export function resetAuthorizationForPhoneLogin(): Promise<void> {
  if (switchInFlight !== null) {
    return switchInFlight;
  }
  const slotId = accountRegistry.activeSlotId();
  switchInFlight = restartWithDestroy(slotId).finally((): void => {
    switchInFlight = null;
  });
  return switchInFlight;
}

async function restartWithDestroy(slotId: string): Promise<void> {
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  try {
    await stopRuntime('destroy');
    createRuntime(slotId);
    bumpSessionEpoch();
  } catch (caught) {
    const error = caught as Error;
    logE(`Globals.restartWithDestroy(${slotId}) failed: ${error.message}`);
    // 重建失败时至少把运行时拉起来，否则应用停在一个没有 client 的状态上，
    // 连登录页都不工作。槽位不变，失败的是这一次重置而不是账号本身。
    if (client === undefined) {
      createRuntime(slotId);
      bumpSessionEpoch();
    }
    throw error;
  } finally {
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  }
}

export function switchTdAccount(slotId: string): Promise<void> {
  if (!accountRegistry.hasSlot(slotId) || slotId === accountRegistry.activeSlotId()) {
    return Promise.resolve();
  }
  if (switchInFlight !== null) { return switchInFlight; }
  const previousSlotId = accountRegistry.activeSlotId();
  accountRegistry.setActive(slotId);
  switchInFlight = restartOnSlot(slotId, previousSlotId).finally((): void => {
    switchInFlight = null;
  });
  return switchInFlight;
}

export function addTdAccount(): Promise<void> {
  if (switchInFlight !== null) { return switchInFlight; }
  const previousSlotId = accountRegistry.activeSlotId();
  const account = accountRegistry.addPendingAccount();
  switchInFlight = restartOnSlot(account.slotId, previousSlotId).finally((): void => {
    switchInFlight = null;
  });
  return switchInFlight;
}

export function returnToPreviousTdAccount(): Promise<void> {
  if (switchInFlight !== null) {
    const pendingSwitch = switchInFlight;
    return pendingSwitch.then((): Promise<void> => returnToPreviousTdAccount());
  }
  const pendingSlotId = accountRegistry.activeSlotId();
  const previousSlotId = accountRegistry.previousSlotForActivePending();
  if (previousSlotId === '') { return Promise.resolve(); }
  return switchTdAccount(previousSlotId).then((): void => {
    accountRegistry.discardPending(pendingSlotId);
  });
}

export function canReturnToPreviousTdAccount(): boolean {
  return accountRegistry.previousSlotForActivePending() !== '';
}

export function logoutCurrentTdAccount(): Promise<void> {
  if (switchInFlight !== null) { return switchInFlight; }
  const currentSlotId = accountRegistry.activeSlotId();
  const fallback = accountRegistry.all().find(
    (account: TdAccountSummary): boolean =>
      account.slotId !== currentSlotId && !account.pendingLogin && account.userId !== 0
  );
  const currentAuth = auth;
  if (currentAuth === undefined) {
    return Promise.reject(new Error(str('gl_account_not_ready')));
  }
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  switchInFlight = currentAuth.logOut().then(async (): Promise<void> => {
    // Hide the logged-out session immediately. If the app is killed while the
    // next runtime is starting, it won't reappear as a usable account.
    accountRegistry.markLoggedOut(currentSlotId);
    if (fallback !== undefined) {
      accountRegistry.setActive(fallback.slotId);
      await restartOnSlot(fallback.slotId, currentSlotId);
      accountRegistry.removeAccount(currentSlotId);
    } else {
      // Recreate TDLib on the same (now logged-out) database so it emits
      // authorizationStateWaitPhoneNumber and the UI returns to login.
      await restartOnSlot(currentSlotId, currentSlotId);
    }
  }).finally((): void => {
    switchInFlight = null;
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  });
  return switchInFlight;
}

export function getTdAccounts(): TdAccountSummary[] {
  return accountRegistry.all();
}

export function removeDuplicateTdAccountsForActive(): number {
  return accountRegistry.removeDuplicatesForActive();
}

export function getActiveTdAccountSlot(): string {
  return accountRegistry.activeSlotId();
}

export function getTdFilesDirectory(): string {
  return activeTdFilesDirectory;
}

export function updateActiveTdAccountProfile(
  userId: number, name: string, phone: string, username: string, avatarPath: string
): void {
  accountRegistry.updateActiveProfile(userId, name, phone, username, avatarPath);
}

function refreshActiveAccountSummary(runtimeClient: TdClient): void {
  const slotBeforeRequest = accountRegistry.active();
  const request: TdRequest = { '@type': 'getMe' };
  runtimeClient.send(request).then((me: TdObject): void => {
    if (client !== runtimeClient) { return; }
    const firstName = (me['first_name'] as string | undefined) ?? '';
    const lastName = (me['last_name'] as string | undefined) ?? '';
    const name = `${firstName} ${lastName}`.trim();
    const phone = (me['phone_number'] as string | undefined) ?? '';
    const usernames = me['usernames'] as TdObject | undefined;
    const activeUsernames =
      (usernames?.['active_usernames'] as string[] | undefined) ?? [];
    const profilePhoto = me['profile_photo'] as TdObject | undefined;
    const small = profilePhoto?.['small'] as TdObject | undefined;
    const local = small?.['local'] as TdObject | undefined;
    const avatarPath = (local?.['path'] as string | undefined) ?? '';
    const userId = (me['id'] as number | undefined) ?? 0;
    const duplicateSlotId = slotBeforeRequest.pendingLogin
      ? accountRegistry.findOtherLoggedInSlot(userId, slotBeforeRequest.slotId)
      : '';
    if (duplicateSlotId !== '' &&
      accountRegistry.activeSlotId() === slotBeforeRequest.slotId &&
      auth !== undefined) {
      resolveDuplicateAccountLogin(
        slotBeforeRequest.slotId,
        duplicateSlotId,
        runtimeClient,
        auth,
        userId,
        name,
        phone,
        activeUsernames.length > 0 ? activeUsernames[0] : '',
        avatarPath
      );
      return;
    }
    accountRegistry.updateActiveProfile(
      userId,
      name,
      phone,
      activeUsernames.length > 0 ? activeUsernames[0] : '',
      avatarPath
    );
  }).catch((caught: Error): void => {
    logE(`Globals.refreshActiveAccountSummary failed: ${caught.message}`);
  });
}

function resolveDuplicateAccountLogin(
  duplicateSlotId: string,
  existingSlotId: string,
  runtimeClient: TdClient,
  runtimeAuth: AuthService,
  userId: number,
  name: string,
  phone: string,
  username: string,
  avatarPath: string
): void {
  if (switchInFlight !== null) {
    const pendingSwitch = switchInFlight;
    pendingSwitch.then((): void => {
      resolveDuplicateAccountLogin(
        duplicateSlotId, existingSlotId, runtimeClient, runtimeAuth,
        userId, name, phone, username, avatarPath
      );
    }).catch((caught: Error): void => {
      logE(`Globals.resolveDuplicateAccountLogin wait failed: ${caught.message}`);
    });
    return;
  }
  if (client !== runtimeClient || auth !== runtimeAuth ||
    accountRegistry.activeSlotId() !== duplicateSlotId) {
    return;
  }
  let logoutCompleted: boolean = false;
  AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, true);
  switchInFlight = runtimeAuth.logOut().then(async (): Promise<void> => {
    logoutCompleted = true;
    accountRegistry.markLoggedOut(duplicateSlotId);
    accountRegistry.setActive(existingSlotId);
    await restartOnSlot(existingSlotId, duplicateSlotId);
    accountRegistry.removeAccount(duplicateSlotId);
  }).catch((caught: Error): void => {
    logE(`Globals.resolveDuplicateAccountLogin failed: ${caught.message}`);
    if (!logoutCompleted && client === runtimeClient &&
      accountRegistry.activeSlotId() === duplicateSlotId) {
      // Keep the freshly authenticated runtime usable if Telegram rejected
      // the cleanup request; it can be resolved manually from Devices.
      accountRegistry.updateActiveProfile(userId, name, phone, username, avatarPath);
    }
  }).finally((): void => {
    switchInFlight = null;
    AppStorage.setOrCreate(TD_ACCOUNT_SWITCHING, false);
  });
}

export function isReady(): boolean {
  return client !== undefined;
}

export function getTdClient(): TdClient {
  return client!;
}

export function getAuthService(): AuthService {
  return auth!;
}

export function getChatStore(): ChatStore {
  return chats!;
}

export function getFileService(): FileService {
  return files!;
}

export function getFolderStore(): FolderStore {
  return folders!;
}

export function getUnreadCountStore(): UnreadCountStore {
  return unread!;
}

export function getUserStore(): UserStore {
  return users!;
}

export function getChatThemeStore(): ChatThemeStore {
  return chatThemes!;
}

export function getAccentColorStore(): AccentColorStore {
  return accentColors!;
}

export function getCallSession(): CallSession {
  return callSession!;
}

export function getStoryStore(): StoryStore {
  return storyStore!;
}

// 供无 UI 上下文的服务（后台任务申请等）使用；EntryAbility 启动时写入。
let uiAbilityContext: common.UIAbilityContext | null = null;

export function setUiAbilityContext(context: common.UIAbilityContext): void {
  uiAbilityContext = context;
}

export function getUiAbilityContext(): common.UIAbilityContext | null {
  return uiAbilityContext;
}

// 当前账号自己的 user id。「保存消息」要往它对应的私聊（Saved Messages）里
// 转发——Telegram 里"收藏"就是和自己的会话，chat_id 等于自己的 user id。
// 0 表示还没拿到（getMe 未回），调用方据此退化。
export function getActiveTdUserId(): number {
  return accountRegistry.active().userId;
}
