import { MusicCollection, collectionContains } from '../../util/musicCollectionModel';
import { musicDurationLabel, MusicTrack, musicTrackKey, trackKeyOf } from '../../util/musicTrackModel';
import { musicGlassBlur, musicGlassFill, musicKeyGradient } from '../../util/musicCenterStyle';
import { MUSIC_ROW_PLAIN, MusicTrackRow, musicRowKey } from './MusicTrackRow';
import { MusicSheetShell } from './MusicSheetShell';
import { COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 音乐中心的三张浮层：播放列表、添加到合集、新建合集（设计稿 showPlaylist /
// showAddTo / showCreate）。壳在 MusicSheetShell，遮罩与层序在 MusicCenterPage。

const LIST_MAX_HEIGHT: number = 420;

@Component
export struct MusicPlaylistSheet {
  @Prop tracks: MusicTrack[];
  @Prop playingKey: string;
  @Prop playing: boolean;
  @Prop bottomInset: number;
  onPlay: (index: number) => void = (): void => {};

  private summaryLabel(): string {
    let total: number = 0;
    this.tracks.forEach((track: MusicTrack): void => { total += track.durationSec; });
    return `${str('mc_track_count', this.tracks.length)} · ${musicDurationLabel(total)}`;
  }

  build() {
    MusicSheetShell({
      title: $r('app.string.mc_playlist'),
      subTitle: this.summaryLabel(),
      bottomInset: this.bottomInset
    }) {
      List({ space: 2 }) {
        ForEach(this.tracks, (track: MusicTrack, index: number): void => {
          ListItem() {
            MusicTrackRow({
              track: track,
              index: -1,
              active: trackKeyOf(track) === this.playingKey,
              playing: this.playing,
              trailing: MUSIC_ROW_PLAIN,
              onTap: (): void => { this.onPlay(index); }
            });
          }
        }, musicRowKey);
      }
      // 浮层的壳是"按内容撑高"的，所以这里不能用 layoutWeight（没有可分的剩余高度），
      // 而是照仓库里别的底部浮层那样给一个上限，由 List 自己按内容取高（ContactPickerSheet 同形）。
      .width('100%').constraintSize({ maxHeight: LIST_MAX_HEIGHT })
      .padding({ left: 12, right: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);
    }
  }
}

@Component
export struct MusicAddToSheet {
  @Prop collections: MusicCollection[];
  @Prop trackKey: string;
  @Prop trackTitle: string;
  @Prop trackArtist: string;
  @Prop bottomInset: number;
  onToggle: (collectionId: string) => void = (): void => {};
  onCreate: () => void = (): void => {};

  private subTitle(): string {
    const artist: string = this.trackArtist !== '' ? this.trackArtist : str('mc_unknown_artist');
    return `${this.trackTitle} · ${artist}`;
  }

  @Builder
  collectionRow(collection: MusicCollection) {
    Row({ space: 12 }) {
      Column().width(38).height(38).borderRadius(10)
        .linearGradient(musicKeyGradient(
          collection.trackKeys.length > 0 ? collection.trackKeys[0] : collection.id));
      Column({ space: 2 }) {
        Text(collection.name)
          .fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(str('mc_track_count', collection.trackKeys.length))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      // 勾选框：选中是实心圆 + 勾，未选是虚线描边的空圆。
      Row() {
        if (collectionContains(collection, this.trackKey)) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([COLOR_ON_PRIMARY]);
        }
      }
      .width(24).height(24).borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(collectionContains(collection, this.trackKey) ? COLOR_PRIMARY : Color.Transparent)
      .border({
        width: collectionContains(collection, this.trackKey) ? 0 : 1,
        color: $r('app.color.divider'),
        style: BorderStyle.Dashed
      });
    }
    .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(16)
    .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: $r('app.color.divider') })
    .onClick((): void => { this.onToggle(collection.id); });
  }

  build() {
    MusicSheetShell({
      title: $r('app.string.mc_add_to_collection'),
      subTitle: this.subTitle(),
      bottomInset: this.bottomInset
    }) {
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.collections, (collection: MusicCollection): void => {
            this.collectionRow(collection);
          }, (collection: MusicCollection): string => collection.id);
          Row({ space: 12 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([COLOR_TEXT_PRIMARY]);
            }
            .width(38).height(38).borderRadius(10)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(musicGlassFill());
            Text($r('app.string.mc_new_collection'))
              .fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
              .layoutWeight(1);
          }
          .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.divider'), style: BorderStyle.Dashed })
          .onClick((): void => { this.onCreate(); });
        }
        .width('100%').padding({ left: 20, right: 20 });
      }
      .width('100%').constraintSize({ maxHeight: LIST_MAX_HEIGHT })
      .scrollBar(BarState.Off)
      .align(Alignment.Top);
    }
  }
}

// 新建合集：设计稿里是屏幕中间的一张卡，不是底部浮层。
@Component
export struct MusicCreateDialog {
  // 从「添加到合集」进来时，建好会顺手把当前这首歌加进去——提示文案据此不同。
  @Prop fromAddTo: boolean;
  @Prop trackTitle: string;
  @Prop name: string;
  onNameChange: (name: string) => void = (): void => {};
  onCancel: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  private hint(): string {
    return this.fromAddTo ? str('mc_create_hint_add', this.trackTitle) : str('mc_create_hint');
  }

  build() {
    Column({ space: 4 }) {
      Text($r('app.string.mc_new_collection'))
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY).width('100%');
      Text(this.hint()).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      TextInput({ text: this.name, placeholder: $r('app.string.mc_collection_name') })
        .width('100%').height(46).margin({ top: 12 })
        .borderRadius(14)
        .backgroundColor(musicGlassFill())
        .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
        .maxLength(40)
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string): void => { this.onNameChange(value); })
        .onSubmit((): void => { this.onConfirm(); });
      Row({ space: 10 }) {
        Text($r('app.string.cancel'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .layoutWeight(1).height(46).borderRadius(14)
          .backgroundColor(musicGlassFill())
          .border({ width: 0.5, color: $r('app.color.divider') })
          .onClick((): void => { this.onCancel(); });
        Text($r('app.string.mc_create'))
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_ON_PRIMARY)
          .textAlign(TextAlign.Center)
          .layoutWeight(1).height(46).borderRadius(14)
          .backgroundColor(COLOR_PRIMARY)
          .opacity(this.name.trim() === '' ? 0.4 : 1)
          .enabled(this.name.trim() !== '')
          .onClick((): void => { this.onConfirm(); });
      }
      .width('100%').margin({ top: 16 });
    }
    .width('100%').padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .borderRadius(28)
    .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start);
  }
}
