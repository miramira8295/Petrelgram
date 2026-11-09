import { appIconArtNoBackground, initialIconName, resolveIconName } from '../../util/appIconArt';

// 转圈延后多久才出现。
//
// 冷启动快的时候这一帧一闪而过，转圈跟着闪一下反而是新的噪点；慢的时候用户需要
// 知道它还活着。半秒是"用户开始怀疑卡住"之前的量级。
const SPINNER_DELAY_MS: number = 500;

// 图案边长。
//
// 原来画的是「底色层 + 前景层」拼成的一整块图标，取系统图标档位里最小的 128。
// 现在只画无背景那一层，那张图自己带着约一成的透明留白（图案占画布七八成），
// 用 128 会明显比原来小一圈，所以放到 160——画出来的图案和原来 128 那块差不多大，
// 与登录页主视觉也是同一个尺寸。
const ART_SIZE: number = 160;

// 系统启动窗消失之后、TDLib 就绪之前的那一帧。
//
// **它的全部职责是「看不出来」。**
//
// 背景色仍与系统启动窗逐字相同（$color:start_window_background，深浅色各一份），
// 所以底色这一步永远接得上。图案则是**当前桌面图标的那张无背景版**：用户选的是
// 哪张图标，这里就画哪张的图案（util/appIconArt 的 appIconArtNoBackground，与
// 登录页主视觉同一个函数），不带图标自己的底色。start_window.json 里那张静态图
// 已经撤掉——系统启动窗没有运行时接口，按备用图标改不了。
//
// 素材一律取 AppScope 里那批 1024×1024 的原图（$r 解析到的就是它），不是 entry
// 里 192px 的 iconprev_* 合成预览：放大到几倍宽的高密度屏上，192 那张会糊。
//
// 时序上分两步而不是一次画完：26 及以上要异步问系统当前是哪一张，第一帧就先不画
// 图案——系统那一帧现在是纯底色，空着反而与它完全一致，图案补上时没有跳变。
// 26 以下没有备用图标，第一帧直接是默认那张。
//
// 深浅色不用管：底色走 $r()，base 与 dark 各有一份 color.json（#FFFFFF/#000000）。
@Component
export struct StartupSplash {
  @State private showSpinner: boolean = false;
  // 图案备好了没有。没备好时整块不画，见上面「时序」那段。
  @State private artReady: boolean = false;
  // 先放默认那张占位；artReady 为 false 时不会被画出来，只是为了不给 Image
  // 传 undefined（ArkTS 不对 this.x 做类型收窄）。
  @State private art: Resource = $r('app.media.fg_nightflight');
  private spinnerTimer: number = -1;
  // 组件已经拆掉了。异步问图标名可能在启动页消失之后才回来——和下面那个定时器
  // 是同一类问题，只是这条走的是 Promise，clearTimeout 管不到。
  private disposed: boolean = false;

  aboutToAppear(): void {
    const name: string | undefined = initialIconName();
    // undefined 只出现在 26 及以上：等系统回答再画。低版本上第一帧就是默认那张，
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
    this.spinnerTimer = setTimeout((): void => {
      this.spinnerTimer = -1;
      this.showSpinner = true;
    }, SPINNER_DELAY_MS);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    // 启动通常在半秒内结束，这个定时器多半是在这里被取消的。不取消就会在组件
    // 已经拆掉之后回调，改一个没人看的 @State。
    if (this.spinnerTimer !== -1) {
      clearTimeout(this.spinnerTimer);
      this.spinnerTimer = -1;
    }
  }

  private applyArt(art: Resource): void {
    this.art = art;
    this.artReady = true;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.artReady) {
        Image(this.art)
          .width(ART_SIZE).height(ART_SIZE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      if (this.showSpinner) {
        // 压在下方三成处，不去碰居中的图案——任何遮挡都会把"接得上"破坏掉。
        Column() {
          LoadingProgress().width(30).height(30).color($r('app.color.text_secondary'));
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: '18%' });
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.start_window_background'));
  }
}
