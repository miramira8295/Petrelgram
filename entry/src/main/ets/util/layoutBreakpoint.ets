import { DOCK_MODE_BOTTOM, DOCK_MODE_LEFT_FLOATING } from './splitMetrics';

// 系统断点（官方《一次开发，多端部署》断点体系）。
//
// 写入端：EntryAbility 用 UIContext.getWindowWidthBreakpoint() /
// getWindowHeightBreakpoint() 取值，存进 AppStorage 的下面两个键，窗口尺寸变化时更新。
// 消费端：@StorageProp 读这两个键，再交给本文件的纯函数判断。
//
// 【为什么用数字而不是 WidthBreakpoint 枚举类型】两个枚举是 SDK 的全局声明，本地单测
// （宿主环境）运行时未必有定义；判据放在纯函数里要能单测。所以这里定义与系统枚举
// **数值逐一相同**的常量，写入端存 getWindowWidthBreakpoint() 的原值，全链路按数字
// 比较——官方要求的「写入与消费类型一致」在这条链上成立。常量值由单测钉住。

export const KEY_WIDTH_BREAKPOINT: string = 'currentWidthBreakpoint';
export const KEY_HEIGHT_BREAKPOINT: string = 'currentHeightBreakpoint';
// 窗口是不是纵向（高 > 宽）。纵向断点只分三档，折叠屏展开态横竖都落在 md（类方形），
// 光看断点分不出横竖，分栏判据要再看这一位。写入端同 EntryAbility.publishBreakpoints。
// 读不到时按纵向（true）：单栏是更保守的一边。
export const KEY_WINDOW_PORTRAIT: string = 'windowPortrait';

// 横向断点：按窗口宽（vp）。xs <320，sm [320,600)，md [600,840)，lg [840,1440)，xl ≥1440。
export const WIDTH_BP_XS: number = 0;
export const WIDTH_BP_SM: number = 1;
export const WIDTH_BP_MD: number = 2;
export const WIDTH_BP_LG: number = 3;
export const WIDTH_BP_XL: number = 4;

// 纵向断点：按窗口高宽比。sm <0.8（横向窗口），md [0.8,1.2)（类方形），lg ≥1.2（纵向窗口）。
export const HEIGHT_BP_SM: number = 0;
export const HEIGHT_BP_MD: number = 1;
export const HEIGHT_BP_LG: number = 2;

// 会不会分栏（HdsNavigation 设成 Split 还是 Stack）。
//
// 官方默认规则是「宽度 sm 单栏、md 起分栏」，但照搬会把**直板机横屏**（md 宽 + sm
// 高宽比，例如 809×376vp）判成分栏——#125：全屏看视频把窗口转横，整个应用被强制分栏。
// 官方给的办法是横向 + 纵向断点组合判断。2026-09-27 用户定：**竖着直板，横着分栏**——
// 平板、折叠屏展开态竖屏都按直板机的样子走，横过来够宽才分栏。折叠屏展开态横竖都是
// md/md，断点分不出，所以另看 windowPortrait（窗口高 > 宽）。按《断点系统》逐一核对：
//
//   直板机竖屏 sm/lg 单栏   直板机横屏 md/sm 单栏（#125）  小方形屏 sm/md 单栏
//   大方形屏   md/md 竖单栏、横分栏                        大屏竖屏 md/lg、lg/lg 单栏
//   大屏横屏   lg/sm 分栏   超大屏 xl/sm 分栏             圆形屏   xs 单栏
//
// 不用 NavigationMode.Auto：它只看宽度，正好会撞上 #125；而且还有「强制单栏」开关、
// 查看器盖满窗口等运行时回退——官方把这类情况列为手动断点切换的适用场景。
export function isSplitByBreakpoint(widthBp: number, heightBp: number,
  forceSingleColumn: boolean, windowPortrait: boolean): boolean {
  if (forceSingleColumn || windowPortrait) {
    return false;
  }
  if (widthBp < WIDTH_BP_MD || heightBp === HEIGHT_BP_LG) {
    return false;
  }
  return !(widthBp === WIDTH_BP_MD && heightBp === HEIGHT_BP_SM);
}

// 应用默认允不允许跟随传感器转屏（2026-09-27 用户定：手机锁竖屏，大屏可转）。
//
// 官方《窗口旋转实践案例》：按设备类型分支会漏掉新形态，要用断点屏蔽设备差异。
// 这里看的是**物理屏幕**的短边（不是窗口：窗口会随分屏 / 悬浮变小，拿它判会把
// 平板分屏也锁成竖屏）。短边 ≥ 600vp（横向断点 md 的下沿）才放开旋转：
//   直板机 / 折叠屏折叠态 / 小方形外屏 → 锁竖屏；平板 / 折叠屏展开态 → 可转。
// 读不到尺寸（0/NaN）时按手机处理，锁竖屏是更保守的一边。
export function allowsRotationForDisplay(widthPx: number, heightPx: number,
  densityPixels: number): boolean {
  if (!(widthPx > 0) || !(heightPx > 0) || !(densityPixels > 0)) {
    return false;
  }
  return Math.min(widthPx, heightPx) / densityPixels >= 600;
}

// 官方 BreakpointType：按横向断点取值，缺的档位向下回退到最近的一档。
export class BreakpointType<T> {
  private sm: T;
  private md?: T;
  private lg?: T;
  private xl?: T;

  constructor(sm: T, md?: T, lg?: T, xl?: T) {
    this.sm = sm;
    this.md = md;
    this.lg = lg;
    this.xl = xl;
  }

  getValue(widthBp: number): T {
    if (widthBp >= WIDTH_BP_XL) {
      return this.xl ?? this.lg ?? this.md ?? this.sm;
    }
    if (widthBp === WIDTH_BP_LG) {
      return this.lg ?? this.md ?? this.sm;
    }
    if (widthBp === WIDTH_BP_MD) {
      return this.md ?? this.sm;
    }
    return this.sm;
  }
}

// 按官方阈值从窗口尺寸推断点。**只在拿不到系统值的时刻用**：EntryAbility 在
// loadContent 之前按启动时的窗口尺寸播一个初值（否则平板第一帧按默认 sm 画成单栏、
// 下一帧跳成分栏），loadContent 回调里立刻被系统接口的值覆盖。
export function widthBreakpointOfVp(widthVp: number): number {
  if (!(widthVp >= 320)) {
    return WIDTH_BP_XS;
  }
  if (widthVp < 600) {
    return WIDTH_BP_SM;
  }
  if (widthVp < 840) {
    return WIDTH_BP_MD;
  }
  return widthVp < 1440 ? WIDTH_BP_LG : WIDTH_BP_XL;
}

// 纵向断点 = 高宽比。高度读不到（0/NaN）时给 lg：等价于原来「高度未知只看宽度」的退路。
export function heightBreakpointOfSize(widthVp: number, heightVp: number): number {
  if (!(widthVp > 0) || !(heightVp > 0)) {
    return HEIGHT_BP_LG;
  }
  const ratio: number = heightVp / widthVp;
  if (ratio < 0.8) {
    return HEIGHT_BP_SM;
  }
  return ratio < 1.2 ? HEIGHT_BP_MD : HEIGHT_BP_LG;
}

// 页签栏（dock）形态：分栏 = 左栏底部自绘胶囊，其余 = 底部胶囊（2026-09-17 用户定，
// 只分这两种）。判据与分栏同源。
export function dockModeForBreakpoint(widthBp: number, heightBp: number,
  forceSingleColumn: boolean, windowPortrait: boolean): string {
  return isSplitByBreakpoint(widthBp, heightBp, forceSingleColumn, windowPortrait)
    ? DOCK_MODE_LEFT_FLOATING : DOCK_MODE_BOTTOM;
}

// 小方形屏（官方 SPEC-04：宽度 sm + 高宽比 md，典型是 Pura X 外屏 / 阔折叠折叠态）。
// 屏幕高度小，标题栏与底部页签占比大，这一档做紧凑标题与沉浸式浏览。
export function isSmallSquare(widthBp: number, heightBp: number): boolean {
  return widthBp === WIDTH_BP_SM && heightBp === HEIGHT_BP_MD;
}
