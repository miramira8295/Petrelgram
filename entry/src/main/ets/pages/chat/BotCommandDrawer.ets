import { CommandSuggestionState } from './ComposerSuggestionState';
import { EmojiDrawerState } from './EmojiDrawerState';
import { SuggestionPanel } from './SuggestionPanel';
import { CommandItem } from '../../store/InputSuggestions';

// Geometry comes from the existing bottom-drawer animation. Command arrival
// changes only the list contents, never the viewport or the reserved height.
@ComponentV2
export struct BotCommandDrawer {
  @Require @Param command: CommandSuggestionState;
  @Require @Param drawer: EmojiDrawerState;
  @Param cardHeight: number = 260;
  @Param appDark: boolean = false;
  @Event onPick: (item: CommandItem) => void = (_item: CommandItem): void => {};
  @Event onFill: (item: CommandItem) => void = (_item: CommandItem): void => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      SuggestionPanel({
        commandMode: true, commands: this.command.commandItems, mentions: [],
        loadState: this.command.commandLoadState, loadError: this.command.commandLoadError,
        catalogSize: this.command.catalogSize(), appDark: this.appDark,
        drawerHeight: Math.max(1, this.cardHeight),
        onPickCommand: this.onPick, onFillCommand: this.onFill,
        onRetryCommands: (): void => { this.command.ensureCommandsLoaded(true); }
      })
        .translate({ y: this.drawer.cardOffsetY })
        .opacity(this.drawer.cardOpacity)
        .enabled(this.command.commandMenuOpen && !this.drawer.closingToIme);
    }
    .width('100%')
    .height(Math.max(0, this.drawer.shellHeight))
    .clip(true);
  }
}
