import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from '../store/ChatStore';
import { logE } from '../util/log';

const AVATAR_PRIORITY: number = 1;

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

  constructor(client: TdClient, store: ChatStore) {
    this.client = client;
    this.store = store;
    client.onUpdate('updateFile', (u: TdObject) => this.onFile(u));
  }

  // 头像文件的本地路径（''=还没下完）。按 file id 直接取，不经会话条目 ——
  // 群消息通知要的是发信人头像，而发信人未必有对应的私聊会话。
  avatarPathOf(fileId: number): string {
    return this.completedPaths.get(fileId) ?? '';
  }

  // 只下载、不绑定任何会话条目。下完后 avatarPathOf 就能取到。
  prefetchAvatar(fileId: number): void {
    if (fileId === 0 || this.completedPaths.has(fileId) || this.requested.has(fileId)) {
      return;
    }
    this.avatarFiles.add(fileId);
    this.requested.add(fileId);
    this.download(fileId);
  }

  requestAvatar(chatId: number, fileId: number): void {
    if (fileId === 0) {
      return;
    }
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
    if (this.requested.has(fileId)) {
      return;
    }
    this.requested.add(fileId);
    this.download(fileId);
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
      this.applyFile(file);
    }).catch((e: TdError) => {
      logE(`FileService.downloadFile ${fileId} failed: ${e.message}`);
      this.requested.delete(fileId);
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
