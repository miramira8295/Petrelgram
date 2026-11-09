import { appIconArtNoBackground, initialIconName, resolveIconName } from '../../util/appIconArt';

// 登录页的主视觉：**应用自己的图案**，与桌面图标同一笔——但只画图案本身，不画
// 那层图标底色。
//
// 原来这里是 Telegram 贴纸包里的 Utya Duck（rawfile/login_utya_*.tgs）——那是
// 整个应用里唯一一处 Telegram 自己的美术素材，登录这一屏等于借别人的吉祥物站台。
// 换成本应用图标之后，它又整块带着圆角方底，像把桌面图标贴在了页面上：登录页
// 的背景、标题、输入框都是自己的版式，中间却嵌一块别人家的蓝方砖。
//
// 现在只画无背景那一层（util/appIconArt 的 appIconArtNoBackground）：用户换过
// 备用图标，这里跟着换，只是永远不带底色。26 以下没有备用图标，永远是默认那只。
//
// 图案不会动，所以补一个极缓的上下浮动——只动 translate，不触发重新布局。
// 3.2 秒一个来回、幅度 6vp，配得上那只海燕贴浪的图。
const HERO_BOX: number = 160;
// 与 HERO_BOX 等高：无底图那一层自己带着约一成的透明留白（图案占画布七成多），
// 铺满整框之后画出来的鸟，和原来嵌在 128 方块里的那只差不多大。
const ART_SIZE: number = 160;
const BOB_HEIGHT: number = -6;
const BOB_DURATION_MS: number = 3200;
// 图案就绪之后隔一小拍再起动画：和布局同一帧改 translate，动画拿不到起始帧，
// 会直接跳到终点静止在那里。
const BOB_DELAY_MS: number = 80;

@Component
export struct LoginHero {
  // 输入框里有内容时轻微放大——原来是鸭子凑过来，现在换成图案跟着应一声。
  @Prop active: boolean = false;
  // 图案备好了没有。26 及以上要异步问系统当前是哪一张，那之前整块不画：
  // 画错一张再换掉，比空着一小会儿更扎眼。
  @State private artReady: boolean = false;
  // 先放默认那只占位；artReady 为 false 时不会被画出来，只是为了不给 Image
  // 传 undefined（ArkTS 不对 this.x 做类型收窄）。
  @State private art: Resource = $r('app.media.fg_nightflight');
  @State private bob: number = 0;
  private disposed: boolean = false;
  private bobTimer: number = -1;

  aboutToAppear(): void {
    this.disposed = false;
    const name: string | undefined = initialIconName();
    // undefined 只出现在 26 及以上：等系统回答再画。低版本上默认那张是确定的，
    // 不必再问——那个接口本来就不存在。
    if (name === undefined) {
      resolveIconName().then((resolved: string): void => {
        if (!this.disposed) {
          this.applyArt(appIconArtNoBackground(resolved));
        }
      });
    } else {
      this.applyArt(appIconArtNoBackground(name));
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    // 登录页切换得很快，这个定时器多半是在这里被取消的。不取消就会在组件已经
    // 拆掉之后回调，改一个没人看的 @State。
    if (this.bobTimer !== -1) {
      clearTimeout(this.bobTimer);
      this.bobTimer = -1;
    }
  }

  private applyArt(art: Resource): void {
    this.art = art;
    this.artReady = true;
    this.startBob();
  }

  // 只改一次状态：iterations: -1 + Alternate 会让它自己永远来回，不需要定时器
  // 逐帧改（那会把整块按帧重建）。
  private startBob(): void {
    if (this.bobTimer !== -1) {
      return;
    }
    this.bobTimer = setTimeout((): void => {
      this.bobTimer = -1;
      if (!this.disposed) {
        this.bob = BOB_HEIGHT;
      }
    }, BOB_DELAY_MS);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.artReady) {
        Image(this.art)
          .width(ART_SIZE).height(ART_SIZE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .translate({ y: this.bob })
          .animation({
            duration: BOB_DURATION_MS,
            curve: Curve.EaseInOut,
            iterations: -1,
            playMode: PlayMode.Alternate
          })
          .scale({
            x: this.active ? 1.04 : 1,
            y: this.active ? 1.04 : 1
          })
          .animation({ duration: 180, curve: Curve.EaseOut });
      }
    }
    .width(HERO_BOX).height(HERO_BOX);
  }
}
