import { BOTTOM_DRAWER_HEIGHT, drawerBottomInset } from '../../util/drawerMetrics';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { SystemGlassSurface } from './SystemGlassSurface';

// 底部抽屉（附件 / 表情贴纸）共用的那身外壳。
//
// 两个抽屉此前各写了一份**逐行相同**的外壳——同样的 calc 宽度、同样的高度加
// 安全区、同样的裁剪与透明底，连解释为什么的那二十行注释都是复制的。内容不同
// 的只有卡片里装什么，所以外壳收成一处，内容用 @BuilderParam 传进来。
//
// 下面这些"为什么"是实测得来的，别按直觉改：

@Component
export struct BottomDrawerShell {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @Prop bottomSafe: number;
  @Prop drawerHeight: number = BOTTOM_DRAWER_HEIGHT;
  @Prop shellHeight: number = -1;
  @Prop topOverlap: number = 0;
  @Prop cardOffsetY: number = 0;
  @Prop cardOpacity: number = 1;
  @Prop imeOverlapRatio: number = 0;
  @BuilderParam content: () => void;

  private visibleShellHeight(): number {
    if (this.shellHeight >= 0) {
      return this.shellHeight > 0 ? Math.max(0, this.shellHeight + Math.max(0, this.topOverlap)) : 0;
    }
    const full: number = this.drawerHeight + drawerBottomInset(this.bottomSafe);
    const ratio: number = Math.min(1, Math.max(0, this.imeOverlapRatio));
    return Math.max(0, full * (1 - ratio));
  }

  build() {
    // 卡片贴着 Stack 顶，整条 drawerBottomInset 都落在卡片**下面**。原来是默认
    // 的居中对齐：卡片 + 8 的外边距被摆在 260 + inset 的中间，留出来的那一截
    // 一半跑到卡片上面去了，卡片下沿实际只离屏幕底 inset/2 + 4，「表情 / 贴纸
    // / GIF」那一条整个躺在系统手势带里（issue #154）。
    Stack({ alignContent: Alignment.Top }) {
      // 卡片的玻璃交给系统沉浸材质（SystemGlassSurface 垫一层 Toggle 材质）。
      // 这是"整块面板"级的面：材质自带模糊与 25% 淡底，所以原来那三件
      // （半透明底 / backdropBlur / visualEffect）全部撤掉，否则底色会把材质盖死。
      Stack() {
        SystemGlassSurface({ radius: 18, fixedHeight: this.drawerHeight }) {
          Column() {
            this.content();
          }
          .width('100%')
          .height('100%');
        }
      }
      // calc 而不是 width('100%') + margin：后者是"满宽再往外推"，多出来的
      // 部分被 Stack 裁掉，看着仍然齐边——实测取色，左边缘 60px 全是卡片底色。
      // 两侧留白。抽屉在页面里，空当露出的就是这张壁纸本身——当它还是自定义
      // 键盘时做不到这一点（另一个图层，背后没有页面背景），才被迫齐边。
      .width('calc(100% - 16vp)')
      .height(this.drawerHeight)
      .translate({ y: this.cardOffsetY })
      .opacity(this.cardOpacity)
      .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: -2 });
    }
    .width('100%')
    .height(this.visibleShellHeight())
    .margin({ top: this.shellHeight > 0 && this.topOverlap > 0 ? -this.topOverlap : 0 })
    // **必须裁剪**。背景层内部按整屏尺寸绘制（CachedImage 的 box 是
    // screenW × screenH），限了高度但不裁的话图会溢出到键盘区外面，把输入框
    // 整个盖住——实测就是这样，中间还多出一条颜色对不上的壁纸。
    .clip(true)
    // 透明：空当里露出的是页面那张壁纸本身。背景层加了
    // expandSafeArea([SafeAreaType.KEYBOARD]) 之后不再被键盘压缩，一直铺满
    // 整屏，所以这里透出来的和上面是**同一张图的同一处**，不可能对不齐。
    .backgroundColor(Color.Transparent);
  }
}
