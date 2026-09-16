import { CachedImage } from './CachedImage';

// 贴纸类的静态图：缩略图、动画起播前的占位、贴纸包标签图标。
//
// 【为什么不直接 Image(file://…)】（2026-09-15 扫描 + trace）按文件路径交给 Image 时，
// 建图在 UI 路径上、目标尺寸是 [0, 0]——整张 512px 的 webp 先解出来再缩进 62vp 的格子，
// 单次 CreateImagePixelMap 最长 22.4ms，而贴纸抽屉一屏几十张。CachedImage 按物理显示
// 尺寸在 TaskPool 上解码，结果进共享 LRU，滑回来的格子同步命中。
//
// 只有本地绝对路径走 CachedImage（pixelCache 要的是不带 file:// 的路径）；其它形式原样交给 Image。
@ComponentV2
export struct StickerPoster {
  @Param path: string = '';
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Param fit: ImageFit = ImageFit.Contain;

  build() {
    if (this.path.startsWith('/')) {
      CachedImage({ path: this.path, boxWidth: this.boxWidth, boxHeight: this.boxHeight, fit: this.fit });
    } else if (this.path !== '') {
      Image(this.path).draggable(false)
        .width(this.boxWidth).height(this.boxHeight).objectFit(this.fit);
    }
  }
}
