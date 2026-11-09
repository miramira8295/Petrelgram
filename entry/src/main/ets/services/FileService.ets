import { TdClient, TimerFns } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from '../store/ChatStore';
import { logE } from '../util/log';
import { publishAvatarFile } from '../util/avatarFileChannel';

const AVATAR_PRIORITY: number = 1;
const RETRY_DELAYS_MS: number[] = [2000, 5000, 15000];

export class FileService {
  private client: TdClient;
  private store: ChatStore;
  // A TDLib file can be reused by more than one chat. Keeping only one chat
  // here makes the last request steal the update, leaving earlier rows on
  // initials until their detail page downloads the same file again.
  private fileToChats: Map<number, Set<number>> = new Map();
  private requested: Set<number> = new Set();
  private completedPaths: Map<number, string> = new Map();
  // updateFile 是全局的（视频、图片、文档都会来），只有这里认领过的 file id
  // 才记路径 —— 否则 completedPaths 会把整个会话的媒体全存进来。
  private avatarFiles: Set<number> = new Set();
  private chatToFile: Map<number, number> = new Map();
  private prefetchedFiles: Set<number> = new Set();
  private retryTimers: Map<number, number> = new Map();
  private failures: Map<number, number> = new Map();
  private timer: TimerFns;
  private closed: boolean = false;
  private connectionReady: boolean = false;
  private offFile: () => void;
  private offAvatars: () => void;
  private offConnection: () => void;

  constructor(client: TdClient, store: ChatStore, timer?: TimerFns) {
    this.client = client;
    this.store = store;
    this.timer = timer ?? {
      setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
    this.offFile = client.onUpdate('updateFile', (u: TdObject) => this.onFile(u));
    this.offConnection = client.onUpdate('updateConnectionState', (u: TdObject): void => {
      const state = u['state'] as TdObject | undefined;
      const ready: boolean = state?.['@type'] === 'connectionStateReady';
      const recovered: boolean = ready && !this.connectionReady;
      this.connectionReady = ready;
      if (recovered) { this.retryFailedAvatars(); }
    });
    this.offAvatars = store.subscribeAvatars((ids: number[]): void => {
      for (const id of ids) { this.syncChatAvatar(id); }
    });
  }

  close(): void {
    if (this.closed) { return; }
    this.closed = true;
    this.offAvatars();
    this.offFile();
    this.offConnection();
    this.retryTimers.forEach((id: number): void => this.timer.clearTimeout(id));
    this.retryTimers.clear();
    this.failures.clear();
    this.fileToChats.clear();
    this.chatToFile.clear();
    this.requested.clear();
    this.completedPaths.clear();
    this.avatarFiles.clear();
    this.prefetchedFiles.clear();
  }

  private syncChatAvatar(chatId: number): void {
    const entry = this.store.entryOf(chatId);
    this.detachPreviousPhoto(chatId, entry?.photoFileId ?? 0);
    if (entry !== undefined && entry.photoFileId !== 0 && entry.avatarPath === '') {
      this.requestAvatar(chatId, entry.photoFileId);
    }
  }

  private detachPreviousPhoto(chatId: number, fileId: number): void {
    const previous = this.chatToFile.get(chatId);
    if (previous === undefined || previous === fileId) { return; }
    this.chatToFile.delete(chatId);
    const ids = this.fileToChats.get(previous);
    ids?.delete(chatId);
    if (ids?.size === 0) { this.fileToChats.delete(previous); }
    if (!this.hasConsumer(previous)) {
      this.cancelRetry(previous);
      this.failures.delete(previous);
    }
  }

  private hasConsumer(fileId: number): boolean {
    return this.prefetchedFiles.has(fileId) || (this.fileToChats.get(fileId)?.size ?? 0) > 0;
  }

  // 头像文件的本地路径（''=还没下完）。按 file id 直接取，不经会话条目 ——
  // 群消息通知要的是发信人头像，而发信人未必有对应的私聊会话。
  avatarPathOf(fileId: number): string {
    return this.completedPaths.get(fileId) ?? '';
  }

  // 只下载、不绑定任何会话条目。下完后 avatarPathOf 就能取到。
  prefetchAvatar(fileId: number): void {
    if (this.closed || fileId === 0) { return; }
    this.prefetchedFiles.add(fileId);
    this.avatarFiles.add(fileId);
    this.ensureDownload(fileId);
  }

  requestAvatar(chatId: number, fileId: number): void {
    if (this.closed || fileId === 0) {
      return;
    }
    this.detachPreviousPhoto(chatId, fileId);
    this.chatToFile.set(chatId, fileId);
    this.avatarFiles.add(fileId);
    let chatIds = this.fileToChats.get(fileId);
    if (chatIds === undefined) {
      chatIds = new Set<number>();
      this.fileToChats.set(fileId, chatIds);
    }
    chatIds.add(chatId);
    const completedPath = this.completedPaths.get(fileId) ?? '';
    if (completedPath !== '') {
      if (this.store.photoFileIdOf(chatId) === fileId) {
        this.store.setAvatarPath(chatId, completedPath);
      }
      return;
    }
    this.ensureDownload(fileId);
  }

  private ensureDownload(fileId: number): void {
    if (this.closed || this.completedPaths.has(fileId) || this.requested.has(fileId) ||
      this.retryTimers.has(fileId) || (this.failures.get(fileId) ?? 0) > RETRY_DELAYS_MS.length) { return; }
    this.requested.add(fileId);
    this.download(fileId);
  }

  private cancelRetry(fileId: number): void {
    const id = this.retryTimers.get(fileId);
    if (id !== undefined) {
      this.timer.clearTimeout(id);
      this.retryTimers.delete(fileId);
    }
  }

  private retryFailedAvatars(): void {
    const ids = Array.from(this.failures.keys());
    for (const id of ids) {
      this.cancelRetry(id);
      this.failures.delete(id);
      if (this.hasConsumer(id)) { this.ensureDownload(id); }
    }
  }

  private scheduleRetry(fileId: number): void {
    if (!this.hasConsumer(fileId) || this.completedPaths.has(fileId)) { return; }
    const failures = (this.failures.get(fileId) ?? 0) + 1;
    this.failures.set(fileId, failures);
    if (failures > RETRY_DELAYS_MS.length) { return; }
    this.retryTimers.set(fileId, this.timer.setTimeout((): void => {
      this.retryTimers.delete(fileId);
      if (this.hasConsumer(fileId)) { this.ensureDownload(fileId); }
    }, RETRY_DELAYS_MS[failures - 1]));
  }

  private download(fileId: number): void {
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = AVATAR_PRIORITY;
    // The response carries the file's current state. Files TDLib already
    // downloaded (e.g. small profile photos fetched during loadChats) come
    // back complete here and emit NO further updateFile, so we must apply the
    // response directly — relying on updateFile alone would miss them.
    this.client.send(req).then((file: TdObject) => {
      if (this.closed) { return; }
      this.applyFile(file);
    }).catch((e: TdError) => {
      if (this.closed) { return; }
      logE(`FileService.downloadFile ${fileId} failed: ${e.message}`);
      this.requested.delete(fileId);
      this.scheduleRetry(fileId);
    });
  }

  private onFile(update: TdObject): void {
    const file = update['file'] as TdObject | undefined;
    if (file === undefined) {
      return;
    }
    this.applyFile(file);
  }

  private applyFile(file: TdObject): void {
    if (this.closed) { return; }
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    if (!this.avatarFiles.has(id)) {
      return; // 不是我们认领的头像文件（updateFile 是全局的）
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const done = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = (local['path'] as string | undefined) ?? '';
    if (!done || path === '') {
      return;
    }
    // 路径先记下来：prefetchAvatar 拉的头像没有绑定会话，下面的循环走不到，
    // 但 avatarPathOf 得能取到它。
    this.completedPaths.set(id, path);
    this.requested.delete(id);
    this.cancelRetry(id);
    this.failures.delete(id);
    // 按 file id 发一条：prefetchAvatar 拉来的头像不绑任何会话，下面那个循环
    // 走不到，订阅方（如 @ 弹窗的 LiveUserAvatar）只能从这里知道图到了。
    publishAvatarFile(id, path);
    const chatIds = this.fileToChats.get(id);
    if (chatIds === undefined) {
      return;
    }
    for (const chatId of chatIds) {
      // Ignore a late completion from the chat's previous photo.
      if (this.store.photoFileIdOf(chatId) === id) {
        this.store.setAvatarPath(chatId, path);
      }
    }
  }
}
