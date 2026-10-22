import { GlobalSearchStore, SearchRow } from '../../store/GlobalSearchStore';
import { getTdClient } from '../../tdkit/Globals';
import { str } from '../../util/strings';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { SearchChatRow } from './SearchResultRows';

@Component
export struct SearchChannelPicker {
  onPick: (id: number, title: string) => void = (_id: number, _title: string): void => {};
  @State private query: string = '';
  @State private rows: SearchRow[] = [];
  @State private busy: boolean = true;
  @State private failed: boolean = false;
  private store: GlobalSearchStore | null = null;
  private off: (() => void) | null = null;
  private timer: number = -1;
  aboutToAppear(): void {
    const store = new GlobalSearchStore(getTdClient()); this.store = store;
    this.off = store.subscribe((): void => {
      this.rows = (this.query.trim() === '' ? store.joinedChannels : store.results)
        .filter((row: SearchRow): boolean => row.isChannel && row.title !== '');
      this.busy = this.query.trim() === '' ? !store.joinedLoaded :
        store.searching || store.results.some((row: SearchRow): boolean => row.title === '');
      this.failed = this.query.trim() === '' ? store.joinedFailed : store.searchFailed;
    });
    store.open();
  }
  aboutToDisappear(): void {
    if (this.timer !== -1) { clearTimeout(this.timer); }
    this.off?.(); this.store?.close(); this.store = null;
  }
  private search(value: string): void {
    this.query = value;
    if (this.timer !== -1) { clearTimeout(this.timer); }
    this.rows = []; this.busy = true;
    this.store?.searchChats('');
    this.timer = setTimeout((): void => { this.timer = -1; this.store?.searchChats(value, 'channel'); }, 300);
  }
  build() {
    Column({ space: 12 }) {
      Text($r('app.string.gs_choose_channel')).fontSize(20).fontWeight(FontWeight.Bold);
      TextInput({ text: this.query, placeholder: str('gs_search_names') })
        .onChange((value: string): void => this.search(value));
      if (this.busy) { LoadingProgress().width(26).height(26).color(COLOR_PRIMARY); }
      if (this.failed) { Text($r('app.string.gs_channel_search_failed')).fontColor(COLOR_TEXT_SECONDARY); }
      List() {
        ForEach(this.rows, (row: SearchRow) => {
          ListItem() {
            SearchChatRow({ chatId: row.chatId, title: row.title, subtitle: row.subtitle,
              avatarPath: row.avatarPath, initials: row.initials, query: this.query,
              identity: row.identity });
          }.onClick((): void => this.onPick(row.chatId, row.title));
        }, (row: SearchRow): string => `${row.chatId}:${row.title}:${row.avatarPath}`);
        ListItem() {
          Text(this.rows.length === 0 && !this.busy ? str('gs_no_channels') : str('gs_public_name_limit'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).padding(16);
        }
      }.layoutWeight(1).width('100%');
    }.padding(20).width('100%').height('100%');
  }
}
