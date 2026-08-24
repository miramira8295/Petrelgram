// 转圈延后多久才出现。
//
// 冷启动快的时候这一帧一闪而过，转圈跟着闪一下反而是新的噪点；慢的时候用户需要
// 知道它还活着。半秒是"用户开始怀疑卡住"之前的量级。
const SPINNER_DELAY_MS: number = 500;

// 系统启动窗消失之后、TDLib 就绪之前的那一帧。
//
// **它的全部职责是「看不出来」。** 原来这里画的是一个裸 LoadingProgress：系统
// 启动窗上是一架居中的飞机，下一帧突然变成一个小转圈——中间那一下跳变就是启动
// 显得割裂的原因。
//
// 所以这里**照抄系统启动窗**，而不是另画一个品牌页：
//   · 同一张图     $media:start_splash（那张图本身是透明的，只有飞机）
//   · 同一个填充   Cover
//   · 同一个底色   $color:start_window_background
// 三项都逐字取自 resources/base/profile/start_window.json。同一份资源、同一种
// 摆法，接上去就是同一帧，跳变自然消失。
//
// 深浅色不用管：start_window.json 是 FOLLOW_SYSTEM，而 $r() 本来就按当前深浅色
// 解析——base 与 dark 各有一份 color.json（#FFFFFF / #000000）。两边走的是同一
// 套资源限定，所以自动一致。
//
// **改这个文件前先看 start_window.json。** 那三项里任何一项改了，这里必须跟着
// 改，否则跳变会以另一种形式回来。
@Component
export struct StartupSplash {
  @State private showSpinner: boolean = false;
  private spinnerTimer: number = -1;

  aboutToAppear(): void {
    this.spinnerTimer = setTimeout((): void => {
      this.spinnerTimer = -1;
      this.showSpinner = true;
    }, SPINNER_DELAY_MS);
  }

  aboutToDisappear(): void {
    // 启动通常在半秒内结束，这个定时器多半是在这里被取消的。不取消就会在组件
    // 已经拆掉之后回调，改一个没人看的 @State。
    if (this.spinnerTimer !== -1) {
      clearTimeout(this.spinnerTimer);
      this.spinnerTimer = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // start_splash 是透明图，飞机以外全靠这层底色透出来——和系统启动窗一样。
      Image($r('app.media.start_splash'))
        .width('100%').height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false);
      if (this.showSpinner) {
        // 压在下方三成处，不去碰居中的飞机——飞机的位置正是要和系统启动窗对齐的
        // 那个东西，任何遮挡都会把"接得上"破坏掉。
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
