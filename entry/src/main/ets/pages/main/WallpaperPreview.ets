import { ChatBackgroundState } from '../../store/ChatBackgroundStore';
import { gradientStops } from '../../util/backgroundPresentation';
import {
  backgroundBlurRadius, BLUR_OVERSCAN_SCALE, NO_BLUR_RADIUS, patternOpacity, wallpaperTakesUserDim
} from '../../util/chatBackgroundRaster';
import { CHAT_DIM_MAX } from '../../store/AppSettings';
import { PatternTileLayer } from '../chat/PatternTileLayer';

// 设置页的实时壁纸预览。
//
// 这里故意不用 ChatBackdrop：聊天背景组件还带离屏光栅，适合长时间停留的聊天页，
// 却会让一根正在拖动的 Slider 不断重建整屏缓存。预览只画
// 与三根滑杆有关的几层，规则仍复用生产渲染的纯函数，避免“预览一套、实际一套”。
@Component
export struct WallpaperPreview {
  @Prop wallpaper: ChatBackgroundState;
  @Prop blurAmount: number;
  @Prop patternStrength: number;
  @Prop dimAmount: number;
  @Prop dark: boolean;
  @Prop previewW: number;
  @Prop previewH: number;
  // 没有颜色也没有图时垫在底下的那一层。**由调用方按槽位给**（util/solidBackground
  // 的 systemSlotColor），不能在这里写 $r('app.color.chat_bg')：
  //   · $r 只认**当前系统**的深浅色，编辑另一模式的槽位时会画错底；
  //   · 聊天底和 APP 底浅色相同、深色不同（#0E1621 / #232E3C），只写一个必然错一个。
  // 2026-10-29 用户报「app深色/聊天深色 也按照当前真实背景设置上」就是这两条叠在一起：
  // 浅色设备上打开深色槽位，预览垫的是绿色的浅色聊天底。
  @Prop baseColor: string;

  private blurRadius(): number {
    return backgroundBlurRadius(
      this.wallpaper.path, this.wallpaper.isPattern,
      this.wallpaper.blurred, this.blurAmount);
  }

  private imageOpacity(): number {
    return patternOpacity(
      this.wallpaper.isPattern, this.wallpaper.imageOpacity, this.patternStrength);
  }

  private darkDim(): number {
    if (!this.dark || !wallpaperTakesUserDim(this.wallpaper.colors, this.wallpaper.path)) {
      return 0;
    }
    return Math.max(0, Math.min(CHAT_DIM_MAX, this.dimAmount));
  }

  build() {
    Stack() {
      if (this.wallpaper.colors.length > 0) {
        Column().width('100%').height('100%')
          .linearGradient({
            angle: this.wallpaper.angle,
            colors: gradientStops(this.wallpaper.colors)
          });
      } else {
        Column().width('100%').height('100%')
          .backgroundColor(this.baseColor);
      }
      if (this.wallpaper.path !== '' && this.wallpaper.isPattern) {
        PatternTileLayer({
          path: this.wallpaper.path,
          tileOpacity: this.imageOpacity(),
          blurRadius: this.blurRadius(),
          screenW: this.previewW,
          screenH: this.previewH
        });
      } else if (this.wallpaper.path !== '') {
        Image(this.wallpaper.path.startsWith('/')
          ? `file://${this.wallpaper.path}` : this.wallpaper.path).draggable(false)
          // 预览只有 188vp 高，不需要把相册原图按数千像素完整解码。
          // 2x 留足高密屏清晰度，同时显著降低滚动时的纹理上传和合成负担。
          .sourceSize({ width: this.previewW * 2, height: this.previewH * 2 })
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.imageOpacity())
          .scale(this.blurRadius() > NO_BLUR_RADIUS
            ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
          .blur(this.blurRadius());
      }
      if (this.wallpaper.dimming > 0) {
        Column().width('100%').height('100%')
          .backgroundColor(Color.Black).opacity(this.wallpaper.dimming);
      }
      if (this.darkDim() > 0) {
        Column().width('100%').height('100%')
          .backgroundColor(Color.Black).opacity(this.darkDim());
      }
    }
    .width('100%').height('100%').clip(true).renderGroup(true);
  }
}
