// 拖拽悬停提示层：把文件/图片/视频拖到会话页上空时，页面正中给出「拖拽到此处，
// 松手即发送」的提示，并沿可投放范围圈一圈描边；松手由 ChatDropReceiver 立刻发出。
//
// 【2026-11-23 用户要求】原来松手后会弹一个「分享到 Petrel」的确认输入框，每次都要
// 再点一次发送，很碍事。这一层替代那个弹框：拖拽期间就把「会发生什么」讲清楚，松手即发。
//
// 【玻璃】与输入栏同一条路径：NativeGlassHost 的默认 'menu' 面（ChatComposerInput
// 也是不传 surface 用默认值，两处出来的是同一块玻璃）。卡片先按内容自适应排版，
// 量到宽高后回填给画布——NativeGlassHost 只吃绝对 vp，传 '100%' 在这一层解析不可靠。
//
// 【遮罩不出框】压暗层、主题色淡填充、虚线边界全部塞进同一个「内缩 12vp、圆角 24」
// 的容器里，所以暗色只铺到框选范围为止，屏幕四边那 12vp 保持原样（用户 2026-11-23：
// 「遮罩阴影应该显示在框选范围内，不应该超出」）。
//
// 【进出动画】不用 transition：拖拽是系统级事件，if 节点插入/移除时的 transition 在真机
// 上时灵时不灵，用户两次反馈「很生硬」。改成常驻在树上时用属性动画——
//   进场：shown true，卡片 scale 0.86→1 + opacity 0→1（380ms EaseOut，即「逐渐放大、
//         从虚到实」）；压暗与虚线框 280ms 淡入。
//   出场：shown false，卡片 1→0.86 + 1→0（240ms EaseIn，即「从大到小、从实到虚」），
//         等动画播完（260ms）再把节点移出树。
// 状态机放在 DropHoverState 里（@ObservedV2），显隐入口统一走 setVisible()。
//
// 这一层只负责观感：hitTestBehavior 全关、不接拖拽事件；显隐由 ChatPage 的
// onDragEnter / onDragLeave / onDrop 驱动，拖拽数据的接收仍在页面根 Stack 的
// allowDrop/onDrop 上。
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { NativeGlassHost } from './NativeGlassHost';

@ObservedV2
export class DropHoverState {
  // 是否在树上。出场动画播完才置 false（否则节点被立刻删掉，动画没机会跑）。
  @Trace visible: boolean = false;
  // 动画目标：false = 虚/小，true = 实/原位。进场先入树、下一拍再切 true，属性动画才有起点。
  @Trace shown: boolean = false;
  // 松手之后是直接发出（文件/图片），还是塞进输入框（纯文字）。数据类型只有
  // 拖拽事件的 Summary 能提前知道，所以由 ChatPage 在 onDragEnter 里写进来。
  @Trace sendMode: boolean = true;

  private showTimer: number = -1;
  private hideTimer: number = -1;

  setVisible(on: boolean): void {
    if (on) {
      if (this.hideTimer !== -1) {
        clearTimeout(this.hideTimer);
        this.hideTimer = -1;
      }
      if (this.visible && this.shown) {
        return;
      }
      this.visible = true;
      if (this.showTimer !== -1) {
        clearTimeout(this.showTimer);
      }
      // 等首帧以「虚 + 小」渲染出来，再切到实态，属性动画才会从 0.86/透明补到 1。
      this.showTimer = setTimeout((): void => {
        this.showTimer = -1;
        this.shown = true;
      }, 16);
    } else {
      if (this.showTimer !== -1) {
        clearTimeout(this.showTimer);
        this.showTimer = -1;
      }
      if (!this.visible) {
        return;
      }
      this.shown = false;
      if (this.hideTimer === -1) {
        // 比出场动画（240ms）稍长，保证动画跑完再拆节点。
        this.hideTimer = setTimeout((): void => {
          this.hideTimer = -1;
          this.visible = false;
        }, 260);
      }
    }
  }

  dispose(): void {
    if (this.showTimer !== -1) {
      clearTimeout(this.showTimer);
      this.showTimer = -1;
    }
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
    this.visible = false;
    this.shown = false;
  }
}

@ComponentV2
export struct DropHoverOverlay {
  @Require @Param state: DropHoverState;
  @Param target: string = '';
  @Param dark: boolean = false;

  // 玻璃画布要的绝对尺寸：先按内容排一次版，量到宽高再回填（与输入栏同一套做法）。
  @Local private cardW: number = 0;
  @Local private cardH: number = 0;

  build() {
    if (this.state.visible) {
      // 外层满屏但不是遮罩：只负责把里面那层「框」内缩 12vp，暗色不会溢出到屏幕边缘。
      Stack({ alignContent: Alignment.Center }) {
        Stack({ alignContent: Alignment.Center }) {
          this.dropShade()
          this.hintCard()
        }
        .width('100%')
        .height('100%')
        .padding(12)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }

  // 框内：压暗 + 一层很淡的主题色 + 一圈虚线边界，三者都只在框里画。
  @Builder
  dropShade() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor(this.dark ? '#6B000000' : '#47000000')
        .opacity(this.state.shown ? 1 : 0)
        .animation({
          duration: this.state.shown ? 280 : 200,
          curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
        })
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor(COLOR_PRIMARY)
        .opacity(this.state.shown ? 0.06 : 0)
        .animation({
          duration: this.state.shown ? 280 : 200,
          curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
        })
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .border({ width: 2, color: COLOR_PRIMARY, style: BorderStyle.Dashed })
        .opacity(this.state.shown ? 1 : 0)
        .animation({
          duration: this.state.shown ? 280 : 200,
          curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  hintCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 玻璃画布：尺寸等于量出来的卡片尺寸，圆角与卡片一致（26）。
      if (this.cardW > 0 && this.cardH > 0) {
        NativeGlassHost({
          hostWidth: this.cardW, hostHeight: this.cardH, hostRadius: 26, dark: this.dark
        })
      }
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(64)
            .height(64)
            .fill(this.dark ? '#26FFFFFF' : '#14000000')
          SymbolGlyph($r('sys.symbol.paperplane'))
            .fontSize(30)
            .fontColor([COLOR_PRIMARY])
        }
        .width(64)
        .height(64)

        Text(str(this.state.sendMode ? 'drop_release_send' : 'drop_release_draft'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .margin({ top: 14 })

        if (this.target !== '') {
          Text(str('drop_release_to', this.target))
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .margin({ top: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .padding({ left: 32, right: 32, top: 28, bottom: 26 })
      .constraintSize({ minWidth: 240, maxWidth: 340 })
      // 玻璃还没量到尺寸的那一帧先垫一层近似的玻璃色，避免白字直接压在压暗层上闪一下。
      .backgroundColor(this.cardW > 0 ? Color.Transparent : (this.dark ? '#B32F3F52' : '#B3F8F8F8'))
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && Math.abs(w - this.cardW) > 0.5) {
          this.cardW = w;
        }
        if (h > 0 && Math.abs(h - this.cardH) > 0.5) {
          this.cardH = h;
        }
      })
    }
    // 进场：0.86 → 1、透明 → 实（逐渐放大、从虚到实）；出场反过来（从大到小、从实到虚）。
    .scale({ x: this.state.shown ? 1 : 0.86, y: this.state.shown ? 1 : 0.86 })
    .opacity(this.state.shown ? 1 : 0)
    .animation({
      duration: this.state.shown ? 380 : 240,
      curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
    })
  }
}
