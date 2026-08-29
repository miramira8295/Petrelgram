import {
  BG_BLUR_MAX, CHAT_DIM_MAX, KEY_APP_BG_BLUR, KEY_APP_BG_DARK, KEY_APP_BG_DIM, KEY_APP_BG_LIGHT
} from '../../store/AppSettings';
import { KEY_APP_DARK } from '../../util/theme';
import { appWallpaperActive } from '../../util/localWallpaper';
import { BLUR_OVERSCAN_SCALE, NO_BLUR_RADIUS } from '../../util/chatBackgroundRaster';

// APP 背景图：铺在**主界面**（会话列表 / 联系人 / 设置首页 / 我的）背后的一张
// 本机图片。和聊天壁纸是两件事，两套设置各管各的。
//
// 【为什么只在主界面】设置子页和登录页是密集的列表与表单，铺一张任意图片只会让
// 它们更难读——而且那还会把 65 处 page_bg 全牵进来。主界面这四个 tab 是唯一
// 「留白多、值得有张图」的地方，触点也就四处。
//
// 【为什么不进 Index 而是挂在 MainScreen】挂 Index 会连登录流程一起铺上，那既没
// 必要、又赶在用户还没设过这张图的时候。MainScreen 是「已登录的主界面」这一层，
// 边界正好。
//
// 【不需要 epoch】本组件用 @StorageProp 直接订阅路径键，设置页一写就重建。
// ChatPage 那边要 KEY_LOCAL_BG_EPOCH，是因为解析壁纸的是 store（不是组件），
// 订阅不到 AppStorage。
@Component
export struct AppBackdrop {
  // 分栏（平板/折叠屏展开）下不铺：右栏被聊天壁纸盖住，这张图只能从左栏那条窄缝
  // 里露出来，既不好看也没意义。设置项在分栏下也一并藏掉。
  @Prop split: boolean = false;
  @StorageProp(KEY_APP_DARK) appDark: boolean = false;
  @StorageProp(KEY_APP_BG_LIGHT) lightPath: string = '';
  @StorageProp(KEY_APP_BG_DARK) darkPath: string = '';
  @StorageProp(KEY_APP_BG_BLUR) blurAmount: number = 0;
  @StorageProp(KEY_APP_BG_DIM) dimAmount: number = 0;

  private path(): string {
    return this.appDark ? this.darkPath : this.lightPath;
  }

  private blurRadius(): number {
    return Math.max(NO_BLUR_RADIUS, Math.min(BG_BLUR_MAX, this.blurAmount));
  }

  // 暗化只在深色模式下生效，和聊天壁纸那层同一套心智：浅色模式下压暗背景只会
  // 让整个界面发脏，而深色模式下它是让白字读得清的关键。
  private maskOpacity(): number {
    if (!this.appDark) {
      return 0;
    }
    return Math.max(0, Math.min(CHAT_DIM_MAX, this.dimAmount));
  }

  build() {
    Stack() {
      if (appWallpaperActive(this.path(), this.split)) {
        Image(this.path().startsWith('/') ? `file://${this.path()}` : this.path())
          .draggable(false)
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
          // 模糊要一点过扫，否则边缘的半透明像素会在四周露出来。按**实际半径**判断
          // 而不是「有没有开模糊」——滑杆拖到 0 时不该白白放大裁掉边缘。
          .scale(this.blurRadius() > NO_BLUR_RADIUS
            ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
          .blur(this.blurRadius());
        if (this.maskOpacity() > 0) {
          Column()
            .width('100%').height('100%')
            .backgroundColor(Color.Black)
            .opacity(this.maskOpacity());
        }
      }
    }
    .width('100%').height('100%')
    // 纯装饰层，不该吃任何手势——上面就是会话列表。
    .hitTestBehavior(HitTestMode.None);
  }
}
