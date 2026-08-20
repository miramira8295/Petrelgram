import { BOTTOM_DRAWER_HEIGHT, DRAWER_INSET } from '../../util/drawerMetrics';
import {
  overlayBackdropBlur, overlayGlassFill, overlayMaterial
} from '../../util/overlayMaterial';

// 底部抽屉（附件 / 表情贴纸）共用的那身外壳。
//
// 两个抽屉此前各写了一份**逐行相同**的外壳——同样的 calc 宽度、同样的高度加
// 安全区、同样的裁剪与透明底，连解释为什么的那二十行注释都是复制的。内容不同
// 的只有卡片里装什么，所以外壳收成一处，内容用 @BuilderParam 传进来。
//
// 下面这些"为什么"是实测得来的，别按直觉改：

// 抽屉下沿要把系统手势条那一截算进来，否则卡片被压着。用一半、封顶 12 而不是
// 整条 bottomSafe：手势条本身只占安全区的一小条，全留就显得下面空了一大块。
export function drawerBottomInset(bottomSafe: number): number {
  return Math.min(12, Math.round(bottomSafe / 2));
}

@Component
export struct BottomDrawerShell {
  @Prop bottomSafe: number;
  @BuilderParam content: () => void;

  @Styles
  drawerCard() {
    // 毛玻璃/沉浸光感走 'card' 档（和输入框胶囊同档）。这里有东西可透——
    // 抽屉底下铺着自己画的那份聊天背景，模糊的正是它。
    // 自绘玻璃的两半必须一起上：半透明底 + backdropBlur，不透明底会把模糊
    // 完全盖住。材质接管时这两者自动让位（overlayGlassFill 交回实心色、
    // overlayBackdropBlur 归 0）。
    .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('card'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
    // 四角都圆：卡片四周都有空当，浮在壁纸上。
    .borderRadius(18)
    .clip(true)
    .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: -2 })
    .systemMaterial(overlayMaterial('card'))
  }

  build() {
    Stack() {
      Column() {
        this.content();
      }
      // calc 而不是 width('100%') + margin：后者是"满宽再往外推"，多出来的
      // 部分被 Stack 裁掉，看着仍然齐边——实测取色，左边缘 60px 全是卡片底色。
      // 两侧留白。抽屉在页面里，空当露出的就是这张壁纸本身——当它还是自定义
      // 键盘时做不到这一点（另一个图层，背后没有页面背景），才被迫齐边。
      .width('calc(100% - 16vp)')
      .height(BOTTOM_DRAWER_HEIGHT)
      .margin({ bottom: DRAWER_INSET })
      .drawerCard();
    }
    .width('100%')
    .height(BOTTOM_DRAWER_HEIGHT + drawerBottomInset(this.bottomSafe))
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
