import { fileIo } from '@kit.CoreFileKit';
import { TdClient } from '../tdkit/TdClient';
import { RecentChatHistory, RecentChatHistoryState, RecentChatHistoryStorage,
  emptyRecentChatHistory } from '../util/recentChatHistory';
import { logE } from '../util/log';

class HistoryFile implements RecentChatHistoryStorage {
  private path: string;
  constructor(directory: string) { this.path = `${directory}/recent-chat-history.json`; }
  read(): RecentChatHistoryState {
    return fileIo.accessSync(this.path) ? JSON.parse(fileIo.readTextSync(this.path)) as RecentChatHistoryState :
      emptyRecentChatHistory();
  }
  write(state: RecentChatHistoryState): void {
    const temp = this.path + '.tmp';
    const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, JSON.stringify(state)); fileIo.fsyncSync(file.fd); }
    finally { fileIo.closeSync(file); }
    fileIo.renameSync(temp, this.path);
  }
}

const histories: Map<TdClient, RecentChatHistory> = new Map();

export function attachRecentChatHistory(client: TdClient, directory: string): void {
  histories.set(client, new RecentChatHistory(new HistoryFile(directory)));
}

export function detachRecentChatHistory(client: TdClient): void { histories.delete(client); }

export function recentChatHistory(client: TdClient): RecentChatHistory {
  const history = histories.get(client);
  if (history === undefined) { throw new Error('recent chat history unavailable'); }
  return history;
}

// Called only for an explicit conversation open, not passive panels or foreground resume.
export function rememberOpenedChat(client: TdClient, chatId: number): void {
  const history = histories.get(client);
  if (history === undefined) { return; }
  try { history.opened(chatId); } catch (_error) { logE('Recent chat history save failed'); }
}
