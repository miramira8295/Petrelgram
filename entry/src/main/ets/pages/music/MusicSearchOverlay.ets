import { MusicTrack, musicTrackKey } from '../../util/musicTrackModel';
import {
  musicGlassBlur, musicGlassFill, musicSheetBlur
} from '../../util/musicCenterStyle';
import { MUSIC_ROW_FORMAT, MusicTrackRow, musicRowKey } from './MusicTrackRow';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 搜索层（设计稿 showSearch）：盖满整页的一块毛玻璃，上面一个搜索框。
//
// 搜的是**曲库本身**，也就是全部会话里的音频消息（MusicLibraryStore 走 TDLib 的
// 全局搜索，空查询就是全部歌曲）——所以这里搜得到的不止已经加载出来的那几页。

@Component
export struct MusicSearchOverlay {
  @Prop query: string;
  @Prop tracks: MusicTrack[];
  @Prop loading: boolean;
  @Prop playingKey: string;
  @Prop playing: boolean;
  @Prop topInset: number;
  @Prop bottomInset: number;
  onQueryChange: (query: string) => void = (): void => {};
  onClose: () => void = (): void => {};
  onPlay: (index: number) => void = (): void => {};
  onLoadMore: () => void = (): void => {};

  private sectionLabel(): string {
    return this.query.trim() === ''
      ? str('mc_search_all')
      : str('mc_search_results', this.tracks.length);
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

      Row({ space: 8 }) {
        Text(this.sectionLabel()).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        if (this.loading) {
          LoadingProgress().width(14).height(14).color(COLOR_TEXT_SECONDARY);
        }
      }
      .width('100%').padding({ left: 6, right: 6, top: 18, bottom: 8 });

      if (this.tracks.length === 0 && !this.loading) {
        Text(this.query.trim() === '' ? str('mc_library_empty') : str('mc_search_empty', this.query))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
          .width('100%').padding(40);
      } else {
        List({ space: 2 }) {
          ForEach(this.tracks, (track: MusicTrack, index: number): void => {
            ListItem() {
              MusicTrackRow({
                track: track,
                index: -1,
                active: musicTrackKey(track.chatId, track.messageId) === this.playingKey,
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
        .onReachEnd((): void => { this.onLoadMore(); });
      }
    }
    .width('100%').height('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 12, bottom: this.bottomInset })
    // 搜索层盖满整页，底色必须**不透明够**才挡得住底下的曲目列表；
    // page_bg 那档在自绘玻璃下太淡，用和浮层同一份 surface 玻璃。
    .backgroundColor(musicGlassFill())
    .backdropBlur(musicSheetBlur());
  }
}
