import { musicDurationLabel, musicFormatLabel, MusicTrack, musicTrackKey } from '../../util/musicTrackModel';
import { musicCoverGradient, musicGlassBlur, musicGlassFill } from '../../util/musicCenterStyle';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import {
  cachedMusicCover, ensureMusicCover, musicCoverSource
} from '../../services/MusicCoverCache';

// 一首歌一行。播放列表、合集详情、搜索结果三处共用（设计稿里这三段行的结构一模一样，
// 只有尾部的东西不同：时长 / 删除键 / 格式徽标）。

export const MUSIC_ROW_PLAIN: string = 'plain';
export const MUSIC_ROW_REMOVE: string = 'remove';
export const MUSIC_ROW_FORMAT: string = 'format';

const COVER: number = 44;

@Component
export struct MusicTrackRow {
  @Prop track: MusicTrack;
  // -1 = 不显示序号（播放列表与搜索结果都不显示）。
  @Prop index: number;
  @Prop active: boolean;
  @Prop playing: boolean;
  @Prop trailing: string;
  onTap: () => void = (): void => {};
  onRemove: () => void = (): void => {};
  // 封面自己取：缓存在 services/MusicCoverCache，同一张专辑只发一次请求。
  @State private coverPath: string = '';

  aboutToAppear(): void {
    this.loadCover();
  }

  // 行被复用去画另一首时 @Prop 已是新值，封面必须跟着换——**不换就是串封面**。
  aboutToReuse(): void {
    this.coverPath = '';
    this.loadCover();
  }

  private loadCover(): void {
    const fileId: number = this.track.coverFileId;
    if (fileId <= 0) {
      return;
    }
    this.coverPath = cachedMusicCover(fileId);
    if (this.coverPath !== '') {
      return;
    }
    ensureMusicCover(fileId).then((path: string): void => {
      // 期间可能已经被复用去画别的歌了，认一下。
      if (path !== '' && this.track.coverFileId === fileId) {
        this.coverPath = path;
      }
    });
  }

  private metaLabel(): string {
    const artist: string = this.track.artist !== '' ? this.track.artist : str('mc_unknown_artist');
    const format: string = musicFormatLabel(this.track.mimeType, this.track.fileName);
    return format !== '' ? `${artist} · ${format}` : artist;
  }

  build() {
    Row({ space: 12 }) {
      if (this.index >= 0) {
        Text(`${this.index + 1}`)
          .width(22).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      }
      Stack() {
        Column().width(COVER).height(COVER).borderRadius(11)
          .linearGradient(musicCoverGradient(this.track));
        if (this.coverPath !== '') {
          Image(musicCoverSource(this.coverPath)).draggable(false)
            .width(COVER).height(COVER).borderRadius(11)
            .objectFit(ImageFit.Cover);
        }
        // 正在放的那一行在封面上盖一层，和设计稿一样：暗底 + 一颗喇叭。
        if (this.active) {
          Column() {
            SymbolGlyph($r(this.playing ? 'sys.symbol.speaker_wave_2' : 'sys.symbol.pause_fill'))
              .fontSize(18).fontColor([Color.White]);
          }
          .width(COVER).height(COVER).borderRadius(11)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000');
        }
      }
      .width(COVER).height(COVER);
      Column({ space: 2 }) {
        Text(this.track.title)
          .fontSize(14.5).fontWeight(FontWeight.Medium)
          .fontColor(this.active ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(this.metaLabel())
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.trailing === MUSIC_ROW_FORMAT) {
        Text(musicFormatLabel(this.track.mimeType, this.track.fileName))
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .borderRadius(7).backgroundColor(musicGlassFill());
      } else {
        Text(musicDurationLabel(this.track.durationSec))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      if (this.trailing === MUSIC_ROW_REMOVE) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(30).height(30).borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
        // 删除键自己吃掉点击，不要连带把这首歌放出来。
        .onClick((): void => { this.onRemove(); });
      }
    }
    .width('100%').padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.active ? musicGlassFill() : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => { this.onTap(); });
  }
}

// 行的身份：ForEach 的键。用曲目键而不是下标，列表变了才不会串行。
export function musicRowKey(track: MusicTrack): string {
  return musicTrackKey(track.chatId, track.messageId);
}
