import { image } from '@kit.ImageKit';
import { queueTgsOpen, queueTgsRender, tgsClose, TgsOpenResult } from '../../util/tgsRenderQueue';
import { tgsRenderSize } from '../../util/tgsPlayback';
import { logE } from '../../util/log';
import { replyThumbSrc } from '../../util/replyThumb';

// 引用块里的骰子/老虎机：画动画的**结尾帧**（摇出来的结果），不是缩略图那张第一帧
// （老虎机的第一帧是三个空转轮，看不出结果）。2026-10-10。
//
// 只渲一帧：开 → 渲最后一帧 → 关。多层（老虎机 5 层）由原生合成一张；帧缓存在的话
// 这一帧直接从盘上读。渲出来之前、或渲不出来时，垫着缩略图。
@ComponentV2
export struct DiceEndFrame {
  // 按 z 序从下到上的层（见 util/replyThumb.replyDiceLayers）。
  @Param layers: string[] = [];
  @Param boxSize: number = 30;
  // 结尾帧渲出来之前（或渲不出来时）垫着的缩略图；'' = 空着但照样占位。
  @Param thumbPath: string = '';

  @Local private frame: image.PixelMap | null = null;
  // 换了层 / 回收 / 下树时作废在途的那次渲染。
  private seq: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.seq++;
    this.dropFrame();
  }

  // 挂在 @ReusableV2 的消息行里：复用时 @Param 已换，@Monitor 静默，必须自己重载。
  aboutToRecycle(): void {
    this.seq++;
    this.dropFrame();
  }

  aboutToReuse(): void {
    this.load();
  }

  @Monitor('layers')
  onLayersChanged(): void {
    this.load();
  }

  private dropFrame(): void {
    if (this.frame !== null) {
      const old: image.PixelMap = this.frame;
      this.frame = null;
      old.release().catch((e: Error): void => {
        logE(`DiceEndFrame: release failed: ${e.message}`);
      });
    }
  }

  private load(): void {
    const token: number = ++this.seq;
    this.dropFrame();
    if (this.layers.length === 0) {
      return;
    }
    const size: number = tgsRenderSize(this.boxSize, this.getUIContext().vp2px(1));
    const source: string | string[] = this.layers.length > 1 ? this.layers.slice() : this.layers[0];
    queueTgsOpen(source, size, size).then(async (info: TgsOpenResult | null): Promise<void> => {
      if (info === null) {
        return;
      }
      try {
        if (token !== this.seq || info.totalFrames <= 0) {
          return;
        }
        const frame: image.PixelMap | null = await queueTgsRender(info.handle, info.totalFrames - 1);
        if (frame === null) {
          return;
        }
        if (token !== this.seq) {
          frame.release();
          return;
        }
        this.frame = frame;
      } finally {
        tgsClose(info.handle);
      }
    }).catch((e: Error): void => {
      logE(`DiceEndFrame: render failed: ${e.message}`);
    });
  }

  // 始终占住一个方块：引用块的高度/宽度不能因为结尾帧晚到而跳。
  build() {
    Stack() {
      if (this.frame !== null) {
        Image(this.frame).draggable(false)
          .width(this.boxSize).height(this.boxSize).objectFit(ImageFit.Contain);
      } else if (this.thumbPath !== '') {
        Image(replyThumbSrc(this.thumbPath)).draggable(false)
          .width(this.boxSize).height(this.boxSize).objectFit(ImageFit.Contain);
      }
    }
    .width(this.boxSize).height(this.boxSize);
  }
}
