import { MentionItem } from '../../store/InputSuggestions';
import { mentionQueryOf } from '../../util/mentionDraft';

export interface SearchSenderHost {
  chatId: () => number;
  enabled: () => boolean;
  find: (chatId: number, query: string) => Promise<MentionItem[]>;
}

@ObservedV2
export class SearchSenderSuggestions {
  @Trace open: boolean = false;
  @Trace loading: boolean = false;
  @Trace items: MentionItem[] = [];
  private seq: number = 0;
  private timer: number = -1;
  private host: SearchSenderHost | null = null;

  bind(host: SearchSenderHost): void { this.host = host; }

  update(value: string): void {
    this.clear();
    const query: string | null = mentionQueryOf(value);
    const host: SearchSenderHost | null = this.host;
    if (query === null || host === null || !host.enabled()) { return; }
    const seq: number = this.seq;
    const chatId: number = host.chatId();
    this.open = true;
    this.loading = true;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (seq !== this.seq || !host.enabled() || host.chatId() !== chatId) { return; }
      host.find(chatId, query).then((items: MentionItem[]): void => {
        if (seq !== this.seq || !host.enabled() || host.chatId() !== chatId) { return; }
        this.items = items.filter((item: MentionItem): boolean => item.userId > 0);
        this.loading = false;
      }).catch((): void => {
        if (seq !== this.seq || !host.enabled() || host.chatId() !== chatId) { return; }
        this.items = [];
        this.loading = false;
      });
    }, 180);
  }

  clear(): void {
    this.seq++;
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    this.open = false;
    this.loading = false;
    this.items = [];
  }
}
