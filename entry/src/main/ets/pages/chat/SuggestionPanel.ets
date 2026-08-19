import { AvatarView } from '../chatlist/AvatarView';
import { CommandItem, MentionItem } from '../../store/InputSuggestions';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// 输入框上方的补全面板：草稿以 '/' 开头时列机器人命令，末尾是 '@' 时列群成员。
//
// 从 ChatPage 搬出来。它是"给我一份清单、告诉我点了哪一条"——12 个引用里
// 只有三个是动作（选中命令、选中成员、重试加载），其余都是清单和加载状态。
//
// 命令的抓取、过滤、去抖仍在页面：那些要碰 TDLib 和当前草稿，属于数据侧。
// 这里只负责把结果画出来。

// 命令的显示形式：/cmd 或 /cmd@bot。群里有多个机器人时后缀是必要的。
export function commandLabel(item: CommandItem): string {
  return `/${item.command}${item.botUsername !== '' ? `@${item.botUsername}` : ''}`;
}

@Component
export struct SuggestionPanel {
  // true = 列命令，false = 列 @ 成员。两者不会同时出现，共用这一块面板。
  @Prop commandMode: boolean;
  @Prop commands: CommandItem[];
  @Prop mentions: MentionItem[];
  // 'idle' | 'loading' | 'ready' | 'error'
  @Prop loadState: string;
  @Prop loadError: string;
  // catalog 的总条数，用于右上角那个计数和"没有命令 / 没有匹配"的区分。
  @Prop catalogSize: number;

  onPickCommand: (item: CommandItem) => void = (): void => {};
  onPickMention: (item: MentionItem) => void = (): void => {};
  onRetryCommands: () => void = (): void => {};

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Builder
  commandHeader() {
    Row({ space: 7 }) {
      Text('/').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
      Text($r('app.string.cp_bot_commands')).fontSize(13)
        .fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Blank().layoutWeight(1);
      if (this.loadState === 'ready' && this.catalogSize > 0) {
        Text(`${this.catalogSize}`)
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.surface_alt')).borderRadius(9);
      }
    }
    .width('100%').height(34).padding({ left: 14, right: 14 })
    .border({ width: { bottom: 0.7 }, color: $r('app.color.divider') });
  }

  @Builder
  commandList() {
    if (this.loadState === 'loading' || this.loadState === 'idle') {
      Row({ space: 9 }) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        Text($r('app.string.cp_loading_commands')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%').height(72).justifyContent(FlexAlign.Center);
    } else if (this.loadState === 'error') {
      Column({ space: 7 }) {
        Text(this.loadError !== '' ? this.loadError : $r('app.string.cp_commands_failed'))
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.settings_reload'))
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.selected_pill')).borderRadius(14)
          .onClick((): void => { this.onRetryCommands(); });
      }
      .width('100%').height(86).justifyContent(FlexAlign.Center);
    } else if (this.commands.length === 0) {
      // 区分"这个会话根本没有命令"和"有命令但没匹配上"——两种情况下用户
      // 该做的事不一样：前者别再敲了，后者继续敲。
      Column({ space: 5 }) {
        Text(this.catalogSize === 0
          ? $r('app.string.cp_no_bot_commands') : $r('app.string.cp_no_matching_commands'))
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.catalogSize === 0
          ? $r('app.string.cp_chat_no_commands') : $r('app.string.cp_keep_typing'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%').height(82).justifyContent(FlexAlign.Center);
    } else {
      List() {
        ForEach(this.commands, (it: CommandItem) => {
          ListItem() {
            Row({ space: 10 }) {
              Row() {
                Text('/').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
              }
              .width(32).height(32).borderRadius(10)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.selected_pill'));
              Column({ space: 2 }) {
                Text(commandLabel(it))
                  .fontSize(14).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                if (it.description !== '') {
                  Text(it.description).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                }
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1);
              SymbolGlyph($r('sys.symbol.paperplane'))
                .fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .alignItems(VerticalAlign.Center)
            .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
              curve: Curve.EaseOut
            })
            .onClick((): void => { this.onPickCommand(it); });
          }
        }, (it: CommandItem) => `c_${it.command}_${it.botUserId}_${it.botUsername}`);
      }
      .width('100%').constraintSize({ maxHeight: 206 })
      .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 54, endMargin: 12 });
    }
  }

  @Builder
  mentionList() {
    List() {
      ForEach(this.mentions, (it: MentionItem) => {
        ListItem() {
          Row({ space: 10 }) {
            AvatarView({
              avatarPath: '', initials: it.name.substring(0, 1).toUpperCase(),
              colorSeed: it.userId, avatarSize: 32
            });
            Text(it.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            if (it.username !== '') {
              Text(`@${it.username}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
          }
          .width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .alignItems(VerticalAlign.Center)
          .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          })
          .onClick((): void => { this.onPickMention(it); });
        }
      }, (it: MentionItem) => `m${it.userId}`);
    }
    .width('100%').constraintSize({ maxHeight: 240 })
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 54, endMargin: 12 });
  }

  build() {
    Column() {
      if (this.commandMode) {
        this.commandHeader();
        this.commandList();
      } else {
        this.mentionList();
      }
    }
    .width('calc(100% - 28vp)')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16).clip(true)
    .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 14, right: 14, bottom: 2 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}
