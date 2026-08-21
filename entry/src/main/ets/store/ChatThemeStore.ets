import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE, logI } from '../util/log';

type ChatThemeListener = (themes: TdObject[]) => void;

// TDLib has no request for the official chat-theme list — the server pushes it
// once per connection via updateChatThemes. Cache that update for the theme
// picker and the chat page's theme-background resolver.
export class ChatThemeStore {
  private client: TdClient;
  private themes: TdObject[] = [];
  private listeners: ChatThemeListener[] = [];

  constructor(client: TdClient) {
    this.client = client;
    client.onUpdate('updateChatThemes', (update: TdObject): void => {
      this.themes = ((update['chat_themes'] as TdObject[] | undefined) ?? []).slice();
      logI(`[ChatThemeStore] updateChatThemes received: ${this.themes.length} themes`);
      const snapshot = this.themes.slice();
      for (const listener of this.listeners) { listener(snapshot); }
    });
  }

  chatThemes(): TdObject[] {
    return this.themes.slice();
  }

  // The push can predate this store (TDLib sends it during startup only when
  // it was authorized with a warm cache). getCurrentState replays the same
  // update on demand.
  ensureLoaded(): void {
    if (this.themes.length > 0) { return; }
    this.client.send({ '@type': 'getCurrentState' } as TdRequest, 20000)
      .then((state: TdObject): void => {
        const updates = (state['updates'] as TdObject[] | undefined) ?? [];
        const themesUpdate = updates.find((update: TdObject): boolean =>
          ((update['@type'] as string | undefined) ?? '') === 'updateChatThemes');
        logI(`[ChatThemeStore] getCurrentState: found=${themesUpdate !== undefined}`);
        if (themesUpdate === undefined || this.themes.length > 0) { return; }
        this.themes = ((themesUpdate['chat_themes'] as TdObject[] | undefined) ?? []).slice();
        const snapshot = this.themes.slice();
        for (const listener of this.listeners) { listener(snapshot); }
      }).catch((caught: Error): void => {
        logE(`[ChatThemeStore] getCurrentState failed: ${caught.message}`);
      });
  }

  subscribe(listener: ChatThemeListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.themes.slice());
    return (): void => {
      this.listeners = this.listeners.filter(
        (current: ChatThemeListener): boolean => current !== listener
      );
    };
  }

  async setChatTheme(chatId: number, themeName: string): Promise<void> {
    const request: TdRequest = { '@type': 'setChatTheme' };
    request['chat_id'] = chatId;
    request['theme_name'] = themeName;
    await this.client.send(request, 15000);
  }
}
