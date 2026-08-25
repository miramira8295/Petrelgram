import { MATERIAL_EPOCH, OverlaySurface, overlayMaterial } from './overlayMaterial';

// systemMaterial 属性的**唯一**出口。
//
// .systemMaterial(...) 是 API 26 才有的组件属性。直接链式调用的话，方法本身
// 在低版本运行时里就不存在，页面一构建就抛——这不是"参数传 undefined 会被
// 忽略"能救的：炸在取方法那一步，参数还没轮到求值。全应用底线是 6.0.0(20)，
// 所以任何页面都不允许直接写 .systemMaterial(...)。
//
// 出口收在 AttributeModifier 里：apply 时先问 overlayMaterial —— 它内部有
// 26 的版本闸门，低版本返回 undefined —— 拿不到材质就**根本不碰**那个方法。
// 于是"调不调"由运行时版本决定，构造上就安全，不依赖任何"低版本会忽略"
// 的猜测。低版本上观感由各调用点自己的 backdropBlur/overlayGlassFill 降级
// 路径接住，和以前一致。
//
// 修饰器按面缓存：apply 每次都现取材质，材质缓存（含用户厚度/光感档位）在
// overlayMaterial 里自己失效，这里不用管。
export class SurfaceMaterialModifier implements AttributeModifier<CommonAttribute> {
  private readonly surface: OverlaySurface;
  private readonly enabled: boolean;

  constructor(surface: OverlaySurface, enabled: boolean = true) {
    this.surface = surface;
    this.enabled = enabled;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (!this.enabled) {
      instance.systemMaterial(undefined); // 从开到关也要清，不然气泡离屏后材质还挂着
      return;
    }
    // 没有材质（厚度调到「关闭」、省电、API 不够）时必须显式清掉：修饰器会在
    // 同一个节点上反复跑，不清的话上一次挂上的材质就一直留在那儿——用户把厚度
    // 关掉后 dock 还是玻璃，就是这个原因。
    instance.systemMaterial(overlayMaterial(this.surface));
  }
}

const cache: Map<string, SurfaceMaterialModifier> = new Map<string, SurfaceMaterialModifier>();

export function materialModifier(surface: OverlaySurface): SurfaceMaterialModifier {
  return materialModifierWhen(surface, true);
}

// Transition-heavy destinations can build a flat first frame and enable the
// material after onShown. Keep both variants cached so a state-driven rebuild
// does not allocate another modifier for every surface.
// 缓存按 MATERIAL_EPOCH 分代：epoch 一变就换一批新实例。ArkUI 对同一个修饰器
// 实例不一定重新 apply，用户改了厚度/关闭材质时 dock 就是这样卡在旧材质上的。
let cachedEpoch: number = -1;

export function materialModifierWhen(surface: OverlaySurface, enabled: boolean): SurfaceMaterialModifier {
  const epoch: number = AppStorage.get<number>(MATERIAL_EPOCH) ?? 0;
  if (epoch !== cachedEpoch) {
    cache.clear();
    cachedEpoch = epoch;
  }
  const key: string = `${surface}:${enabled ? 'on' : 'off'}`;
  const hit = cache.get(key);
  if (hit !== undefined) {
    return hit;
  }
  const built = new SurfaceMaterialModifier(surface, enabled);
  cache.set(key, built);
  return built;
}
