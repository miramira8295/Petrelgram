import { common } from '@kit.AbilityKit';
import { ChatBackgroundState } from '../../store/ChatBackgroundStore';
import { gradientStops } from '../../util/backgroundPresentation';
import {
  backgroundBlurRadius, BLUR_OVERSCAN_SCALE, cachedPatternRaster, NO_BLUR_RADIUS,
  patternOpacity, PatternRasterParams, patternRasterSignature, rasterizePattern, wallpaperTakesUserDim
} from '../../util/chatBackgroundRaster';
import { CHAT_DIM_MAX } from '../../store/AppSettings';
import { PatternTileLayer } from '../chat/PatternTileLayer';

const PATTERN_RASTER_DELAY_MS: number = 360;

// 设置页的实时壁纸预览。
//
// 这里故意不用 ChatBackdrop：聊天背景组件还带离屏光栅，适合长时间停留的聊天页，
// 却会让一根正在拖动的 Slider 不断重建整屏缓存。预览只画
// 与三根滑杆有关的几层，规则仍复用生产渲染的纯函数，避免“预览一套、实际一套”。
@Component
export struct WallpaperPreview {
  @Prop @Watch('onSourceChanged') wallpaper: ChatBackgroundState;
  @Prop blurAmount: number;
  @Prop patternStrength: number;
  @Prop dimAmount: number;
  @Prop dark: boolean;
  @Prop @Watch('onSourceChanged') previewW: number;
  @Prop @Watch('onSourceChanged') previewH: number;
  // 没有颜色也没有图时垫在底下的那一层。**由调用方按槽位给**（util/solidBackground
  // 的 systemSlotColor），不能在这里写 $r('app.color.chat_bg')：
  //   · $r 只认**当前系统**的深浅色，编辑另一模式的槽位时会画错底；
  //   · 聊天底和 APP 底浅色相同、深色不同（#0E1621 / #232E3C），只写一个必然错一个。
  // 2026-10-29 用户报「app深色/聊天深色 也按照当前真实背景设置上」就是这两条叠在一起：
  // 浅色设备上打开深色槽位，预览垫的是绿色的浅色聊天底。
  @Prop baseColor: string;

  // 图案层的光栅化结果（'' = 还没好）。图案本体是 10 张 pattern.tgv.svg，每次进页
  // 都要逐张栅格化，真机实测吃掉 RS 绘制 105ms；烘成一张透明底 PNG 后只剩一次 blit。
  @State private rasterPath: string = '';
  // 烘焙期间只画渐变、不建那 10 张 SVG（否则等于没优化）。烘焙失败会撤销。
  @State private deferTiles: boolean = false;
  private rasterGen: number = 0;
  private rasterTimer: number = -1;

  aboutToAppear(): void {
    this.syncPatternRaster();
  }

  aboutToDisappear(): void {
    // 页面走了：作废在途烘焙（结果回来也不再 setState），并撤掉定时器。
    this.rasterGen++;
    this.clearRasterTimer();
  }

  private clearRasterTimer(): void {
    if (this.rasterTimer !== -1) {
      clearTimeout(this.rasterTimer);
      this.rasterTimer = -1;
    }
  }

  private cacheDir(): string {
    return (this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir;
  }

  // 背景或预览尺寸变了：换图/换尺寸就作废旧结果，绝不把上一张图案贴回去。
  private onSourceChanged(): void {
    this.syncPatternRaster();
  }

  private syncPatternRaster(): void {
    this.rasterGen++;
    const gen: number = this.rasterGen;
    this.clearRasterTimer();
    if (!this.wallpaper.isPattern || this.wallpaper.path === '') {
      this.rasterPath = '';
      this.deferTiles = false;
      return;
    }
    const params: PatternRasterParams = {
      path: this.wallpaper.path, width: this.previewW, height: this.previewH
    };
    const dir: string = this.cacheDir();
    const hit: string = cachedPatternRaster(patternRasterSignature(params), dir);
    if (hit !== '') {
      this.rasterPath = hit;
      this.deferTiles = false;
      return;
    }
    this.rasterPath = '';
    this.deferTiles = true;
    // 一次烘焙要 320ms 快照 + 编码，推到下一拍再开始，先把进入帧让出去。
    this.rasterTimer = setTimeout((): void => {
      this.rasterTimer = -1;
      if (gen !== this.rasterGen) {
        return;
      }
      rasterizePattern(this.getUIContext(), params, dir)
        .then((baked: string): void => {
          if (gen !== this.rasterGen) {
            return;
          }
          if (baked !== '') {
            this.rasterPath = baked;
          }
          // 烘失败也要把实时图案层放回来：宁可慢，不能没有图案。
          this.deferTiles = false;
        })
        .catch((): void => {
          if (gen === this.rasterGen) {
            this.deferTiles = false;
          }
        });
    }, PATTERN_RASTER_DELAY_MS);
  }

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
        if (this.rasterPath !== '') {
          // 位图里只有图案本体（透明底），渐变还在下面那层，所以浓度/模糊/遮罩
          // 继续由这三条实时属性乘上去——拖滑杆不会重烘，也就不会闪。
          Image(`file://${this.rasterPath}`).draggable(false)
            .autoResize(true)
            .width('100%').height('100%')
            .objectFit(ImageFit.Fill)
            .opacity(this.imageOpacity())
            .scale(this.blurRadius() > NO_BLUR_RADIUS
              ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
            .blur(this.blurRadius());
        } else if (!this.deferTiles) {
          // 没有缓存、也没在烘：老路（10 张 SVG 实时平铺）。
          PatternTileLayer({
            path: this.wallpaper.path,
            tileOpacity: this.imageOpacity(),
            blurRadius: this.blurRadius(),
            screenW: this.previewW,
            screenH: this.previewH
          });
        }
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
