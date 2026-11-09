import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavigationAttribute } from '@kit.UIDesignKit';

// HdsNavigation 的 enableVisibilityLifecycleWithContentCover 要 **6.1.0(23)**，
// 而本应用的 compatibleSdkVersion 是 6.0.0(20)。差这三级的后果不是"属性不生效"
// 而是**整个应用起不来**：属性链在运行时就是一串方法调用，方法不存在时
// ArkTS 抛 `TypeError: undefined is not callable`，四个路由容器（聊天/联系人/
// 设置/个人资料）里哪一个先 build 就在哪一个崩。
//
// 手机模拟器（Pura X View，HarmonyOS 6.0.0(20)）上实测：登录成功、TDLib 进
// authorizationStateReady 之后立刻 jscrash，栈顶就是 ChatListPage 的这一行。
// 平板那台是 API 26，属性存在，所以整轮平板验证一次都没暴露出来——这正是
// "只在高版本设备上验"会漏掉的那一类问题。
//
// **为什么不能照 hdsTitleBar 那样用 sdkApiVersion 直接挡。**
// 那里挡的是**取值**（IMMERSIVE_GRADIENT_BLUR 这一档枚举），方法本身一直在，
// 三元运算符换个参数就完事。这里缺的是**方法**，而 ArkTS 的属性链是固定语法，
// 中间插不进 if。官方给的口子是 attributeModifier——它把属性的应用推迟到一个
// 普通函数里，那里面就能正常写条件了。HdsNavigationAttribute extends
// CommonMethod<HdsNavigationAttribute>，所以这个口子对它是开的。
//
// **跳过它在低版本上是安全的，不是"降级凑合"。**
// 这个属性关的是"全模态与 NavDestination 生命周期联动"——而那套联动本身就是
// 6.1.0(23) 引入的。API 20 上没有联动可关，跳过之后行为与显式关闭一致：
// ChatPage 拉起转发/表态面板时不会收到 onHidden，音视频不会被停掉。
const VISIBILITY_LIFECYCLE_API: number = 23;

// 取一次就够——deviceInfo.sdkApiVersion 在进程生命周期内不会变，而这个判断
// 会在每次 build 时被问到。
const linkageAvailable: boolean = deviceInfo.sdkApiVersion >= VISIBILITY_LIFECYCLE_API;

class SheetLifecycleModifier implements AttributeModifier<HdsNavigationAttribute> {
  applyNormalAttribute(instance: HdsNavigationAttribute): void {
    if (!linkageAvailable) {
      return;
    }
    instance.enableVisibilityLifecycleWithContentCover(false);
  }
}

// 四个路由容器共用一份：modifier 无状态，每页各 new 一个只是白白多占对象。
export const SHEET_LIFECYCLE_MODIFIER: SheetLifecycleModifier = new SheetLifecycleModifier();
