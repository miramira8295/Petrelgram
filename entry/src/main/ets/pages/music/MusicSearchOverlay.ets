import { MusicTrack, musicTrackKey, trackKeyOf } from '../../util/musicTrackModel';
import {
  musicGlassBlur, musicGlassFill, musicSheetBlur
} from '../../util/musicCenterStyle';
import { MUSIC_ROW_FORMAT, MusicTrackRow, musicRowKey } from './MusicTrackRow';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 搜索层（设计稿 showSearch）：盖满整页的一块毛玻璃，上面一个搜索框。
//
// 搜的是**曲库本身**，也就是全部会话里的音频消息（MusicLibraryStore 走 TDLib 的
// 全局搜索，空查询就是全部歌曲）——所以这里搜得到的不止已经加载出来的那几页。
//
// 【第二段：机器人搜索】曲库只有"你的会话里出现过的"，想听的歌多半不在里面。
// 下面那一段是向内联音乐机器人查回来的（store/MusicBotSearchApi），和曲库结果
// 用同一种行，只是多一个来源标题。两段合在一个 List 里，滚动才是连续的。

// 一条会话机器人结果。只有一行文字——bot 回的就是一行，标题和歌手之间没有任何
// 分隔符，拆只能靠猜，所以原样显示。
//
// 做成组件而不是带参 @Builder：带参 builder 的形参是首次挂载时按值捕获的、
// 之后永不更新（见 pages/music/MusicPlayerParts 里那段说明），转圈状态会冻住。
@Component
struct MusicChatBotRow {
  @Prop label: string;
  @Prop fetching: boolean;

  onTap: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Text(this.label)
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      if (this.fetching) {
        LoadingProgress().width(18).height(18).color(COLOR_TEXT_SECONDARY);
      } else {
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(18).fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%').padding({ left: 6, right: 6, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => { this.onTap(); });
  }
}

@Component
export struct MusicSearchOverlay {
  @Prop query: string;
  @Prop tracks: MusicTrack[];
  @Prop loading: boolean;
  // 机器人搜来的结果（可能为空：没网、bot 解析不出来、或者这个词没命中）。
  @Prop botTracks: MusicTrack[];
  @Prop botLoading: boolean;
  @Prop botName: string;
  // 会话式机器人那一段（@music_v1bot 一类）。它的搜索**要手点**，不跟着输入跑：
  // 每搜一次都真往那个 bot 的会话里发一条 /search。
  @Prop chatBotName: string;
  @Prop chatLabels: string[];
  @Prop chatBusy: boolean;
  // '' = 没有错误。非空是已经翻译好的一句话，直接显示。
  @Prop chatError: string;
  // 正在取的那一条（下标），-1 = 没有。
  @Prop chatFetching: number;
  @Prop playingKey: string;
  @Prop playing: boolean;
  @Prop topInset: number;
  @Prop bottomInset: number;
  onQueryChange: (query: string) => void = (): void => {};
  onClose: () => void = (): void => {};
  onPlay: (index: number) => void = (): void => {};
  onPlayBot: (index: number) => void = (): void => {};
  onChatSearch: () => void = (): void => {};
  onChatPick: (index: number) => void = (): void => {};
  onLoadMore: () => void = (): void => {};

  private sectionLabel(): string {
    return this.query.trim() === ''
      ? str('mc_search_all')
      : str('mc_search_results', this.tracks.length);
  }


  // 会话机器人那一段的头：一颗要手点的搜索按钮，或者转圈，或者一句错误。
  @Builder
  chatBotBlock() {
    Column({ space: 6 }) {
      if (this.chatBusy) {
        Row({ space: 8 }) {
          LoadingProgress().width(14).height(14).color(COLOR_TEXT_SECONDARY);
          Text(str('mc_search_bot_section', this.chatBotName))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%');
      } else if (this.chatLabels.length > 0) {
        Text(str('mc_search_bot_section', this.chatBotName))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      } else {
        Column({ space: 3 }) {
          Text(str('mc_search_chatbot_action', this.chatBotName))
            .fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          Text($r('app.string.mc_search_chatbot_note'))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start).width('100%')
        .onClick((): void => { this.onChatSearch(); });
      }
      if (this.chatError !== '') {
        Text(this.chatError)
          .fontSize(12).fontColor($r('app.color.dc_warn')).width('100%');
      }
    }
    .width('100%').padding({ left: 6, right: 6, top: 18, bottom: 8 });
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18)
            .fontColor([COLOR_TEXT_SECONDARY]);
          TextInput({ text: this.query, placeholder: $r('app.string.mc_search_placeholder') })
            .layoutWeight(1).height(44)
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .padding(0)
            .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
            .enterKeyType(EnterKeyType.Search)
            .defaultFocus(true)
            .onChange((value: string): void => { this.onQueryChange(value); });
        }
        .layoutWeight(1).height(44).padding({ left: 14, right: 14 })
        .borderRadius(22)
        .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
        .border({ width: 0.5, color: $r('app.color.divider') });
        Text($r('app.string.cancel'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 4, right: 4, top: 8, bottom: 8 })
          .onClick((): void => { this.onClose(); });
      }
      .width('100%');

      // 段序（用户 2026-09-20 定）：会话机器人在最上、LyBot 在中间、曲库在最下。
      // 曲库那段的标题原来在 List 外面固定着，现在跟着段落一起进 List。
      List({ space: 2 }) {
        // ── 一、会话式机器人（手点才搜）──
        if (this.query.trim() !== '') {
          ListItem() {
            this.chatBotBlock();
          }
        }
        ForEach(this.chatLabels, (label: string, index: number): void => {
          ListItem() {
            MusicChatBotRow({
              label: label,
              fetching: this.chatFetching === index,
              onTap: (): void => { this.onChatPick(index); }
            });
          }
        }, (label: string, index: number): string => `cb_${index}_${label}`);

        // ── 二、LyBot（内联，随输入自动搜）──
        if (this.botLoading || this.botTracks.length > 0) {
          ListItem() {
            Row({ space: 8 }) {
              Text(str('mc_search_bot_section', this.botName))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              if (this.botLoading) {
                LoadingProgress().width(14).height(14).color(COLOR_TEXT_SECONDARY);
              }
            }
            .width('100%').padding({ left: 6, right: 6, top: 18, bottom: 8 });
          }
        }
        ForEach(this.botTracks, (track: MusicTrack, index: number): void => {
          ListItem() {
            MusicTrackRow({
              track: track,
              index: -1,
              active: trackKeyOf(track) === this.playingKey,
              playing: this.playing,
              trailing: MUSIC_ROW_FORMAT,
              onTap: (): void => { this.onPlayBot(index); }
            });
          }
        }, musicRowKey);

        // ── 三、曲库（你自己会话里的音频消息）──
        ListItem() {
          Row({ space: 8 }) {
            Text(this.sectionLabel()).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            if (this.loading) {
              LoadingProgress().width(14).height(14).color(COLOR_TEXT_SECONDARY);
            }
          }
          .width('100%').padding({ left: 6, right: 6, top: 18, bottom: 8 });
        }
        if (this.tracks.length === 0 && !this.loading) {
          ListItem() {
            Text(this.query.trim() === ''
              ? str('mc_library_empty') : str('mc_search_empty', this.query))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
              .width('100%').padding({ top: 16, bottom: 16 });
          }
        }
        ForEach(this.tracks, (track: MusicTrack, index: number): void => {
          ListItem() {
            MusicTrackRow({
              track: track,
              index: -1,
              active: trackKeyOf(track) === this.playingKey,
              playing: this.playing,
              trailing: MUSIC_ROW_FORMAT,
              onTap: (): void => { this.onPlay(index); }
            });
          }
        }, musicRowKey);
      }
      .width('100%').layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 只有曲库那段分页；两个机器人段都没有下一页（LyBot 的 next_offset 恒空，
      // 会话机器人那段是手点一次出一页）。曲库在最下面，到底触发正好。
      .onReachEnd((): void => { this.onLoadMore(); });
    }
    .width('100%').height('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 12, bottom: this.bottomInset })
    // 搜索层盖满整页，底色必须**不透明够**才挡得住底下的曲目列表；
    // page_bg 那档在自绘玻璃下太淡，用和浮层同一份 surface 玻璃。
    .backgroundColor(musicGlassFill())
    .backdropBlur(musicSheetBlur());
  }
}
