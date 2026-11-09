import { TgsStickerView } from './TgsStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { StickerPoster } from '../common/StickerPoster';
import { stickerFramesCached } from '../../services/stickerFrameIndex';
import { alphaStickerHighBudget } from '../../util/webm/AlphaStickerBudget';

// 贴纸抽屉的一格：只负责画（动态 TGS / 视频贴纸 / 静态缩略图 / 经典 emoji 文字）。
// 点击、长按、按压反馈留在外层（StickerPicker.stickerCell）。
//
// 【曾经标过 @Reusable，已撤回（2026-09-15 同日）】想法是滑回来时只换路径、不重建贴纸视图子树，
// 依据是官方「@Reusable 回收复用时递归调用子组件 aboutToRecycle/aboutToReuse」。真机上复用出来的
// 格子一直画着上一张贴纸、换不到自己的静态图——外层是 V1 @Reusable、里面的贴纸视图是 V2 组件，
// 新路径没有在复用时送到里面那层（是 @Param 晚到还是 @Monitor 被复用期吞掉，没加探针，没定）。
// 查清之前别再给它加 @Reusable；要复用得先在 aboutToReuse / @Monitor 里打出路径看顺序。
@Component
export struct StickerGridCell {
  @Prop format: string = '';
  @Prop srcPath: string = '';
  // webm 源文件的 remote.unique_id：帧缓存命中时源文件不必下载（srcPath 可以是 ''）。
  @Prop srcUid: string = '';
  @Prop thumbPath: string = '';
  @Prop emoji: string = '';
  // 抽屉激活且允许播放（StickerPicker.active && animate）。
  // 同时经 @Consume('stickerPickerAnimate') 接收父级 StickerPicker 的实时激活态：
  // V1 LazyForEach 在键值不变时不会重跑子项 builder，单靠 @Prop animate 无法感知
  // 面板收起或切页，必须靠 @Consume 穿透 LazyForEach 立即卸载动态贴纸视图。
  @Prop animate: boolean = true;
  @Consume('stickerPickerAnimate') pickerAnimate: boolean;
  @Prop cellPx: number = 62;
  @Prop category: string = 'sticker';
  @Prop emojiFontSize: number = 30;

  private framesCached(): boolean {
    return stickerFramesCached(this.srcUid, vp2px(this.cellPx), alphaStickerHighBudget(this.category));
  }

  private shouldAnimate(): boolean {
    return this.animate && this.pickerAnimate;
  }

  build() {
    Stack() {
      if (this.shouldAnimate() && this.format === 'tgs' && this.srcPath !== '') {
        TgsStickerView({
          tgsPath: this.srcPath, thumbPath: this.thumbPath,
          boxWidth: this.cellPx, boxHeight: this.cellPx,
          powerCategory: this.category,
          panelGated: true
        });
      } else if (this.shouldAnimate() && this.format === 'webm' && (this.srcPath !== '' || this.framesCached())) {
        SmartLoopVideo({
          videoPath: this.srcPath, thumbPath: this.thumbPath, stickerUid: this.srcUid,
          boxWidth: this.cellPx, boxHeight: this.cellPx,
          powerCategory: this.category,
          panelGated: true
        });
      } else if (this.thumbPath !== '') {
        StickerPoster({ path: this.thumbPath, boxWidth: this.cellPx, boxHeight: this.cellPx });
      } else {
        Text(this.emoji)
          .fontSize(this.emojiFontSize)
          .textAlign(TextAlign.Center)
          .width('100%').height('100%');
      }
    }
    .width('100%').height('100%');
  }
}
