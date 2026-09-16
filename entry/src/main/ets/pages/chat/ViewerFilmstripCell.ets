import { LiveThumbImage } from './LiveThumbImage';
import { CachedImage } from '../common/CachedImage';
import { FilmCellVM } from '../../util/viewerFilmstrip';
import { posterFor, subscribePoster } from '../../util/videoPosterStore';

// 查看器底部缩略图条的一格（2026-09-16）。
//
// 【为什么单独成组件】原来这一格是 MediaViewerOverlay 里 ForEach 的内联子树：
// n 张就是 n 棵子树同时活着，没有复用。下载中心把整个页签当成一个相册，n 是已加载
// 的全部条目（用户 2026-09-16：「缩略图列表是分页的吗…item 需要是复用的」）。
// 拆出来才能挂 @ReusableV2，配合外层的 LazyForEach 只建可视区 + cachedCount 那几格。
//
// 【为什么内层是 LiveThumbImage 而不是 Image】缩略图路径**刻意不进 key**
// （见 util/collapseAlbums），所以路径落地时这一格不会被重建——图必须自己订阅
// mediaThumbChannel 自己换。LiveThumbImage 就是干这个的，且它自带 @Monitor('spec')
// 的复用自愈，正好接住 @ReusableV2 复用时 @Param 晚落地的那一拍。
//
// 必须放在 V2 父组件里：官方混用表写明 V1 普通组件不能包含 V2 复用组件。
// MediaViewerOverlay 是 @ComponentV2，成立。

const THUMB: number = 52;
const RADIUS: number = 6;

@ReusableV2
@ComponentV2
export struct ViewerFilmstripCell {
  @Require @Param cell: FilmCellVM;
  // 选中态只影响边框/透明度/缩放。它进了缩略图条那一份 key（filmCellKeys），
  // 所以选中移动时恰好这两格重画。
  @Param current: boolean = false;
  // 动画时长由宿主按省电档位算好传进来（chatEffectDuration），本组件不读设置。
  @Param effectMs: number = 160;

  @Builder
  emptyBox() {
    Column().width(THUMB).height(THUMB).borderRadius(RADIUS).backgroundColor('#333333');
  }

  // 下载中心的本地视频：没有 fileId、也没有 TDLib 缩略图，海报是我们自己抽的首帧，
  // 通道按**路径**索引（util/videoPosterStore）。所以这一格不能走 LiveThumbImage
  // （它按 fileId 订阅），自己订阅、自己换图——道理与 LiveThumbImage 完全一样。
  @Local private poster: string = '';
  private unsubPoster: (() => void) | null = null;
  private attachedPath: string = '';

  aboutToAppear(): void {
    this.attachPoster();
  }

  aboutToDisappear(): void {
    this.detachPoster();
  }

  // 同 DownloadCenterRow：@ReusableV2 滑出是进池不是销毁，且复用重置期间
  // @Monitor 静默——两个钩子缺一不可，否则复用出来的格子永远不重挂、不请求。
  aboutToRecycle(): void {
    this.detachPoster();
  }

  aboutToReuse(): void {
    this.attachPoster();
  }

  // @ReusableV2 复用时 @Param 已是新值：按新路径重挂。名字必须与 @Param 逐字一致
  // （名字写错 ArkUI 不报错也不告警，自愈会静默失效）。
  @Monitor('cell')
  onCellChanged(): void {
    this.attachPoster();
  }

  private attachPoster(): void {
    const path: string = this.cell.videoPath;
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
  }

  private detachPoster(): void {
    if (this.unsubPoster !== null) {
      this.unsubPoster();
      this.unsubPoster = null;
    }
    this.attachedPath = '';
  }

  build() {
    Stack() {
      if (this.cell.videoPath !== '') {
        if (this.poster !== '') {
          CachedImage({
            path: this.poster, boxWidth: THUMB, boxHeight: THUMB,
            radius: RADIUS, fit: ImageFit.Cover
          });
        } else {
          this.emptyBox();
        }
      } else {
        LiveThumbImage({
        spec: {
          fileId: this.cell.fileId,
          initialPath: this.cell.path,
          boxWidth: THUMB,
          boxHeight: THUMB,
          radius: RADIUS,
          fit: ImageFit.Cover
        },
        placeholder: (): void => { this.emptyBox(); }
        });
      }
      if (this.cell.isVideo) {
        Text('▶').fontSize(14).fontColor(Color.White);
      }
    }
    .width(THUMB).height(THUMB)
    .border({ width: this.current ? 2 : 0, color: Color.White })
    .borderRadius(RADIUS)
    .opacity(this.current ? 1 : 0.68)
    .scale({ x: this.current ? 1 : 0.92, y: this.current ? 1 : 0.92 })
    .animation({ duration: this.effectMs, curve: Curve.EaseOut });
  }
}
