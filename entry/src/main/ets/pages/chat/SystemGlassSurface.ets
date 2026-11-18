// 系统沉浸材质玻璃面板（2026-11-18，全应用统一改造的公共外壳）。
//
// 【为什么要这个外壳】
// 系统沉浸材质（systemMaterial / ImmersiveMaterial）只画在白名单宿主里，内容区唯一
// 「既在白名单、又能任意定尺寸」的是 Toggle（见 pages/chat/NativeGlassHost.ets 的
// 文件头与官方《沉浸光感》排查）。所以任何自绘玻璃面要换成系统材质，都必须：
//   ① 用 Stack 把「一层 Toggle 材质」垫在内容下面；
//   ② 材质层需要**明确的绝对尺寸**（vp），不能靠百分比。
// 本组件就是把 ①② 收成一处：自己量内容尺寸，垫一层材质，再把内容画在上面。
//
// 【用法】调用方把原来挂在内容上的「定位类」属性（margin / width / height /
// layoutWeight / position）**移到本组件上**，内容本身只保留自己的排版属性：
//
//   SystemGlassSurface({ radius: 14 }) {
//     Row() { ... }
//       .backgroundColor(Color.Transparent)   // 底色交给材质层
//   }
//   .margin({ left: 12, right: 12 })
//
// 内容里不要再写 backgroundColor / backdropBlur / visualEffect：底色和模糊都由
// 材质层承担，自绘底色会把材质盖住（同一 BackgroundFilter 后写的赢）。
//
// 【为什么量的是外层 Stack】量内容自己是拿不到「含内边距的完整盒子」的（输入栏
// 第一版就吃过这个 6px 的亏）。外层 Stack 的尺寸 = 内容的尺寸，直接量它即可。

import { immersiveMaterialAvailable, OverlaySurface } from '../../util/overlayMaterial';
import { NativeGlassHost } from './NativeGlassHost';

@ComponentV2
export struct SystemGlassSurface {
  // 圆角：照抄调用方原来的 borderRadius（材质层要圆角才不会露出方角）。
  @Param radius: number = 14;
  // 已知固定尺寸时直接给，省掉一帧测量；0 = 自己量（全宽卡片用这个）。
  @Param fixedWidth: number = 0;
  @Param fixedHeight: number = 0;
  // 铺满父容器（父容器自己管尺寸：layoutWeight / calc / 固定值都行）。自适应宽度
  // 的面（顶栏身份胶囊、整条搜索条）用它：直接给百分比，材质层仍按量到的像素铺。
  @Param fill: boolean = false;

  // 深色只影响材质不可用时的降级底色，由调用方透传（V2 不能用 @StorageProp）。
  @Param dark: boolean = false;
  // 材质面（同 overlayMaterial 档位）：'menu' 默认；看图/看视频的控制条传 'viewer'。
  @Param surface: OverlaySurface = 'menu';

  @Local private mw: number = 0;
  @Local private mh: number = 0;

  @BuilderParam content: () => void;

  private glassOn(): boolean {
    return immersiveMaterialAvailable() && this.w() > 0.5 && this.h() > 0.5;
  }

  private w(): number {
    return this.fixedWidth > 0 ? this.fixedWidth : this.mw;
  }

  private h(): number {
    return this.fixedHeight > 0 ? this.fixedHeight : this.mh;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.glassOn()) {
        NativeGlassHost({
          hostWidth: this.w(),
          hostHeight: this.h(),
          hostRadius: this.radius,
          dark: this.dark,
          surface: this.surface
        });
      }
      this.content();
    }
    // fill：铺满父容器；否则按 fixed* / 自量尺寸（'auto' 与不写等价）。
    .width(this.fill ? '100%' : (this.fixedWidth > 0 ? this.fixedWidth : 'auto'))
    .height(this.fill ? '100%' : (this.fixedHeight > 0 ? this.fixedHeight : 'auto'))
    .onAreaChange((_old: Area, area: Area): void => {
      const w: number = area.width as number;
      const h: number = area.height as number;
      // 差值小于半像素不写回，避免测量抖动引起的重建风暴。
      if (Math.abs(w - this.mw) > 0.5) {
        this.mw = w;
      }
      if (Math.abs(h - this.mh) > 0.5) {
        this.mh = h;
      }
    });
  }
}
