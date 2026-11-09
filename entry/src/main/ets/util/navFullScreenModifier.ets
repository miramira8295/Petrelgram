// fullScreenOverlay 属性的**唯一**出口，理由和 materialModifier 一模一样：
// 这是 API 26 才有的组件属性，低版本运行时里方法根本不存在，**取方法那一步就抛**
// ——传 undefined 也救不了（参数还没轮到求值）。1.4.2「登录后进主界面必崩」就是
// 这么来的，别在页面里直接写 .fullScreenOverlay(...)。
//
// 所以版本闸放在 applyNormalAttribute 里面：版本不够就一次都不碰 instance，
// 连「摘掉」那一支也不碰。低版本的表现＝维持现状（查看器只铺满右栏）。
import { deviceInfo } from '@kit.BasicServicesKit';
import { fullScreenOverlayWinsAt } from './navFullScreen';

// deviceInfo 是设备常量，读一次。
const overlayAvailable: boolean = fullScreenOverlayWinsAt(deviceInfo.sdkApiVersion);

export function navFullScreenAvailable(): boolean {
  return overlayAvailable;
}

class NavFullScreenModifier implements AttributeModifier<NavDestinationAttribute> {
  private readonly wanted: boolean;

  constructor(wanted: boolean) {
    this.wanted = wanted;
  }

  applyNormalAttribute(instance: NavDestinationAttribute): void {
    if (!overlayAvailable) {
      return;
    }
    // 关掉那一支同样要显式设 false：修饰器会在同一个节点上反复跑，不摘的话
    // 查看器关了 ChatPage 还盖着整个窗口，左栏就再也回不来了。
    instance.fullScreenOverlay(this.wanted);
  }
}

// 两个实例够用（开/关），别每次 build 都 new 一个：ArkUI 对同一个节点反复应用
// 修饰器，换实例会让它每次都当成新的。
const ON: NavFullScreenModifier = new NavFullScreenModifier(true);
const OFF: NavFullScreenModifier = new NavFullScreenModifier(false);

export function navFullScreenModifier(wanted: boolean): AttributeModifier<NavDestinationAttribute> {
  return wanted ? ON : OFF;
}
