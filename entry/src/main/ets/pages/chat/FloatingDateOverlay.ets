import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { overlayBackdropBlur, overlayGlassFill } from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';
import { FLOAT_DATE_HIDE_MS, floatDateShouldRearm } from '../../util/floatDateGate';
import { TimelineStatePill } from './MessageListState';

// 视口顶上那枚浮动日期条，连同它的显隐节奏。
//
// 【为什么从 ChatPage 里搬出来】
// 原来日期文字和显隐是 ChatPage 的两个 @Local，onDidScroll 每帧调的
// updateFloatDate 直接写它们，820ms 的隐藏定时器再写回去。后果是：滑动中每次
// 跨过日期边界、以及每次停手后的淡出，都会让**整个 ChatPage** 重绘一遍。真机
// Frame trace 里最重的那一帧就命中了它的 200ms 动画上下文。
//
// 现在这两个值住在下面这个 @ObservedV2 对象里，ChatPage 只持有对象引用（普通
// 私有字段，不是 @Local），build() 里一个字都不读。读它的只有本文件里的两个
// V2 组件，于是重绘范围收敛到日期条本身。
//
// 【为什么状态放在 @ObservedV2 对象里，而不是组件自己的 @Local】
// 因为有第二个读者：TimelineStatePill 要知道日期条在不在，好把自己往下让
// 42vp。@Local 只有组件自己看得见，那就得在 ChatPage 里再存一份给它——两份
// 会漂。放在一个 @Trace 对象里，两个组件各自订阅，ChatPage 谁也不订阅。

@ObservedV2
export class FloatingDateState {
  // 日期文字。**清空只发生在 clear()**：隐藏定时器只翻 shown，label 留着。
  // 这是既有行为，TimelineStatePill 的让位判据（label !== ''）依赖它——淡出
  // 之后胶囊仍然保持让位，别顺手"修"成跟着 shown 走。
  @Trace label: string = '';
  // 入场/出场用的可见性。200ms 的淡入淡出挂在读它的那个节点上。
  @Trace shown: boolean = false;

  // 以下三个都是普通字段：写它们不该惊动任何组件。
  private hideTimer: number = -1;
  private armedAt: number = 0;
  private hiddenCallback: () => void = (): void => {};

  // 定时器烧到底时回调。ChatPage 用它在**同一时刻**把 listUserScrollActive
  // 翻假——那是它原来在同一个定时器体里做的事，时序因此完全等价。
  setOnHidden(callback: () => void): void {
    this.hiddenCallback = callback;
  }

  // 顶行换了日期：换文字、亮起来、重新上定时器。
  show(label: string, now: number): void {
    if (this.label !== label) {
      this.label = label;
    }
    if (!this.shown) {
      this.shown = true;
    }
    this.armHide(now);
  }

  // 顶行没换但手指还在拖：只给显示续期，粗粒度（见 util/floatDateGate）。
  keepAlive(now: number): void {
    if (!this.shown || !floatDateShouldRearm(now, this.armedAt)) {
      return;
    }
    this.armHide(now);
  }

  // 立刻收掉，不走淡出——跳转/换会话这些"位置意图被接管"的场合用。
  // 刻意不触发 hiddenCallback：调用方（ChatPage.clearFloatingDate）本来就在
  // 同一句里把自己那几个非响应式标志一起清了。
  clear(): void {
    this.cancelHide();
    this.armedAt = 0;
    if (this.label !== '') {
      this.label = '';
    }
    if (this.shown) {
      this.shown = false;
    }
  }

  private cancelHide(): void {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  private armHide(now: number): void {
    this.armedAt = now;
    this.cancelHide();
    this.hideTimer = setTimeout((): void => {
      this.hideTimer = -1;
      this.shown = false;
      this.hiddenCallback();
    }, FLOAT_DATE_HIDE_MS);
  }
}

@ComponentV2
export struct FloatingDateOverlay {
  @Require @Param state: FloatingDateState;
  // V2 组件不能直接订阅 AppStorage；由 ChatPageChrome 现有的材质纪元一路透传。
  // 只在用户修改档位时变化，不参与滚动中的日期状态更新。
  @Require @Param materialEpoch: number = 0;
  // 顶部 chrome 的高度由 ChatPage 算（headerChromeHeight()），这里只收结果。
  // 传数值而不是传 getter：getter 会把 ChatPage 的那几个字段拖进本组件的订阅
  // 关系里，而 ChatPage.build 本来就为 List.contentStartOffset 读了它们，多订
  // 阅一份没有收益。
  @Param topMargin: number = 0;

  build() {
    // 外层这个 Row 常驻挂载：ArkUI 要求 build 有唯一根节点，条件渲染只能放在
    // 它里面。label 为空时内层不挂载，屏幕上是零高度的空节点，与原来"整条
    // 不挂载"在视觉与布局上等价（Stack 是 TopStart 对齐，子节点各自独立）。
    //
    // 修饰器栈与搬来之前逐条一致：surface 底、divider 边、圆角 14、阴影、
    // headerChromeHeight() + 8 的顶边距、200ms EaseOut 的出入场。
    Row() {
      if (this.state.label !== '') {
        Row() {
          Text(this.state.label)
            .fontSize(12)
            .fontColor(COLOR_TEXT_PRIMARY)
            .fontWeight(FontWeight.Medium);
        }
        .height(28)
        .padding({ left: 12, right: 12 })
        // 浮动日期走与悬浮栏一致的稳定 bar 玻璃：厚度映射到锁定质量的模糊半径，
        // 滚动与停手期间始终是同一层，不触发 systemMaterial 的降级/恢复闪变。
        .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
        .backdropBlur(overlayBackdropBlur('bar'))
        .attributeModifier(materialModifierWhen('bar', this.materialEpoch >= 0))
        .border({ width: 0.5, color: $r('app.color.divider') })
        .borderRadius(14)
        .shadow({ radius: 5, color: '#22000000', offsetX: 0, offsetY: 2 })
        .clip(true);
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: this.topMargin })
    .opacity(this.state.shown ? 1 : 0)
    .scale({ x: this.state.shown ? 1 : 0.9, y: this.state.shown ? 1 : 0.9 })
    .translate({ y: this.state.shown ? 0 : -5 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
      curve: Curve.EaseOut
    })
    .hitTestBehavior(HitTestMode.None);
  }
}

// TimelineStatePill 的 V2 外壳。
//
// 胶囊本体是 V1 的 @Component（它用了 @Styles + stateStyles，那是 V1 专有的
// 写法），收不了 @Trace 对象。而"日期条在不在"这一位如果由 ChatPage.build 去
// 读，ChatPage 就又订阅回去了，整轮拆分白做。
//
// 所以在中间加这一层：本组件是 V2，它读 state.label 因而只订阅自己；往下仍然
// 按老样子传一个普通 boolean 进 V1 的 @Prop——ChatPage 原本就是这么传的（V2
// 父 → V1 子 @Prop），链路没变，胶囊本体一行没动。
@ComponentV2
export struct TimelineStatePillSlot {
  @Require @Param state: FloatingDateState;
  @Require @Param mode: string;
  @Require @Param label: string;
  @Require @Param topInset: number;
  @Event onRetry: () => void = (): void => {};

  build() {
    TimelineStatePill({
      mode: this.mode,
      label: this.label,
      topInset: this.topInset,
      // 判据逐字保留：原来是 `this.floatDate !== ''`，即"日期条这个节点还在不
      // 在"，而不是"它此刻可见不可见"。
      floatDateShown: this.state.label !== '',
      onRetry: (): void => { this.onRetry(); }
    });
  }
}
