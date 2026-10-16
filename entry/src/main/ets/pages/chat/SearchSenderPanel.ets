import { MentionItem } from '../../store/InputSuggestions';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { SearchSession } from './SearchSession';
import { SuggestionPanel } from './SuggestionPanel';

@ComponentV2
export struct SearchSenderPanel {
  @Require @Param search: SearchSession;

  build() {
    Column() {
      if (this.search.senders.open) {
        if (this.search.senders.loading || this.search.senders.items.length === 0) {
          Row({ space: 8 }) {
            if (this.search.senders.loading) {
              LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            }
            Text(this.search.senders.loading ? $r('app.string.cpp_loading_members') :
              $r('app.string.cpp_no_members'))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('calc(100% - 28vp)').height(48).justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface')).borderRadius(16)
          .margin({ left: 14, right: 14, bottom: 4 });
        } else {
          SuggestionPanel({
            commandMode: false, commands: [], mentions: this.search.senders.items,
            loadState: 'ready', loadError: '', catalogSize: 0,
            onPickMention: (item: MentionItem): void => { this.search.pickSender(item); }
          });
        }
      }
    }.width('100%');
  }
}
