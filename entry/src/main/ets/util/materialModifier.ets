import { MATERIAL_EPOCH, OverlaySurface, immersiveMaterialAvailable, overlayMaterial } from './overlayMaterial';

// systemMaterial 属性的**唯一**出口。
//
// .systemMaterial(...) 是 API 26 才有的组件属性。直接链式调用的话，方法本身
// 在低版本运行时里就不存在，页面一构建就抛——这不是"参数传 undefined 会被
// 忽略"能救的：炸在取方法那一步，参数还没轮到求值。全应用底线是 6.0.0(20)，
// 所以任何页面都不允许直接写 .systemMaterial(...)。
//
// 出口收在 AttributeModifier 里：apply 时**先问版本**
// （immersiveMaterialAvailable），版本不够就一次都不碰 instance.systemMaterial
// ——包括"清除"那一支。清除同样要先取到方法，`systemMaterial(undefined)` 在
// API 20 上和 `systemMaterial(材质)` 一样炸。这是 1.4.2 登录后进主界面必崩的
// 原因（栈顶就是本文件；overlayMaterial 内部那道版本闸门救不了，它只管参数值，
// 而取方法发生在求参数之前）。
//
// 版本够了之后才谈"挂还是清"：那一层由 overlayMaterial 的返回值决定（厚度调到
// 「关闭」、省电、面不参与材质时它返回 undefined），此时传 undefined 是**必要**
// 的——修饰器会在同一个节点上反复跑，不清的话上一次挂上的材质会一直留着。
//
// 低版本上观感由各调用点自己的 backdropBlur/overlayGlassFill 降级路径接住，
// 和以前一致。
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
    // API 26 以下这个方法根本不存在，取它就抛。连清除都不能调。
    if (!immersiveMaterialAvailable()) {
      return;
    }
    if (!this.enabled) {
      instance.systemMaterial(undefined); // 从开到关也要清，不然气泡离屏后材质还挂着
      return;
    }
    // 没有材质（厚度调到「关闭」、省电、这个面不参与材质）时必须显式清掉：
    // 修饰器会在同一个节点上反复跑，不清的话上一次挂上的材质就一直留在那儿
    // ——用户把厚度关掉后 dock 还是玻璃，就是这个原因。
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
