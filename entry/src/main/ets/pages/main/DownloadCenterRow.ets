import { CachedImage } from '../common/CachedImage';
import { formatDuration } from '../../store/StorageApi';
import { formatFileSize } from '../../util/formatFileSize';
import { formatTime } from '../../util/formatTime';
import { monthDay } from '../../util/intlFormat';
import { str } from '../../util/strings';
import { accentSoft, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  DC_KIND_APK, DC_KIND_AUDIO, DC_KIND_PHOTO, DC_KIND_VIDEO, DC_KIND_VOICE, DC_STATE_COMPLETE, DC_STATE_DOWNLOADING,
  DC_STATE_FAILED, DC_STATE_PARTIAL, DC_STATE_PAUSED, DC_STATE_QUEUED, DC_STATE_WAITING_NETWORK, DC_STATE_WAITING_WIFI,
  displayNameOf, etaSeconds, progressPercent
} from '../../util/downloadCenterModel';
import { dcKindLabel } from '../../util/downloadCenterLabels';
import {
  DC_ACTION_ALLOW_CELLULAR, DC_ACTION_CANCEL, DC_ACTION_DELETE, DC_ACTION_OPEN, DC_ACTION_PAUSE, DC_ACTION_RESUME,
  DC_ACTION_RETRY, DC_ACTION_SAVE, DC_ACTION_SELECT
} from '../../util/downloadCenterRows';
import { DcRowVM } from '../../util/downloadCenterRowVM';
import { posterEligible } from '../../util/videoPoster';
import { posterFor, requestPoster, subscribePoster } from '../../util/videoPosterStore';

// 下载中心卡片里的一行（2026-09-15；第四版 @ReusableV2 复用，内容走 DcRowVM 的 @Trace 原地刷新）。
// 左：批量模式的勾选圈 + 44vp 类型图标（完整的图片直接用缩略图）；
// 中：名字、「来源会话 · 大小 · 时间」；进行中的再加进度条和一行状态（速度 / 等 Wi‑Fi / 等网络 / 暂停 / 排队 / 失败），
// 已完成的前面挂「仅缓存 / 已存本地」；右：圆形操作按钮，等 Wi‑Fi 时多一个「用流量」。
// 整行点击、长按菜单挂在外面（pages/main/DownloadCenterList）；按钮只报 (itemId, 动作)。
// 必须放在 V2 父组件里：官方混用表，V1 普通组件不能包含 V2 复用组件。

const ROW_RADIUS: number = 14;
const HAIRLINE: string = '1px';
const BUTTON_SIZE: number = 34;

@ReusableV2
@ComponentV2
export struct DownloadCenterRow {
  @Require @Param row: DcRowVM;
  @Param batch: boolean = false;
  @Event onAction: (itemId: string, action: string) => void = (_itemId: string, _action: string): void => {};

  // 视频的首帧海报。DC 条目没有任何缩略图来源（preview 是文本、磁盘条目 fileId 为 0），
  // 海报是我们自己从本地文件抽的，通道按**路径**索引（util/videoPosterStore）。
  @Local private poster: string = '';
  private unsubPoster: (() => void) | null = null;
  private attachedPath: string = '';

  aboutToAppear(): void {
    this.attachPoster();
  }

  aboutToDisappear(): void {
    this.detachPoster();
  }

  // 【两条复用路径都要覆盖】本组件是 @ReusableV2：行滑出屏幕是**进复用池**而不是
  // 销毁，aboutToDisappear 根本不会来；而复用重置期间 @Monitor 又是静默的
  // （同 CachedImage 文件头记着的那条坑）。只挂 @Monitor 的后果正是用户 2026-09-16
  // 报的：「滑到底部之外再回来就没有缩略图了，刚滑进屏幕内的也没有」——行被复用时
  // 既不重挂订阅、也不再发抽帧请求。
  aboutToRecycle(): void {
    this.detachPoster();
  }

  aboutToReuse(): void {
    // @Param 已是新值；@Local poster 已被框架重置。按新路径重新播种 + 订阅。
    this.attachPoster();
  }

  // 复用换行、以及同一个 VM 原地改 path，都要重挂。
  @Monitor('row', 'row.path')
  onRowChanged(): void {
    this.attachPoster();
  }

  private attachPoster(): void {
    const eligible: boolean = posterEligible(this.row.kind, this.row.state, this.row.path);
    const path: string = eligible ? this.row.path : '';
    if (path === this.attachedPath) {
      return;
    }
    this.detachPoster();
    this.attachedPath = path;
    if (path === '') {
      this.poster = '';
      return;
    }
    this.poster = posterFor(path);
    this.unsubPoster = subscribePoster(path, (jpg: string): void => { this.poster = jpg; });
    // mtime 按**整秒**传：查看器那侧只能从 entry.date（秒）还原，两边不一致会算出
    // 两个签名、白抽两次。
    requestPoster(path, this.row.sizeBytes, Math.floor(this.row.mtime / 1000) * 1000);
  }

  private detachPoster(): void {
    if (this.unsubPoster !== null) {
      this.unsubPoster();
      this.unsubPoster = null;
    }
    this.attachedPath = '';
  }

  private done(): boolean {
    return this.row.state === DC_STATE_COMPLETE;
  }

  private waiting(): boolean {
    return this.row.state === DC_STATE_WAITING_WIFI || this.row.state === DC_STATE_WAITING_NETWORK;
  }

  private percent(): number {
    return progressPercent(this.row.downloaded, this.row.sizeBytes, this.done());
  }

  // 有真名用真名；TDLib 生成的数字名、或者没有名字的，用「类型 · 日期」。
  private title(): string {
    const named: string = displayNameOf(this.row.name);
    if (named !== '') {
      return named;
    }
    return this.row.mtime > 0
      ? `${dcKindLabel(this.row.kind)} · ${monthDay(new Date(this.row.mtime))}` : dcKindLabel(this.row.kind);
  }

  private metaText(): string {
    const parts: string[] = [];
    if (this.row.session !== '') {
      parts.push(this.row.session);
    }
    if (this.row.sizeBytes > 0) {
      parts.push(formatFileSize(this.row.sizeBytes));
    }
    if (this.done() && this.row.mtime > 0) {
      parts.push(formatTime(Math.floor(this.row.mtime / 1000), Math.floor(Date.now() / 1000)));
    }
    return parts.join(' · ');
  }

  private showBar(): boolean {
    const state: string = this.row.state;
    return state === DC_STATE_DOWNLOADING || state === DC_STATE_PAUSED || state === DC_STATE_PARTIAL || this.waiting();
  }

  private subText(): string {
    const state: string = this.row.state;
    if (state === DC_STATE_DOWNLOADING) {
      const eta: number = etaSeconds(this.row.sizeBytes, this.row.downloaded, this.row.speed);
      return eta >= 0
        ? str('dc_status_speed', formatFileSize(this.row.speed), formatDuration(eta), this.percent())
        : str('dc_status_downloading', this.percent());
    }
    if (state === DC_STATE_WAITING_WIFI) {
      return str('dc_status_waiting_wifi', this.percent());
    }
    if (state === DC_STATE_WAITING_NETWORK) {
      return str('dc_status_waiting_network', this.percent());
    }
    if (state === DC_STATE_QUEUED) {
      return str('dc_status_queued');
    }
    if (state === DC_STATE_FAILED) {
      return str('dc_status_failed');
    }
    return str('dc_status_paused', this.percent());
  }

  private subColor(): ResourceColor {
    if (this.row.state === DC_STATE_DOWNLOADING) {
      return COLOR_PRIMARY;
    }
    return this.row.state === DC_STATE_FAILED ? $r('app.color.dc_err') : COLOR_TEXT_SECONDARY;
  }

  // 类型色（设计稿），图标底是同色 13% 透明度。
  private tint(): string {
    const kind: string = this.row.kind;
    if (kind === DC_KIND_VIDEO) {
      return '#3F8FD8';
    }
    if (kind === DC_KIND_PHOTO) {
      return '#3AA66C';
    }
    if (kind === DC_KIND_AUDIO) {
      return '#8E6CD0';
    }
    if (kind === DC_KIND_VOICE) {
      return '#D98A2B';
    }
    if (kind === DC_KIND_APK) {
      return '#2FA3A3';
    }
    return '#6B7A89';
  }

  private tintSoft(): string {
    return `#22${this.tint().substring(1)}`;
  }

  private kindIcon(): Resource {
    const kind: string = this.row.kind;
    if (kind === DC_KIND_VIDEO) {
      return $r('sys.symbol.video');
    }
    if (kind === DC_KIND_PHOTO) {
      return $r('sys.symbol.picture');
    }
    if (kind === DC_KIND_AUDIO) {
      return $r('sys.symbol.music_note_list');
    }
    if (kind === DC_KIND_VOICE) {
      return $r('sys.symbol.mic');
    }
    if (kind === DC_KIND_APK) {
      return $r('sys.symbol.square_grid_2x2');
    }
    return $r('sys.symbol.doc_text');
  }

  private act(action: string): void {
    this.onAction(this.row.itemId, action);
  }

  build() {
    Column() {
      Row({ space: 11 }) {
        if (this.batch) {
          Row() {
            if (this.row.selected) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontWeight(FontWeight.Bold).fontColor([Color.White]);
            }
          }
          .width(22).height(22).borderRadius(11)
          .backgroundColor(this.row.selected ? COLOR_PRIMARY : Color.Transparent)
          .borderWidth(this.row.selected ? 0 : 1.5)
          .borderColor(COLOR_TEXT_SECONDARY)
          .justifyContent(FlexAlign.Center)
          .onClick((): void => { this.act(DC_ACTION_SELECT); });
        }
        if (this.row.kind === DC_KIND_PHOTO && this.row.path !== '') {
          CachedImage({ path: this.row.path, boxWidth: 44, boxHeight: 44, radius: 12, fit: ImageFit.Cover });
        } else if (this.poster !== '') {
          Stack() {
            CachedImage({ path: this.poster, boxWidth: 44, boxHeight: 44, radius: 12, fit: ImageFit.Cover });
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([Color.White]);
          }
          .width(44).height(44);
        } else {
          Row() {
            SymbolGlyph(this.kindIcon()).fontSize(22).fontColor([this.tint()]);
          }
          .width(44).height(44).borderRadius(12)
          .backgroundColor(this.tintSoft())
          .justifyContent(FlexAlign.Center);
        }
        Column() {
          Text(this.title())
            .width('100%')
            .fontSize(14.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.done()) {
            Row({ space: 6 }) {
              Text(this.row.savedLocal ? $r('app.string.dc_badge_saved_local') : $r('app.string.dc_badge_cache_only'))
                .fontSize(10.5).fontWeight(600)
                .fontColor(this.row.savedLocal ? $r('app.color.dc_ok') : $r('app.color.dc_warn'))
                .backgroundColor(this.row.savedLocal ? $r('app.color.dc_ok_soft') : $r('app.color.dc_warn_soft'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(5)
                .flexShrink(0);
              Text(this.metaText())
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1);
            }
            .width('100%')
            .margin({ top: 4 });
          } else {
            if (this.metaText() !== '') {
              Text(this.metaText())
                .width('100%')
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 3 });
            }
            if (this.showBar()) {
              Stack({ alignContent: Alignment.Start }) {
                Row()
                  .width(`${this.percent()}%`)
                  .height('100%')
                  .borderRadius(2)
                  .backgroundColor(this.row.state === DC_STATE_DOWNLOADING ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
              }
              .width('100%').height(4).borderRadius(2).clip(true)
              .backgroundColor($r('app.color.dc_chip'))
              .margin({ top: 8 });
            }
            Text(this.subText())
              .width('100%')
              .fontSize(12).fontWeight(this.row.state === DC_STATE_FAILED ? 600 : 500)
              .fontColor(this.subColor())
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 });
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        Row({ space: 6 }) {
          if (this.row.state === DC_STATE_DOWNLOADING) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.pause')).fontSize(15).fontColor([COLOR_PRIMARY]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor($r('app.color.dc_chip'))
            .accessibilityText($r('app.string.dc_action_pause'))
            .onClick((): void => { this.act(DC_ACTION_PAUSE); });
          }
          if (this.row.state === DC_STATE_WAITING_WIFI) {
            Button($r('app.string.dc_allow_cellular_short'))
              .height(BUTTON_SIZE)
              .padding({ left: 12, right: 12 })
              .fontSize(12.5).fontWeight(600)
              .fontColor(COLOR_PRIMARY)
              .backgroundColor(accentSoft())
              .accessibilityText($r('app.string.dc_allow_cellular'))
              .onClick((): void => { this.act(DC_ACTION_ALLOW_CELLULAR); });
          }
          if (this.row.state === DC_STATE_PAUSED || this.row.state === DC_STATE_PARTIAL) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(15).fontColor([COLOR_PRIMARY]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor(accentSoft())
            .accessibilityText($r('app.string.dc_action_resume'))
            .onClick((): void => { this.act(DC_ACTION_RESUME); });
          }
          if (this.row.state === DC_STATE_FAILED) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(15).fontColor([$r('app.color.dc_err')]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor($r('app.color.dc_err_soft'))
            .accessibilityText($r('app.string.dc_action_retry'))
            .onClick((): void => { this.act(DC_ACTION_RETRY); });
          }
          if (!this.done()) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor($r('app.color.dc_chip'))
            .accessibilityText($r('app.string.dc_action_cancel'))
            .onClick((): void => { this.act(DC_ACTION_CANCEL); });
          }
          if (this.done() && !this.row.savedLocal) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(15).fontColor([Color.White]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor(COLOR_PRIMARY)
            .accessibilityText($r('app.string.dc_action_save'))
            .onClick((): void => { this.act(DC_ACTION_SAVE); });
          }
          if (this.done() && this.row.savedLocal) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(14).fontColor([COLOR_PRIMARY]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor($r('app.color.dc_chip'))
            .accessibilityText($r('app.string.dc_action_open'))
            .onClick((): void => { this.act(DC_ACTION_OPEN); });
          }
          if (this.done()) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width(BUTTON_SIZE).height(BUTTON_SIZE)
            .backgroundColor($r('app.color.dc_chip'))
            .accessibilityText($r('app.string.dc_delete_cache'))
            .onClick((): void => { this.act(DC_ACTION_DELETE); });
          }
        }
        .flexShrink(0);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center);
      if (!this.row.last) {
        Divider().strokeWidth(HAIRLINE).color($r('app.color.dc_line'));
      }
    }
    .width('100%')
    .backgroundColor(COLOR_SURFACE)
    .borderWidth({
      left: HAIRLINE, right: HAIRLINE, top: this.row.first ? HAIRLINE : 0, bottom: this.row.last ? HAIRLINE : 0
    })
    .borderColor($r('app.color.dc_line'))
    .borderRadius({
      topLeft: this.row.first ? ROW_RADIUS : 0, topRight: this.row.first ? ROW_RADIUS : 0,
      bottomLeft: this.row.last ? ROW_RADIUS : 0, bottomRight: this.row.last ? ROW_RADIUS : 0
    })
    .clip(true);
  }
}
