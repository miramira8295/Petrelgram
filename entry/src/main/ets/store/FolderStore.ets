import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';

export const FOLDER_TAGS_ENABLED: string = 'chatFolderTagsEnabled';

export interface FolderInfo {
  id: number;
  title: string;
  iconName: string;
  colorId: number;
  isShareable: boolean;
  hasMyInviteLinks: boolean;
}

function folderTitle(info: TdObject): string {
  const title = info['title'] as string | undefined;
  if (title !== undefined && title !== '') { return title; }
  const name = info['name'] as TdObject | undefined;
  const text = name?.['text'] as TdObject | undefined;
  return text !== undefined ? ((text['text'] as string | undefined) ?? '') : '';
}

function folderInfo(info: TdObject): FolderInfo | null {
  const id = info['id'] as number | undefined;
  if (id === undefined || id === 0) { return null; }
  const icon = info['icon'] as TdObject | undefined;
  return {
    id, title: folderTitle(info),
    iconName: (icon?.['name'] as string | undefined) ?? 'Custom',
    colorId: (info['color_id'] as number | undefined) ?? -1,
    isShareable: (info['is_shareable'] as boolean | undefined) ?? false,
    hasMyInviteLinks: (info['has_my_invite_links'] as boolean | undefined) ?? false
  };
}

export class FolderStore {
  private folders: FolderInfo[] = [];
  private listeners: Array<(folders: FolderInfo[]) => void> = [];
  private initialUpdateReceived: boolean = false;
  private mainChatListPosition: number = 0;
  private tagsEnabled: boolean = false;

  constructor(client: TdClient) {
    AppStorage.setOrCreate(FOLDER_TAGS_ENABLED, false);
    client.onUpdate('updateChatFolders', (update: TdObject): void => this.onFolders(update));
  }

  getFolders(): FolderInfo[] { return this.folders; }
  isReady(): boolean { return this.initialUpdateReceived; }
  getMainChatListPosition(): number { return this.mainChatListPosition; }
  areTagsEnabled(): boolean { return this.tagsEnabled; }

  subscribe(listener: (folders: FolderInfo[]) => void): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.folders);
    return (): void => {
      this.listeners = this.listeners.filter((item: (folders: FolderInfo[]) => void): boolean => item !== listener);
    };
  }

  private notify(): void {
    this.folders = this.folders.slice();
    for (const listener of this.listeners) { listener(this.folders); }
  }

  applyServerFolderInfo(raw: TdObject): void {
    const parsed = folderInfo(raw);
    if (parsed === null) { return; }
    const index = this.folders.findIndex((item: FolderInfo): boolean => item.id === parsed.id);
    if (index < 0) {
      this.folders = [...this.folders, parsed];
    } else {
      const next = this.folders.slice();
      next[index] = parsed;
      this.folders = next;
    }
    this.initialUpdateReceived = true;
    this.notify();
  }

  removeFolder(id: number): void {
    const next = this.folders.filter((item: FolderInfo): boolean => item.id !== id);
    if (next.length === this.folders.length) { return; }
    this.folders = next;
    this.notify();
  }

  applyLocalOrder(ids: number[], mainPosition: number): void {
    const byId = new Map<number, FolderInfo>();
    for (const folder of this.folders) { byId.set(folder.id, folder); }
    const next: FolderInfo[] = [];
    for (const id of ids) {
      const folder = byId.get(id);
      if (folder !== undefined) { next.push(folder); byId.delete(id); }
    }
    byId.forEach((folder: FolderInfo): void => { next.push(folder); });
    this.folders = next;
    this.mainChatListPosition = Math.max(0, Math.min(next.length, mainPosition));
    this.notify();
  }

  applyTagsEnabled(enabled: boolean): void {
    this.tagsEnabled = enabled;
    AppStorage.setOrCreate(FOLDER_TAGS_ENABLED, enabled);
    this.notify();
  }

  private onFolders(update: TdObject): void {
    const rows = update['chat_folders'] as TdObject[] | undefined;
    if (rows === undefined) { return; }
    const next: FolderInfo[] = [];
    for (const raw of rows) {
      const parsed = folderInfo(raw);
      if (parsed !== null) { next.push(parsed); }
    }
    this.folders = next;
    this.mainChatListPosition = (update['main_chat_list_position'] as number | undefined) ?? 0;
    this.tagsEnabled = (update['are_tags_enabled'] as boolean | undefined) ?? false;
    this.initialUpdateReceived = true;
    AppStorage.setOrCreate(FOLDER_TAGS_ENABLED, this.tagsEnabled);
    this.notify();
  }
}
