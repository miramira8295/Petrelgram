// 组件级光感（点光源 + 按压阴影）的**唯一**出口。
//
// **为什么不是 systemMaterial。** 系统把**组件级**的沉浸材质收回了——只有 HDS
// 导航级的栏（HdsNavigation/HdsNavDestination 的 titleBar、HdsTabs 的
// barFloatingStyle，都走 systemMaterialEffect）还拿得到玻璃和光感。证据：首页
// 搜索键有流光/按压形变（它画在标题栏的 stackBuilder 里 = 导航级），而 dock 里的
// 控件、顶栏菜单浮层这些组件级的面全都没有，同一台设备同一份判定
// （api=26 state=0 types=[101] material=true）。
//
// hdsEffect 是**另一条通道**：`HdsEffectBuilder` 造出 VisualEffect，挂到 ArkUI 的
// `.visualEffect()` 上，和 systemMaterial 无关，因此不受那次收回影响。
// 而且它是 **6.0.0(20)** 起——正好是本工程底线，不需要版本闸（不像
// barFloatingStyle / hdsMaterial 那些 23+ 的）。
//
// **玻璃仍然自绘**：这条路只给光效，不给毛玻璃。底色和模糊走
// plainGlassFill + plainBackdropBlur（那一对明确不指望材质）。
//
// `.visualEffect()` 的签名是 `visualEffect(effect: VisualEffect)`，**不收
// undefined**，所以"关掉"表示为一个空的 effect（builder 什么都不加就 build）。

import { hdsEffect } from '@kit.UIDesignKit';
import { MATERIAL_EPOCH, OverlaySurface, pointLightOn, pressShadowOn } from './overlayMaterial';
import { hdsMaterialLevelIndex } from './overlayMaterial';
import { HDS_LEVEL_EXQUISITE } from './materialTuning';

// 「精致」档给亮光源，其余档给柔光。档位本身由 materialTuning 归一化，
// 「平滑」档在 pointLightOn 那一步就已经关掉了，走不到这里。
function sourceTypeOf(levelIndex: number): hdsEffect.PointLightSourceType {
  return levelIndex === HDS_LEVEL_EXQUISITE
    ? hdsEffect.PointLightSourceType.BRIGHT
    : hdsEffect.PointLightSourceType.SOFT;
}

function buildEffect(surface: OverlaySurface): VisualEffect {
  const builder: hdsEffect.HdsEffectBuilder = new hdsEffect.HdsEffectBuilder();
  if (pointLightOn(surface)) {
    builder.pointLight({
      sourceType: sourceTypeOf(hdsMaterialLevelIndex()),
      // 边框 + 内容都照亮：只照边框在输入栏这种大面上几乎看不出来。
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      // color 不给 = 用系统默认光色（官方示例里 lightEffect 也是 color: undefined）。
      options: {}
    });
  }
  if (pressShadowOn(surface)) {
    builder.pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT);
  }
  return builder.buildEffect();
}

// 按「面 + 材质纪元」缓存：VisualEffect 每帧新建会白白产生对象，而用户改了
// 厚度/光感之后又必须换一份新的（和 materialModifier 的分代缓存同一个理由）。
const cache: Map<string, VisualEffect> = new Map<string, VisualEffect>();
let cachedEpoch: number = -1;

export function hdsVisualEffect(surface: OverlaySurface): VisualEffect {
  const epoch: number = AppStorage.get<number>(MATERIAL_EPOCH) ?? 0;
  if (epoch !== cachedEpoch) {
    cache.clear();
    cachedEpoch = epoch;
  }
  const hit = cache.get(surface);
  if (hit !== undefined) {
    return hit;
  }
  const built: VisualEffect = buildEffect(surface);
  cache.set(surface, built);
  return built;
}
