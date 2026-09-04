import { BOTTOM_DRAWER_HEIGHT, drawerBottomInset } from '../../util/drawerMetrics';
import {
  plainBackdropBlur, plainGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';

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
  @BuilderParam content: () => void;

  @Styles
  drawerCard() {
    // 毛玻璃走 'card' 档（和输入框胶囊同档）。这里有东西可透——抽屉底下铺着
    // 自己画的那份聊天背景，模糊的正是它。自绘玻璃的两半必须一起上：半透明底
    // + backdropBlur，不透明底会把模糊完全盖住。
    //
    // **改用 plain* 那一对**：原来是 overlayGlassFill / overlayBackdropBlur，
    // 它们在"材质可用"时会把模糊归 0、底色退成 25% 淡色，把观感让给材质——而
    // 系统已经把**组件级**的沉浸材质收回了（只剩 HDS 导航级的栏还有），于是这块
    // 面既没材质也没自己的玻璃。plain* 不看材质在不在，无条件自绘。
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .backdropBlur(plainBackdropBlur('card'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
    // 四角都圆：卡片四周都有空当，浮在壁纸上。
    .borderRadius(18)
    .clip(true)
    .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: -2 })
    // 光感走 hdsEffect 的另一条通道（visualEffect，6.0.0(20) 起，不受材质收回
    // 影响）。'card' 档只给点光源、不给按压阴影——整块面板跟着手指变形很怪。
    .visualEffect(hdsVisualEffect('card'))
  }

  build() {
    // 卡片贴着 Stack 顶，整条 drawerBottomInset 都落在卡片**下面**。原来是默认
    // 的居中对齐：卡片 + 8 的外边距被摆在 260 + inset 的中间，留出来的那一截
    // 一半跑到卡片上面去了，卡片下沿实际只离屏幕底 inset/2 + 4，「表情 / 贴纸
    // / GIF」那一条整个躺在系统手势带里（issue #154）。
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        this.content();
      }
      // calc 而不是 width('100%') + margin：后者是"满宽再往外推"，多出来的
      // 部分被 Stack 裁掉，看着仍然齐边——实测取色，左边缘 60px 全是卡片底色。
      // 两侧留白。抽屉在页面里，空当露出的就是这张壁纸本身——当它还是自定义
      // 键盘时做不到这一点（另一个图层，背后没有页面背景），才被迫齐边。
      .width('calc(100% - 16vp)')
      .height(this.drawerHeight)
      .drawerCard();
    }
    .width('100%')
    .height(this.drawerHeight + drawerBottomInset(this.bottomSafe))
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
