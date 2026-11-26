import { edgeBlurStopsEx } from './scrollEdgeBlur';

/**
 * 滚动边缘渐变模糊（linearGradientBlur）的统一属性修饰器。
 *
 * 【为什么不能直接链式写 `.linearGradientBlur(0, ...)`】
 * 真机 RenderService 树（Mate 70 Pro+，`hidumper -s RenderService -a 'RSTree'`）与 trace 实测：
 * 即使传入 `blurRadius = 0` 且 `fractionStops` 全为 0，ArkUI 仍会向 Rosen 提交
 * `LinearGradientBlurPara`，导致整屏滚动容器挂上 `NeedFilter[true]` +
 * `RSLinearGradientBlurFilterBlur(radius: 0)`。任意子节点刷新（如贴纸帧切换或滚动）都会把
 * 脏区扩成整屏、清空 FilterCache 并每帧触发整屏 `TakeSnapshot` 与多 Pass GPU 合成。
 *
 * 通过 AttributeModifier 按需挂载：
 *   1. 默认关闭（从未开启）时完全不调用 `instance.linearGradientBlur(...)`，Rosen 不建滤镜节点；
 *   2. 开启时才设置半径与 stops，并按参数签名缓存实例，避免无关重渲染反复分配与下发；
 *   3. 从开启切回关闭时显式调用 `linearGradientBlur(undefined, undefined)` 清除滤镜。
 */
export class ScrollEdgeBlurModifier implements AttributeModifier<CommonAttribute> {
  readonly radius: number;
  readonly viewH: number;
  readonly fallbackH: number;
  readonly topOffsetVp: number;
  readonly topOn: boolean;
  readonly bottomOn: boolean;
  readonly reset: boolean;

  constructor(
    radius: number,
    viewH: number,
    fallbackH: number = 780,
    topOffsetVp: number = 0,
    topOn: boolean = false,
    bottomOn: boolean = false,
    reset: boolean = false
  ) {
    this.radius = radius;
    this.viewH = viewH;
    this.fallbackH = fallbackH;
    this.topOffsetVp = topOffsetVp;
    this.topOn = topOn;
    this.bottomOn = bottomOn;
    this.reset = reset;
  }

  get active(): boolean {
    return this.radius > 0 && (this.topOn || this.bottomOn);
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (this.active) {
      instance.linearGradientBlur(this.radius, {
        fractionStops: edgeBlurStopsEx(this.viewH, this.fallbackH, this.topOffsetVp, this.topOn, this.bottomOn),
        direction: GradientDirection.Bottom
      });
    } else if (this.reset) {
      instance.linearGradientBlur(undefined, undefined);
    }
  }
}

const NOOP_EDGE_BLUR_MODIFIER: ScrollEdgeBlurModifier =
  new ScrollEdgeBlurModifier(0, 780, 780, 0, false, false, false);

const CLEAR_EDGE_BLUR_MODIFIER: ScrollEdgeBlurModifier =
  new ScrollEdgeBlurModifier(0, 780, 780, 0, false, false, true);

/**
 * 单个滚动容器持有的边缘虚化绑定器：
 * - 未开启过时稳定返回 NOOP 单例（零分配、零 linearGradientBlur 调用）；
 * - 开启且参数未变时复用同一修饰器实例；
 * - 开启→关闭时返回 CLEAR 单例清除先前挂载的滤镜。
 *
 * 【全应用唯一范式（2026-11-26 统一）】
 * 第一个参数（半径）必须由开关算出来，不要在页面里另外写三元：
 *   · 常规页面：edgeBlurRadiusOf(topOn || bottomOn)
 *   · 两处资料页：edgeBlurRadiusWhileMorphing(avatarMorphing, topOn, bottomOn)
 * 顶/底带宽（118vp）、峰值半径（22vp）、曲线、fallbackH（780）、topOffsetVp（0）全在
 * util/scrollEdgeBlur.ets 的常量里，页面只传「开关」与「容器高度」。
 * 禁止按滚动状态（onScrollStart/onScrollStop）或滚动量去改半径：那会让手指一动虚化消失、
 * 或者静止不糊一动才糊，与其他页面观感不一致（最后两处这种写法已于 2026-11-26 清掉）。
 */
export class ScrollEdgeBlurBinder {
  private hasApplied: boolean = false;
  private lastKey: string = '';
  private cached: ScrollEdgeBlurModifier = NOOP_EDGE_BLUR_MODIFIER;

  bind(
    radius: number,
    viewH: number,
    topOn: boolean,
    bottomOn: boolean,
    fallbackH: number = 780,
    topOffsetVp: number = 0
  ): ScrollEdgeBlurModifier {
    const active: boolean = radius > 0 && (topOn || bottomOn);
    if (!active) {
      this.lastKey = '';
      if (this.hasApplied) {
        this.cached = CLEAR_EDGE_BLUR_MODIFIER;
        return CLEAR_EDGE_BLUR_MODIFIER;
      }
      this.cached = NOOP_EDGE_BLUR_MODIFIER;
      return NOOP_EDGE_BLUR_MODIFIER;
    }
    const key: string = `${radius}:${Math.round(viewH)}:${fallbackH}:${topOffsetVp}:${topOn ? 1 : 0}:${bottomOn ? 1 : 0}`;
    if (this.hasApplied && this.lastKey === key) {
      return this.cached;
    }
    this.hasApplied = true;
    this.lastKey = key;
    this.cached = new ScrollEdgeBlurModifier(radius, viewH, fallbackH, topOffsetVp, topOn, bottomOn, false);
    return this.cached;
  }
}
