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
// 官方给的办法是横向 + 纵向断点组合判断，按《断点系统》的 8 种屏幕形态逐一核对：
//
//   直板机竖屏 sm/lg 单栏   直板机横屏 md/sm 单栏（#125）  小方形屏 sm/md 单栏
//   大方形屏   md/md 分栏   大屏竖屏   md/lg 分栏          大屏横屏 lg/sm 分栏
//   超大屏     xl/sm 分栏   圆形屏     xs    单栏
//
// 结论与原来的「宽高都 ≥ 600vp」规则逐一相同，这次只换判据来源。
// 不用 NavigationMode.Auto：它只看宽度，正好会撞上 #125；而且还有「强制单栏」开关、
// 查看器盖满窗口等运行时回退——官方把这类情况列为手动断点切换的适用场景。
export function isSplitByBreakpoint(widthBp: number, heightBp: number,
  forceSingleColumn: boolean = false): boolean {
  if (forceSingleColumn) {
    return false;
  }
  if (widthBp < WIDTH_BP_MD) {
    return false;
  }
  return !(widthBp === WIDTH_BP_MD && heightBp === HEIGHT_BP_SM);
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
