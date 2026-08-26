// 消息行外壳（ReusableMessageBubble，@ReusableV2）的**全局复用池**接线。
//
// 这个模块目前只做一件事：判定当前设备走不走全局池（API 26 起）。
//
// 池本身在**哪里**声明，不在这里 —— 装饰器参数是编译期的，写在 ChatPage.ets
// 的池宿主组件上（见那边 ChatPagePoolHost 的注释）。这里只放能脱离 UI 单测
// 的纯逻辑，外加一层薄薄的运行时封装。
//
// ── 双路径 ────────────────────────────────────────────────────────────────
// 全局复用池是 API 26 起的能力，而本仓 compatibleSdkVersion 是 6.0.0(20)。
// 形状照抄 util/overlayMaterial.ets：一个 `xxxWinsAt(apiVersion)` 纯函数 +
// 一个模块级常量把设备版本喂进去，调用点全部在这个常量之后。
//
// 并且**绝不在模块级解引用任何 API 26 才有的东西**。overlayMaterial 的文件头
// 记着 1.3.6 就是这么挂的：把 uiMaterial.ImmersiveStyle 提成模块级常量之后，
// 低版本设备上模块一加载就抛，整个应用启动即崩。这里的对应物是池宿主组件
// 上那份装饰器配置：编译产物里它是**类字段初始化器**
// （`__reusePool__Internal = __ReusePool__Internal.create(...)`），只在构造
// 函数里跑，所以「类定义存在」不等于「碰过 API 26」——真正的闸门是那条
// `if (globalReusePoolAvailable())` 决定要不要 new 它。

import { deviceInfo } from '@kit.BasicServicesKit';

// 全局复用池的起始版本（官方《全局复用：集中化的组件回收与复用》：
// 「全局复用池功能从 API 版本 26.0.0 开始支持」）。
const GLOBAL_REUSE_POOL_API: number = 26;

// 与 overlayMaterial.materialWinsAt 同形：判定规则单独成纯函数，好让它在没有
// 设备的情况下被单测钉住。
export function globalReusePoolWinsAt(apiVersion: number): boolean {
  return apiVersion >= GLOBAL_REUSE_POOL_API;
}

// deviceInfo 是设备常量，官方建议读一次而不是每帧读。
const poolAvailable: boolean = globalReusePoolWinsAt(deviceInfo.sdkApiVersion);

export function globalReusePoolAvailable(): boolean {
  return poolAvailable;
}
