import { MusicCollection } from '../../util/musicCollectionModel';
import { musicDurationLabel, MusicTrack, musicTrackKey } from '../../util/musicTrackModel';
import { musicEmptyTileFill, musicGlassBlur, musicGlassFill, musicKeyGradient } from '../../util/musicCenterStyle';
import { MUSIC_ROW_REMOVE, MusicTrackRow, musicRowKey } from './MusicTrackRow';
import { COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 合集详情（设计稿 isDetail 那一段）：封面马赛克 + 名字 + 两颗大按钮 + 曲目卡片 + 删除。
//
// 曲目由 MusicCenterPage 解析好传进来（合集里存的是键，取歌见 services/MusicTrackResolver），
// 这里只画和回调。

const COVER: number = 120;
const TILE_GAP: number = 6;
const TILE_SIZE: number = (COVER - 16 - TILE_GAP) / 2;
const DANGER_COLOR: string = '#FF5A5A';
const DANGER_FILL: string = '#1FFF5A5A';
const DANGER_BORDER: string = '#59FF5A5A';

@Component
export struct MusicCollectionDetailView {
  @Prop collection: MusicCollection;
  @Prop tracks: MusicTrack[];
  @Prop playingKey: string;
  @Prop playing: boolean;
  @Prop loading: boolean;
  onPlayAll: () => void = (): void => {};
  onShuffle: () => void = (): void => {};
  onPlay: (index: number) => void = (): void => {};
  onRemove: (trackKey: string) => void = (): void => {};
  onDelete: () => void = (): void => {};

  private totalSeconds(): number {
    let total: number = 0;
    this.tracks.forEach((track: MusicTrack): void => { total += track.durationSec; });
    return total;
  }

  // 「3 首 · 12:04」。歌还没取回来时只报数量，不报一个会变的时长。
  private summaryLabel(): string {
    const count: number = this.collection.trackKeys.length;
    if (this.tracks.length < count) {
      return str('mc_track_count', count);
    }
    return `${str('mc_track_count', count)} · ${musicDurationLabel(this.totalSeconds())}`;
  }

  private empty(): boolean {
    return this.collection.trackKeys.length === 0;
  }

  @Builder
  actionButton(icon: string, label: ResourceStr, filled: boolean, action: () => void) {
    Row({ space: 8 }) {
      SymbolGlyph($r(icon)).fontSize(18)
        .fontColor([filled ? COLOR_ON_PRIMARY : COLOR_TEXT_PRIMARY]);
      Text(label).fontSize(14).fontWeight(FontWeight.Bold)
        .fontColor(filled ? COLOR_ON_PRIMARY : COLOR_TEXT_PRIMARY);
    }
    .layoutWeight(1).height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(filled ? COLOR_PRIMARY : musicGlassFill())
    .backdropBlur(filled ? 0 : musicGlassBlur())
    .border({ width: filled ? 0 : 0.5, color: $r('app.color.divider') })
    .opacity(this.empty() ? 0.4 : 1)
    .enabled(!this.empty())
    .onClick((): void => { action(); });
  }

  @Builder
  tile(slot: number) {
    if (slot < this.collection.trackKeys.length) {
      Column().width(TILE_SIZE).height(TILE_SIZE)
        .borderRadius(10).linearGradient(musicKeyGradient(this.collection.trackKeys[slot]));
    } else {
      Column().width(TILE_SIZE).height(TILE_SIZE)
        .borderRadius(10).backgroundColor(musicEmptyTileFill());
    }
  }

  @Builder
  coverMosaic() {
    Column({ space: TILE_GAP }) {
      Row({ space: TILE_GAP }) {
        this.tile(0);
        this.tile(1);
      }
      Row({ space: TILE_GAP }) {
        this.tile(2);
        this.tile(3);
      }
    }
    .width(COVER).height(COVER).padding(8)
    .borderRadius(24)
    .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: $r('app.color.divider') });
  }

  build() {
    Column() {
      Row({ space: 16 }) {
        this.coverMosaic();
        Column({ space: 4 }) {
          Text($r('app.string.mc_collection_label'))
            .fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.collection.name)
            .fontSize(26).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(this.summaryLabel()).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start);
      }
      .width('100%').alignItems(VerticalAlign.Bottom);

      Row({ space: 10 }) {
        this.actionButton('sys.symbol.play_fill', $r('app.string.mc_play_all'), true,
          (): void => { this.onPlayAll(); });
        this.actionButton('sys.symbol.shuffle', $r('app.string.mc_shuffle'), false,
          (): void => { this.onShuffle(); });
      }
      .width('100%').margin({ top: 18 });

      Column() {
        if (this.empty()) {
          Text($r('app.string.mc_collection_empty'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
            .padding(28).width('100%');
        } else if (this.loading && this.tracks.length === 0) {
          Row() {
            LoadingProgress().width(22).height(22).color(COLOR_TEXT_SECONDARY);
          }
          .width('100%').padding(28).justifyContent(FlexAlign.Center);
        } else {
          ForEach(this.tracks, (track: MusicTrack, index: number): void => {
            MusicTrackRow({
              track: track,
              index: index,
              active: musicTrackKey(track.chatId, track.messageId) === this.playingKey,
              playing: this.playing,
              trailing: MUSIC_ROW_REMOVE,
              onTap: (): void => { this.onPlay(index); },
              onRemove: (): void => { this.onRemove(musicTrackKey(track.chatId, track.messageId)); }
            });
          }, musicRowKey);
        }
      }
      .width('100%').margin({ top: 18 })
      .padding({ left: 4, right: 4, top: 4, bottom: 4 })
      .borderRadius(20)
      .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
      .border({ width: 0.5, color: $r('app.color.divider') });

      Text($r('app.string.mc_delete_collection'))
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(DANGER_COLOR)
        .textAlign(TextAlign.Center)
        .width('100%').height(44).margin({ top: 14 })
        .borderRadius(22)
        .backgroundColor(DANGER_FILL)
        .border({ width: 1, color: DANGER_BORDER })
        .onClick((): void => { this.onDelete(); });
    }
    .width('100%');
  }
}
