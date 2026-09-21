import { AudioSourceInfo } from '../../util/audioHeaderProbe';
import { MusicPlaybackSnapshot } from '../../store/MusicPlayerController';
import {
  musicBitrateLabel, musicDurationLabel, musicFormatLabel, musicSampleLabel, musicSizeLabel, MusicTrack
} from '../../util/musicTrackModel';
import { musicCoverGradient, musicGlassBlur, musicGlassFill } from '../../util/musicCenterStyle';
import { COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { musicCoverSource } from '../../services/MusicCoverCache';
import { MUSIC_INFO_CELL_RADIUS, MusicInfoCell, MusicRoundButton } from './MusicPlayerParts';

// 音乐中心的播放页（设计稿「播放」页签）。只画，不决定：曲目、播放态、音源信息都由
// MusicCenterPage 传进来，动作往回调走。
//
// 【信息格为什么是这四项】设计稿是「格式 / 码率 / 采样-位深 / 大小」。位深系统给不了，
// 自己解文件头才有，所以第三格显示「采样率」，位深解出来了就并在同一格里（96 kHz · 24bit）。
// 码率优先用文件头里的真实值，解不出来才退回「大小 ÷ 时长」的估算。

const COVER_SIZE: number = 270;

@Component
export struct MusicPlayerView {
  @Prop track: MusicTrack | null;
  @Prop snapshot: MusicPlaybackSnapshot;
  @Prop source: AudioSourceInfo;
  // 音乐中心开关：关掉时信息格、播放列表、添加到合集都收起（设计稿如此）。
  @Prop centerOn: boolean;
  @Prop castLabel: string;
  @Prop inCollection: boolean;
  // 专辑封面的本地路径；'' = 没有内嵌封面或还没取到，退回渐变色块。
  @Prop coverPath: string;
  onToggle: () => void = (): void => {};
  onPrev: () => void = (): void => {};
  onNext: () => void = (): void => {};
  onSeek: (fraction: number) => void = (): void => {};
  onOpenPlaylist: () => void = (): void => {};
  onOpenAddTo: () => void = (): void => {};
  onOpenCast: () => void = (): void => {};
  onOpenInChat: () => void = (): void => {};
  private seekWidth: number = 1;

  private progress(): number {
    const duration: number = this.snapshot.durationMs;
    return duration > 0 ? Math.min(1, this.snapshot.positionMs / duration) : 0;
  }

  private artistLabel(): string {
    const artist: string = this.track?.artist ?? '';
    return artist !== '' ? artist : str('mc_unknown_artist');
  }

  // 码率：文件头里的真实值优先，没有才用大小÷时长估。
  private bitrateLabel(): string {
    if (this.source.bitrateKbps > 0) {
      return `${this.source.bitrateKbps} kbps`;
    }
    const track: MusicTrack | null = this.track;
    return track !== null ? musicBitrateLabel(track.fileSize, track.durationSec) : '';
  }

  private sampleLabel(): string {
    const sample: string = musicSampleLabel(this.source.sampleRateHz);
    if (sample === '') {
      return '';
    }
    return this.source.bitDepth > 0 ? `${sample} · ${this.source.bitDepth}bit` : sample;
  }

  private formatLabel(): string {
    if (this.source.format !== '') {
      return this.source.format;
    }
    const track: MusicTrack | null = this.track;
    return track !== null ? musicFormatLabel(track.mimeType, track.fileName) : '';
  }

  build() {
    Column() {
      // 封面。外面这层吃掉剩余高度并把封面居中（设计稿里封面区是 flex:1），
      // 封面本身是固定的 270——两件事不能写在同一层，layoutWeight 会把定高顶掉。
      Column() {
        Stack() {
          Column()
            .width(COVER_SIZE).height(COVER_SIZE).borderRadius(28)
            .linearGradient(musicCoverGradient(this.track))
            .shadow({ radius: 30, color: '#59000000', offsetX: 0, offsetY: 18 });
          // 没在放歌时封面位给个音符（用户 2026-09-18）：一块纯灰渐变读起来像
          // 封面加载失败，放个符号才看得出"这里现在没有歌"。
          // 有歌但没内嵌封面时仍然只画彩色渐变——那是设计稿本来的样子，不动。
          if (this.track === null) {
            SymbolGlyph($r('sys.symbol.music_fill'))
              .fontSize(88).fontColor(['#59FFFFFF']);
          }
          // 真封面盖在渐变上：取不到时下面那层渐变就是兜底，不会留白洞。
          if (this.coverPath !== '') {
            Image(musicCoverSource(this.coverPath)).draggable(false)
              .width(COVER_SIZE).height(COVER_SIZE).borderRadius(28)
              .objectFit(ImageFit.Cover);
          }
          if ((this.track?.album ?? '') !== '') {
            Text(this.track?.album ?? '')
              .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#BFFFFFFF')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(COVER_SIZE - 36)
              .offset({ y: COVER_SIZE / 2 - 22 });
          }
        }
        .width(COVER_SIZE).height(COVER_SIZE);
      }
      .width('100%').layoutWeight(1)
      .constraintSize({ minHeight: 0 })
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 8 });

      // 曲名 + 歌手 + 音源徽标 + 流转
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(this.track?.title ?? str('mc_no_track'))
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(this.artistLabel())
            .fontSize(15).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start);
        // 音源徽标点一下回到那条消息——迷你条原来的「点信息区回消息」搬到了这里。
        Row({ space: 5 }) {
          Column()
            .width(6).height(6).borderRadius(3)
            .backgroundColor((this.track?.localPath ?? '') !== '' ? '#7CFF9A' : '#5DB8FF');
          Text((this.track?.localPath ?? '') !== '' ? $r('app.string.mc_source_local') : $r('app.string.mc_source_cloud'))
            .fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }
        .height(26).padding({ left: 10, right: 10 }).borderRadius(13)
        .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
        .border({ width: 0.5, color: $r('app.color.divider') })
        .enabled(this.track !== null)
        .onClick((): void => { this.onOpenInChat(); });
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.superdevice')).fontSize(13).fontColor([COLOR_TEXT_PRIMARY]);
          Text(this.castLabel).fontSize(11).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }
        .height(26).padding({ left: 10, right: 10 }).borderRadius(13)
        .backgroundColor(musicGlassFill()).backdropBlur(musicGlassBlur())
        .border({ width: 0.5, color: $r('app.color.divider') })
        .onClick((): void => { this.onOpenCast(); });
      }
      .width('100%').alignItems(VerticalAlign.Bottom);

      // 音源信息（音乐中心开关控制）
      if (this.centerOn) {
        Row({ space: 6 }) {
          MusicInfoCell({ label: $r('app.string.mc_info_format'), value: this.formatLabel() });
          MusicInfoCell({ label: $r('app.string.mc_info_bitrate'), value: this.bitrateLabel() });
          MusicInfoCell({ label: $r('app.string.mc_info_sample'), value: this.sampleLabel() });
          MusicInfoCell({
            label: $r('app.string.mc_info_size'), value: musicSizeLabel(this.track?.fileSize ?? 0)
          });
        }
        .width('100%').margin({ top: 14 });
      } else {
        Row() {
          Text($r('app.string.mc_info_off'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        }
        .width('100%').height(54).margin({ top: 14 })
        .justifyContent(FlexAlign.Center)
        .borderRadius(MUSIC_INFO_CELL_RADIUS)
        .border({ width: 1, color: $r('app.color.divider'), style: BorderStyle.Dashed });
      }

      // 进度
      Column() {
        Stack({ alignContent: Alignment.Start }) {
          Column().width('100%').height(5).borderRadius(3)
            .backgroundColor($r('app.color.surface_alt'));
          Column().width(`${this.progress() * 100}%`).height(5).borderRadius(3)
            .backgroundColor(COLOR_PRIMARY);
        }
        .width('100%').height(22)
        .onAreaChange((_old: Area, area: Area): void => {
          this.seekWidth = Math.max(1, Number(area.width));
        })
        // 按下即定位，拖动跟手：进度条只有 5vp 高，命中区靠外层 22vp 的 Stack。
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down || event.type === TouchType.Move) {
            this.onSeek(event.touches[0].x / this.seekWidth);
          }
        });
        Row() {
          Text(musicDurationLabel(Math.floor(this.snapshot.positionMs / 1000)))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          Blank();
          Text(`-${musicDurationLabel(Math.max(0, Math.floor((this.snapshot.durationMs - this.snapshot.positionMs) / 1000)))}`)
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%');
      }
      .width('100%').margin({ top: 18 });

      // 控制
      Row() {
        MusicRoundButton({
          icon: $r('sys.symbol.music_note_list'), diameter: 44, iconSize: 22, active: this.centerOn,
          onTap: (): void => { this.onOpenPlaylist(); }
        });
        MusicRoundButton({
          icon: $r('sys.symbol.backward_end_fill'), diameter: 56, iconSize: 26,
          active: this.track !== null,
          onTap: (): void => { this.onPrev(); }
        });
        Row() {
          if (this.snapshot.loading) {
            LoadingProgress().width(28).height(28).color(COLOR_ON_PRIMARY);
          } else {
            SymbolGlyph($r(this.snapshot.playing ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
              .fontSize(30).fontColor([COLOR_ON_PRIMARY]);
          }
        }
        .width(76).height(76).borderRadius(38)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(COLOR_PRIMARY)
        .shadow({ radius: 20, color: '#40000000', offsetX: 0, offsetY: 8 })
        .enabled(this.track !== null)
        .onClick((): void => { this.onToggle(); });
        MusicRoundButton({
          icon: $r('sys.symbol.forward_end_fill'), diameter: 56, iconSize: 26,
          active: this.track !== null,
          onTap: (): void => { this.onNext(); }
        });
        // 机器人搜来的歌在播放那一刻已经发进收藏夹、换成了真消息（见
        // MusicPlayerController 的 materializer），所以能加合集的曲目一定有
        // chatId/messageId，这里不再需要按来源分情况。
        MusicRoundButton({
          icon: this.inCollection
            ? $r('sys.symbol.checkmark_square_on_square') : $r('sys.symbol.plus_square_on_square'),
          diameter: 44, iconSize: 22, active: this.centerOn && this.track !== null,
          onTap: (): void => { this.onOpenAddTo(); }
        });
      }
      .width('100%').margin({ top: 12 })
      .justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Center);
    }
    .width('100%').layoutWeight(1)
    .justifyContent(FlexAlign.Start);
  }
}
