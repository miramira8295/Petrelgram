import { TgsStickerView } from './TgsStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { StickerPoster } from '../common/StickerPoster';

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
  @Prop thumbPath: string = '';
  @Prop emoji: string = '';
  // 抽屉激活且允许播放（StickerPicker.active && animate）。
  @Prop animate: boolean = true;
  @Prop cellPx: number = 62;
  @Prop category: string = 'sticker';
  @Prop emojiFontSize: number = 30;

  build() {
    Stack() {
      if (this.animate && this.format === 'tgs' && this.srcPath !== '') {
        TgsStickerView({
          tgsPath: this.srcPath, thumbPath: this.thumbPath,
          boxWidth: this.cellPx, boxHeight: this.cellPx,
          powerCategory: this.category,
          panelGated: true
        });
      } else if (this.animate && this.format === 'webm' && this.srcPath !== '') {
        SmartLoopVideo({
          videoPath: this.srcPath, thumbPath: this.thumbPath,
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
